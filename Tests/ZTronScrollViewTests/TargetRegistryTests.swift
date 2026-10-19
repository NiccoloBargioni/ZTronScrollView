import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

@MainActor
final class ItemsModel: ObservableObject {
    @Published var ids = [0, 1, 2, 3]
    @Published var tallID: Int?
}

/// A stack of 100 pt items, each registered with `ztronScrollID`; one can grow to 200 pt (a reflow).
struct ItemsView: View {
    let state: ZTronScrollState
    @ObservedObject var model: ItemsModel
    var axes: Axis.Set = .vertical

    var body: some View {
        ZTronScrollView(axes, state: state) {
            VStack(spacing: 0) {
                ForEach(model.ids, id: \.self) { id in
                    Color.blue.frame(height: model.tallID == id ? 200 : 100).ztronScrollID(id)
                }
            }
        }
    }
}

@MainActor
@Suite(.serialized)
struct TargetRegistryTests {
    // MARK: registry unit

    @Test(arguments: OSPath.allCases) func registerIsGuardedAndNotifiesTheState(path: OSPath) {
        let s = makeState(path)
        let r = s.targets
        ZTronRenderCounters.reset()
        r.register("a", frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(r.frame(of: "a") == CGRect(x: 0, y: 0, width: 100, height: 50) && r.writes == 1 && r.version == 1)
        #expect(ZTronRenderCounters.value("registry.frameChanged") == 1)
        r.register("a", frame: CGRect(x: 0, y: 0, width: 100, height: 50))             // unchanged: nothing happens
        #expect(r.writes == 1 && r.version == 1 && ZTronRenderCounters.value("registry.frameChanged") == 1)
        r.register("a", frame: CGRect(x: 0, y: 10, width: 100, height: 50))
        #expect(r.writes == 2 && r.version == 2 && ZTronRenderCounters.value("registry.frameChanged") == 2)
        r.register("bad", frame: CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1))           // non-finite frames are ignored
        #expect(r.frame(of: "bad") == nil && r.writes == 2)
        r.unregister("a")
        #expect(r.frame(of: "a") == nil && r.writes == 3)
        r.unregister("a")
        #expect(r.writes == 3)
        #expect((s.targetRegistry as AnyObject?) === r)
    }

    @Test(arguments: OSPath.allCases) func restoreBringsBackWhatDisappeared(path: OSPath) {
        let r = makeState(path).targets
        let frame = CGRect(x: 0, y: 200, width: 100, height: 100)
        r.register("a", frame: frame)
        r.unregister("a")
        r.restore("a")
        #expect(r.frame(of: "a") == frame)
        r.restore("never")
        #expect(r.frame(of: "never") == nil)
        r.unregister("a")
        let moved = CGRect(x: 0, y: 300, width: 100, height: 100)
        r.register("a", frame: moved)                      // a fresh measurement supersedes the retired frame
        r.unregister("a"); r.register("a", frame: moved); r.restore("a")
        #expect(r.frame(of: "a") == moved)
    }

    @Test(arguments: OSPath.allCases) func anIDShowsTheNewestActiveReportersFrame(path: OSPath) {
        let r = makeState(path).targets
        let old = ReporterToken(), new = ReporterToken()
        #expect(new.serial > old.serial)
        let first = CGRect(x: 0, y: 0, width: 10, height: 10), second = CGRect(x: 0, y: 50, width: 10, height: 10)
        // The replacement registers first; the old view still reports (stale) and disappears afterwards: the id stays.
        r.register("a", frame: first, owner: old)
        r.register("a", frame: second, owner: new)
        r.register("a", frame: first, owner: old)                                   // a stale report of the replaced view
        #expect(r.frame(of: "a") == second)
        r.unregister("a", owner: old)
        #expect(r.frame(of: "a") == second)
        r.unregister("a", owner: new)
        #expect(r.frame(of: "a") == nil)
        // The other order: the old view disappears, then the replacement registers.
        r.register("b", frame: first, owner: old)
        r.unregister("b", owner: old)
        r.register("b", frame: second, owner: new)
        #expect(r.frame(of: "b") == second)
        // Two copies of a view alive at once (SwiftUI can build one and discard it): when the newest goes, the id falls
        // back to the one that stays, which does not report again.
        r.register("c", frame: first, owner: old)
        r.register("c", frame: second, owner: new)
        r.unregister("c", owner: new)
        #expect(r.frame(of: "c") == first)
        r.unregister("c", owner: old)
        #expect(r.frame(of: "c") == nil)
        // A view that never reported cannot remove what an older one registered.
        r.register("d", frame: first, owner: old)
        r.unregister("d", owner: new)
        #expect(r.frame(of: "d") == first)
        // What a removed view's preference resets to is not a frame, and a disappeared view reports nothing.
        r.register("e", frame: .null, owner: new)
        #expect(r.frame(of: "e") == nil)
        new.isActive = false
        r.register("f", frame: first, owner: new)
        #expect(r.frame(of: "f") == nil)
        new.isActive = true
        r.register("f", frame: first, owner: new)
        #expect(r.frame(of: "f") == first)
        // The writes counter counts effective changes only.
        let writes = r.writes
        r.register("f", frame: first, owner: new)
        r.register("f", frame: first, owner: old)                                   // an older reporter, same frame
        #expect(r.writes == writes)
    }

    @Test(arguments: OSPath.allCases) func nearestTargetPrefersContainmentThenDistance(path: OSPath) {
        let r = makeState(path).targets
        #expect(r.nearestTarget(to: .zero) == nil)
        r.register("a", frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        r.register("b", frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        r.register("c", frame: CGRect(x: 0, y: 300, width: 100, height: 100))
        #expect(r.nearestTarget(to: CGPoint(x: 50, y: 150))?.id == AnyHashable("b"))
        #expect(r.nearestTarget(to: CGPoint(x: 50, y: 240))?.id == AnyHashable("b"))     // 40 from b, 60 from c
        #expect(r.nearestTarget(to: CGPoint(x: 50, y: 260))?.id == AnyHashable("c"))
        #expect(r.nearestTarget(to: CGPoint(x: 50, y: -500))?.id == AnyHashable("a"))
        #expect(r.nearestTarget(to: CGPoint(x: 50, y: 100))?.id == AnyHashable("a"))     // a tie: the one nearer the origin
    }

    // MARK: hosted

    private func hosted(_ path: OSPath, model: ItemsModel = ItemsModel(), axes: Axis.Set = .vertical)
        -> (ZTronScrollState, ItemsModel, UIWindow) {
        let s = makeState(path)
        let w = withOSPath(path) { host(ItemsView(state: s, model: model, axes: axes)) }
        pump(0.2)
        return (s, model, w)
    }

    @Test(arguments: OSPath.allCases) func framesAreInTheUnscaledContentSpace(path: OSPath) {
        let (s, _, w) = hosted(path)
        let r = s.targets
        #expect(r.frames.count == 4)
        for i in 0..<4 { #expect(r.frame(of: i) == CGRect(x: 0, y: 100 * CGFloat(i), width: 200, height: 100), "item \(i)") }
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func nothingIsWrittenWhileScrollingAndZooming(path: OSPath) {
        let (s, _, w) = hosted(path)
        let r = s.targets
        let before = r.frames
        let writes = r.writes, version = r.version
        ZTronRenderCounters.reset()
        // A scripted scroll + zoom: finger-like writes, then a programmatic animation.
        for y in stride(from: 10.0, through: 200.0, by: 19) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1 + y / 150); pump(0.03) }
        s.setContentOffset(CGPoint(x: 0, y: 40), animated: true)
        pump(0.6)
        withAnimation(.linear(duration: 0.3)) { s.scroll(to: CGPoint(x: 0, y: 120)) }
        pump(0.6)
        s.track(offset: .zero, zoom: 1); pump(0.1)
        #expect(r.writes == writes && r.version == version)
        #expect(r.frames == before)
        #expect(ZTronRenderCounters.value("registry.frameChanged") == 0)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func unregistersWhenTheViewDisappearsAndRegistersAgain(path: OSPath) {
        let (s, model, w) = hosted(path)
        model.ids.removeLast()
        pump(0.2)
        #expect(s.targets.frame(of: 3) == nil && s.targets.frames.count == 3)
        model.ids.append(3)
        pump(0.2)
        #expect(s.targets.frame(of: 3) == CGRect(x: 0, y: 300, width: 200, height: 100))
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func targetFrameDidChangeOnReflow(path: OSPath) {
        let (s, model, w) = hosted(path)
        ZTronRenderCounters.reset()
        model.tallID = 1                                   // item 1 grows to 200 pt: items 2 and 3 move down
        pump(0.3)
        #expect(s.targets.frame(of: 1) == CGRect(x: 0, y: 100, width: 200, height: 200))
        #expect(s.targets.frame(of: 2) == CGRect(x: 0, y: 300, width: 200, height: 100))
        #expect(s.targets.frame(of: 3) == CGRect(x: 0, y: 400, width: 200, height: 100))
        // Items 1, 2 and 3 changed; exactly three notifications where the content survives the reflow (the fallback
        // layout host rebuilds it, which also unregisters and registers every id again).
        #expect(ZTronRenderCounters.value("registry.frameChanged") >= 3)
        if s.usesGeometryChange { #expect(ZTronRenderCounters.value("registry.frameChanged") == 3) }
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aChangedIDMovesTheRegistration(path: OSPath) {
        let (s, model, w) = hosted(path)
        model.ids = [10, 11, 12, 13]
        pump(0.3)
        #expect(Set(s.targets.frames.keys) == Set([10, 11, 12, 13].map { AnyHashable($0) }))
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func outsideAScrollViewItIsThePlainID(path: OSPath) {
        let w = withOSPath(path) { host(Color.red.frame(width: 50, height: 50).ztronScrollID("loose")) }
        pump(0.1)
        unhost(w)                                              // nothing to register with, nothing to crash
        if #available(iOS 17, *) {
            let native = withOSPath(path) { host(ScrollView { Color.red.frame(height: 400).ztronScrollID("loose") }) }
            pump(0.1)
            _ = native
        }
    }

    @Test(arguments: OSPath.allCases) func nestedViewsRegisterWithTheirOwnScrollView(path: OSPath) {
        let outer = makeState(path), inner = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: outer) {
                VStack(spacing: 0) {
                    Color.green.frame(height: 100).ztronScrollID("outer-header")
                    ZTronScrollView(.horizontal, state: inner) {
                        HStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { Color.orange.frame(width: 100, height: 100).ztronScrollID("page\($0)") }
                        }
                    }
                    .frame(height: 100)
                    .ztronScrollID("outer-inner")
                }
            })
        }
        pump(0.3)
        #expect(Set(outer.targets.frames.keys) == [AnyHashable("outer-header"), AnyHashable("outer-inner")])
        #expect(Set(inner.targets.frames.keys) == Set((0..<4).map { AnyHashable("page\($0)") }))
        #expect(inner.targets.frame(of: "page2") == CGRect(x: 200, y: 0, width: 100, height: 100))
        unhost(w)
    }
}
