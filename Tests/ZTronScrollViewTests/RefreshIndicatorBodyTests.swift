import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Review of open item 19: a hold scrolled away keeps its custom indicator in the tree (its box on the content's edge,
/// clipped), and the leaf rebuilt `custom(binding)` on each of its frames with a fresh closure `Binding`: the indicator's
/// body ran on every frame of a plain scroll although nothing of it was drawn (hosted rig, 17.5: 20 of 20 leaf frames;
/// SPEC S4 allows an indicator body per frame only during a pull or a collapse). While nothing of it is visible and its
/// state is the same, the leaf hands SwiftUI the view it built last (`BuiltRefreshIndicator`): the body runs on the
/// frames with the gap on the screen only, the same view (no new `@StateObject`). The hold's reveal (visible) still runs
/// it on each leaf frame, as before. D80: on the path without layer groups both slots carry the leaf and only the one that
/// draws (behind the content, for this headerless custom indicator) runs the indicator's body; the other one's leaf costs
/// its evaluation only (at most one per frame per slot).
@MainActor
@Suite(.serialized)
struct RefreshIndicatorBodyTests {
    nonisolated(unsafe) static var bodies = 0
    nonisolated(unsafe) static var inits = 0

    final class Token: ObservableObject { init() { RefreshIndicatorBodyTests.inits += 1 } }

    struct Probe: View {
        @Binding var state: ZTronRefreshState
        @StateObject private var token = Token()
        var body: some View {
            let _ = { RefreshIndicatorBodyTests.bodies += 1 }()
            Color.white.frame(width: 20, height: 20)
        }
    }

    func reset() {
        Self.bodies = 0
        Self.inits = 0
        ZTronRenderCounters.reset()
    }

    @Test(arguments: OSPath.allCases, [Edge.top, .bottom, .leading, .trailing])
    func aHoldScrolledAwayRunsNoIndicatorBodyWhileItIsNotDrawn(path: OSPath, edge: Edge) {
        let vertical = edge == .top || edge == .bottom
        let viewport = CGSize(width: 390, height: 800)
        let rig = RefreshRig(path, configs: [edge: ZTronRefreshConfiguration()], axes: vertical ? .vertical : .horizontal,
                             viewport: viewport,
                             content: vertical ? CGSize(width: 390, height: 3000) : CGSize(width: 3000, height: 800))
        var spec = RefresherSpec(style: .default, overlay: false, configuration: ZTronRefreshConfiguration(), action: { _ in })
        spec.indicator = { AnyView(Probe(state: $0)) }
        let host = RefreshSlots(coordinator: rig.refresh, state: rig.state, specs: [edge: spec])
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(origin: .zero, size: viewport))
            w.rootViewController = UIHostingController(rootView: host.ignoresSafeArea())
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        if edge == .bottom { rig.state.setContentOffset(CGPoint(x: 0, y: 2200), animated: false) }
        if edge == .trailing { rig.state.setContentOffset(CGPoint(x: 2610, y: 0), animated: false) }
        pump(0.2)
        let label = "\(path) \(edge)"

        reset()
        rig.refresh.begin(edge, runAction: false)
        for _ in 0..<40 { rig.tick(); pump(0.016) }
        pump(0.4)
        // D80: the drawing slot (behind the content without layer groups) and the other one (front, drawing nothing).
        let behind = !rig.state.usesGeometryGroup
        let drawing = behind ? "refresh.leaf.behind" : "refresh.leaf.front"
        let revealLeaf = ZTronRenderCounters.value(drawing)
        #expect(revealLeaf > 10 && Self.bodies == revealLeaf, "\(label) reveal: a body per leaf frame, as before (\(Self.bodies) / \(revealLeaf))")
        #expect(Self.inits == 1, "\(label) reveal: one indicator")
        let front = ZTronRenderCounters.value("refresh.leaf.front"), back = ZTronRenderCounters.value("refresh.leaf.behind")
        #expect(behind ? front == back : back == 0, "\(label) reveal: one leaf per slot and frame (front \(front), behind \(back))")

        // 400 pt past the base in 10 steps and back in 10: only the first step out and the last two back have the gap
        // on the screen (60 - 46 = 14 pt, then 14 and 60).
        reset()
        let rest = rig.state.contentOffset
        let dir: CGPoint
        switch edge {
        case .top: dir = CGPoint(x: 0, y: 1)
        case .bottom: dir = CGPoint(x: 0, y: -1)
        case .leading: dir = CGPoint(x: 1, y: 0)
        case .trailing: dir = CGPoint(x: -1, y: 0)
        }
        for k in Array(1...10) + Array((0...9).reversed()) {
            let d = CGFloat(k) * 46
            rig.state.setContentOffset(CGPoint(x: rest.x + dir.x * d, y: rest.y + dir.y * d), animated: false)
            pump(0.02)
        }
        let leaf = ZTronRenderCounters.value(drawing)
        #expect(rig.refreshState(edge).mode == .refreshing, "\(label): still held")
        #expect(leaf >= 18, "\(label) away: the leaf follows the scroll (\(leaf))")
        #expect(Self.bodies <= 3, "\(label) away: a body only with the gap on the screen (\(Self.bodies) of \(leaf) leaf frames)")
        #expect(Self.inits == 0, "\(label) away: the same indicator view")
    }
}
