import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// M6 session 2, tests 3 and 11 (docs/design/M6-targets.md §7) in SwiftUI's target space (D27). Viewport 100 x 200,
/// content 300 x 900, so the vertical offset bounds are 0...700 (before insets and zoom); nine 100 pt items are
/// registered as targets (item i spans y = 100 i ... 100 i + 100).
@MainActor
@Suite(.serialized)
struct ViewAlignedTests {
    static func env(inset: EdgeInsets = EdgeInsets(), zoom: CGFloat = 1) -> PanEnvironment {
        var e = PanSessionTests.env()
        e.boundsX = AxisBounds(min: -inset.leading, max: 200 * zoom + 100 * (zoom - 1) + inset.trailing)
        e.boundsY = AxisBounds(min: -inset.top, max: 900 * zoom - 200 + inset.bottom)
        return e
    }

    func make(_ path: OSPath, at offset: CGPoint = CGPoint(x: 0, y: 300), zoom: CGFloat = 1, inset: EdgeInsets = EdgeInsets(),
              items: Int = 9) -> ZTronScrollState {
        let s = makeState(path)
        s.now = { 100 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900),
                                   contentInset: inset, displayScale: 2))
        s.track(offset: offset, zoom: zoom)
        s.beginTracking(); s.beginDragging()
        for i in 0..<items { s.targets.register(i, frame: CGRect(x: 0, y: CGFloat(i) * 100, width: 300, height: 100)) }
        return s
    }

    /// Finger moving up at `vy` pt/s (content offset increases) for 120 ms ending at 100.
    func tracker(vy: CGFloat) -> PointVelocityTracker {
        var t = PointVelocityTracker()
        for i in 0...8 {
            let time = 100 - 0.12 + Double(i) * 0.015
            t.add(CGPoint(x: 0, y: -vy * CGFloat(time - (100 - 0.12))), at: time)
        }
        return t
    }

    func release(_ s: ZTronScrollState, from origin: CGFloat, dragStart: CGFloat? = nil, vy: CGFloat, behavior: ZTronViewAlignedScrollTargetBehavior,
                 env: PanEnvironment = ViewAlignedTests.env()) -> AxisMotion {
        s.targetBehavior = AnyZTronScrollTargetBehavior(behavior)
        let request = ReleaseRequest(origin: CGPoint(x: 0, y: origin), dragStart: CGPoint(x: 0, y: dragStart ?? origin), liftTime: 100, fallbackVelocity: nil)
        return s.endDrag(request, tracker: tracker(vy: vy), env: env, settings: ReleaseSettings()).y
    }

    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-6 }

    // MARK: .never · nearest to the projected rest

    @Test(arguments: OSPath.allCases) func neverLandsOnTheTargetNearestTheProjectedRest(path: OSPath) {
        // A 400 pt/s fling from 300 projects to about 500 (an item boundary).
        let s = make(path)
        #expect(near(release(s, from: 300, vy: 400, behavior: .init(limitBehavior: .never)).endPosition, 500))
        // A weaker one projects between 400 and 500 and goes to the nearer.
        let t = make(path)
        #expect(near(release(t, from: 300, vy: 280, behavior: .init(limitBehavior: .never)).endPosition, 400))
        // No limit: a hard fling runs to the end of the content.
        let u = make(path)
        #expect(near(release(u, from: 300, vy: 3000, behavior: .init(limitBehavior: .never)).endPosition, 700))
        // Backwards, and a rest between two items snaps to the nearer one.
        let v = make(path, at: CGPoint(x: 0, y: 340))
        #expect(near(release(v, from: 340, vy: 0, behavior: .init(limitBehavior: .never)).endPosition, 300))
    }

    // MARK: .alwaysByOne

    @Test(arguments: OSPath.allCases) func alwaysByOneMovesExactlyOneItemInTheDirectionOfTheFling(path: OSPath) {
        let s = make(path)
        #expect(near(release(s, from: 310, dragStart: 300, vy: 3000, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 400))
        let t = make(path)
        #expect(near(release(t, from: 290, dragStart: 300, vy: -3000, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 200))
        // `.always` is `.alwaysByOne`.
        #expect(ZTronViewAlignedScrollTargetBehavior.LimitBehavior.always == .alwaysByOne)
        // No velocity: the target nearest the lift.
        let u = make(path, at: CGPoint(x: 0, y: 330))
        #expect(near(release(u, from: 330, dragStart: 300, vy: 0, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 300))
        let w = make(path, at: CGPoint(x: 0, y: 360))
        #expect(near(release(w, from: 360, dragStart: 300, vy: 0, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 400))
    }

    /// R5, calibrated against SwiftUI in the demo's aligned section (a 240 pt drag across 120 pt cells landed on the cell
    /// after the lift in both): `.alwaysByOne` moves to the first item beyond where the finger lifted.
    @Test(arguments: OSPath.allCases) func alwaysByOneStartsFromTheLiftNotFromTheDragStart(path: OSPath) {
        let s = make(path)
        #expect(near(release(s, from: 430, dragStart: 300, vy: 3000, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 500))
        let t = make(path)
        #expect(near(release(t, from: 170, dragStart: 300, vy: -3000, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 100))
        // Lifted exactly on an item: the next one.
        let u = make(path)
        #expect(near(release(u, from: 400, dragStart: 400, vy: 3000, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 500))
    }

    @Test(arguments: OSPath.allCases) func alwaysByOneAtTheEndsStaysOnTheLastTarget(path: OSPath) {
        let s = make(path, at: CGPoint(x: 0, y: 0))
        #expect(near(release(s, from: 0, vy: -3000, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 0))
        // The content cannot scroll far enough for the last targets to align: they land on the bound (700).
        let t = make(path, at: CGPoint(x: 0, y: 700))
        #expect(near(release(t, from: 700, vy: 3000, behavior: .init(limitBehavior: .alwaysByOne)).endPosition, 700))
    }

    // MARK: .alwaysByFew

    @Test(arguments: OSPath.allCases) func alwaysByFewStaysWithinOneContainerOfTheDragStart(path: OSPath) {
        let s = make(path)
        let m = release(s, from: 300, vy: 3000, behavior: .init(limitBehavior: .alwaysByFew))
        #expect(near(m.endPosition, 500))                                     // 300 + the container (200); never would run to 700
        let t = make(path)
        #expect(near(release(t, from: 300, vy: -3000, behavior: .init(limitBehavior: .alwaysByFew)).endPosition, 100))
        // A gentle fling still lands on a target.
        let u = make(path)
        #expect(near(release(u, from: 300, vy: 280, behavior: .init(limitBehavior: .alwaysByFew)).endPosition, 400))
    }

    // MARK: .automatic · the size class

    @Test(arguments: OSPath.allCases) func automaticFollowsTheHorizontalSizeClass(path: OSPath) {
        let table: [(UserInterfaceSizeClass?, CGFloat)] = [(.compact, 500), (.regular, 700), (nil, 700)]
        for (sizeClass, expected) in table {
            let box = TargetEnvironmentBox()
            box.values.horizontalSizeClass = sizeClass
            let s = make(path)
            s.adoptEnvironment(box)
            #expect(near(release(s, from: 300, vy: 3000, behavior: .init(limitBehavior: .automatic)).endPosition, expected), "\(String(describing: sizeClass))")
            withExtendedLifetime(box) {}
        }
    }

    // MARK: anchor, zoom, no targets

    @Test(arguments: OSPath.allCases) func theAnchorAlignsTheItemsCentreWithTheContainersCentre(path: OSPath) {
        // Item centres 50, 150, ... meet the container centre (100): offsets -50 (clamped to 0), 50, 150, ...
        let s = make(path, at: CGPoint(x: 0, y: 320))
        #expect(near(release(s, from: 320, vy: 0, behavior: .init(limitBehavior: .alwaysByOne, anchor: .center)).endPosition, 350))
        let t = make(path, at: CGPoint(x: 0, y: 320))
        #expect(near(release(t, from: 320, vy: 0, behavior: .viewAligned(anchor: .center)).endPosition, 350))
        let u = make(path, at: CGPoint(x: 0, y: 10))
        #expect(near(release(u, from: 10, vy: 0, behavior: .init(limitBehavior: .alwaysByOne, anchor: .center)).endPosition, 0))   // -50 clamps to 0
    }

    @Test(arguments: OSPath.allCases) func zoomScalesTheCandidates(path: OSPath) {
        // At 2x the targets sit at 0, 200, 400 ...; the bounds are 0...1600.
        let s = make(path, at: CGPoint(x: 0, y: 290), zoom: 2)
        #expect(near(release(s, from: 290, vy: 0, behavior: .init(limitBehavior: .alwaysByOne), env: Self.env(zoom: 2)).endPosition, 200))
        let t = make(path, at: CGPoint(x: 0, y: 330), zoom: 2)
        #expect(near(release(t, from: 330, vy: 0, behavior: .init(limitBehavior: .alwaysByOne), env: Self.env(zoom: 2)).endPosition, 400))
    }

    @Test(arguments: OSPath.allCases) func noTargetsOrADisabledLayoutLeaveTheReleaseAlone(path: OSPath) {
        let plain = make(path, items: 0)
        plain.targetBehavior = nil
        let request = ReleaseRequest(origin: CGPoint(x: 0, y: 300), dragStart: CGPoint(x: 0, y: 300), liftTime: 100, fallbackVelocity: nil)
        let natural = plain.endDrag(request, tracker: tracker(vy: 400), env: Self.env(), settings: ReleaseSettings()).y.endPosition
        let empty = make(path, items: 0)
        #expect(near(release(empty, from: 300, vy: 400, behavior: .init(limitBehavior: .never)).endPosition, natural))
        let disabled = make(path)
        disabled.targets.layoutEnabled = false
        #expect(near(release(disabled, from: 300, vy: 400, behavior: .init(limitBehavior: .never)).endPosition, natural))
        // The plain decay keeps its edge bounce: nothing snaps.
        let bounce = make(path, at: CGPoint(x: 0, y: 650), items: 0)
        let motion = release(bounce, from: 650, vy: 3000, behavior: .init(limitBehavior: .never))
        guard case let .decay(_, _, handoff) = motion, let h = handoff else { Issue.record("expected the natural decay, got \(motion)"); return }
        #expect(h.edge == 700 && h.bounces)
    }

    // MARK: D27 · under an inset

    @Test(arguments: OSPath.allCases) func candidatesLiveInContentCoordinatesUnderATopInset(path: OSPath) {
        let inset = EdgeInsets(top: 62, leading: 0, bottom: 0, trailing: 0)
        // The container is 138 long, the first item aligns at offset -62 and item i at 100 i - 62.
        let s = make(path, at: CGPoint(x: 0, y: 40), inset: inset)
        #expect(near(release(s, from: 40, vy: 0, behavior: .init(limitBehavior: .alwaysByOne), env: Self.env(inset: inset)).endPosition, 38))
        let t = make(path, at: CGPoint(x: 0, y: -62), inset: inset)
        #expect(near(release(t, from: -62, vy: 0, behavior: .init(limitBehavior: .alwaysByOne), env: Self.env(inset: inset)).endPosition, -62))
        // `.alwaysByFew` limits a fling to the unobscured container (138), not the viewport (200).
        let u = make(path, at: CGPoint(x: 0, y: 38), inset: inset)
        #expect(near(release(u, from: 38, vy: 3000, behavior: .init(limitBehavior: .alwaysByFew), env: Self.env(inset: inset)).endPosition, 138))
        // The anchor measures the unobscured container: item centre 150 meets 69 of the container, content y 81, offset 19.
        let w = make(path, at: CGPoint(x: 0, y: 20), inset: inset)
        #expect(near(release(w, from: 20, vy: 0, behavior: .init(limitBehavior: .alwaysByOne, anchor: .center), env: Self.env(inset: inset)).endPosition, 19))
    }

    // MARK: pure selection

    @Test func candidatesAreClampedSortedAndDistinct() {
        let raw: [(id: AnyHashable, offset: CGFloat)] = [(0, -50), (1, 50), (2, 150), (3, 750), (4, 800)]
        let out = ZTronViewAlignedScrollTargetBehavior.candidates(raw, bounds: AxisBounds(min: 0, max: 700), shift: 0)
        #expect(out == [0, 50, 150, 700])
        let shifted = ZTronViewAlignedScrollTargetBehavior.candidates(raw, bounds: AxisBounds(min: -62, max: 700), shift: 62)
        #expect(shifted == [0, 50, 150, 750, 762])
    }

    // MARK: M5 hook · a resize keeps the aligned item

    func viewport(_ w: CGFloat, _ h: CGFloat) -> ViewportMetrics { ViewportMetrics(size: CGSize(width: w, height: h), safeArea: EdgeInsets()) }

    /// Three full-width pages (the item is as wide as the viewport) at offset 500, between page 1 (400) and page 2 (800).
    func carousel(_ path: OSPath, behavior: AnyZTronScrollTargetBehavior?) -> ZTronScrollState {
        let s = makeState(path)
        s.scrollAxes = .horizontal
        s.targetBehavior = behavior
        s.setContentSize(CGSize(width: 1200, height: 800))
        s.setViewport(viewport(400, 800))
        for i in 0..<3 { s.targets.register(i, frame: CGRect(x: CGFloat(i) * 400, y: 0, width: 400, height: 800)) }
        s.track(offset: CGPoint(x: 500, y: 0), zoom: 1)
        return s
    }

    func reflow(_ s: ZTronScrollState, width: CGFloat) {
        s.setContentSize(CGSize(width: 3 * width, height: 800))
        for i in 0..<3 { s.targets.register(i, frame: CGRect(x: CGFloat(i) * width, y: 0, width: width, height: 800)) }
    }

    @Test(arguments: OSPath.allCases) func aResizeKeepsTheAlignedItemAligned(path: OSPath) {
        let s = carousel(path, behavior: AnyZTronScrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior(limitBehavior: .never)))
        s.setViewport(viewport(300, 800))
        reflow(s, width: 300)
        s.closeResize()
        #expect(s.contentOffset.x == 300)                                          // item 1 (the nearest to 500) at its new frame
        // Without the behavior the centre rule alone leaves the page half way.
        let plain = carousel(path, behavior: nil)
        plain.setViewport(viewport(300, 800))
        reflow(plain, width: 300)
        plain.closeResize()
        #expect(plain.contentOffset.x != 300)
    }

    @Test(arguments: OSPath.allCases) func aFrameThatArrivesAfterTheCloseAlignsInTheSettleWindow(path: OSPath) {
        let s = carousel(path, behavior: AnyZTronScrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior(limitBehavior: .never)))
        s.setViewport(viewport(300, 800))
        s.setContentSize(CGSize(width: 900, height: 800))
        s.closeResize()
        for i in 0..<3 { s.targets.register(i, frame: CGRect(x: CGFloat(i) * 300, y: 0, width: 300, height: 800)) }   // the reporters are late
        #expect(s.contentOffset.x == 300)
    }

    // MARK: layout flag

    @Test func theLayoutFlagCountsEveryDisabledLayout() {
        let r = makeState(.preferred).targets
        let a = ReporterToken(), b = ReporterToken()
        r.setLayout(a, enabled: true)
        #expect(r.layoutEnabled)
        r.setLayout(a, enabled: false); r.setLayout(b, enabled: false)
        #expect(!r.layoutEnabled)
        r.setLayout(a, enabled: true)
        #expect(!r.layoutEnabled)
        r.removeLayout(b)
        #expect(r.layoutEnabled)
    }

    final class LayoutModel: ObservableObject { @Published var enabled = true }

    struct Carousel: View {
        let state: ZTronScrollState
        let counts: BodyCount
        @ObservedObject var model: LayoutModel
        var body: some View {
            ZTronScrollView(.vertical, state: state) {
                VStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in Color(white: CGFloat(i) / 10).frame(height: 100).ztronScrollID(i) }
                    ScrollToTests.BodyProbe(counts: counts)
                }
                .ztronScrollTargetLayout(isEnabled: model.enabled)
            }
        }
    }

    @Test(arguments: OSPath.allCases) func theLayoutModifierTogglesTheTargetsAndNeverRunsBodiesWhileScrolling(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never                                  // the hosting window has a top safe area
        let counts = BodyCount()
        let model = LayoutModel()
        let w = withOSPath(path) { host(Carousel(state: s, counts: counts, model: model)) }
        pump(0.2)
        #expect(s.targets.layoutEnabled && s.targets.frames.count == 10)
        model.enabled = false
        pump(0.2)
        #expect(!s.targets.layoutEnabled)
        model.enabled = true
        pump(0.2)
        #expect(s.targets.layoutEnabled)
        let bodies = counts.bodies
        ZTronRenderCounters.reset()
        s.scrollTo(id: 6, anchor: .top, animation: .uikit, ambient: false)
        pump(1.5)
        #expect(abs(s.contentOffset.y - 600) < 0.5 && s.targets.layoutEnabled)
        #expect(counts.bodies == bodies && s.targets.writes == 10)
        unhost(w)
    }

    // MARK: 11 · conversions with SwiftUI (17+)

    @Test(arguments: OSPath.allCases) func limitBehaviorsConvertToSwiftUIsAndTheTwinBehavesLikeTheNativeModifier(path: OSPath) {
        guard #available(iOS 17, *) else { return }
        var cases: [(String, ZTronViewAlignedScrollTargetBehavior.LimitBehavior, ViewAlignedScrollTargetBehavior.LimitBehavior)] = [
            ("automatic", .automatic, .automatic), ("never", .never, .never), ("always", .always, .always)]
        if #available(iOS 18, *) {
            cases += [("alwaysByOne", .alwaysByOne, .alwaysByOne), ("alwaysByFew", .alwaysByFew, .alwaysByFew)]
        }
        for (name, ours, native) in cases {
            let twin = withOSPath(path) {
                host(ScrollView { VStack(spacing: 0) { ForEach(0..<9, id: \.self) { _ in Color.red.frame(height: 100) } }.scrollTargetLayout() }
                    .ztronScrollTargetBehavior(.viewAligned(limitBehavior: ours)))
            }
            let plain = withOSPath(path) {
                host(ScrollView { VStack(spacing: 0) { ForEach(0..<9, id: \.self) { _ in Color.red.frame(height: 100) } }.scrollTargetLayout() }
                    .scrollTargetBehavior(.viewAligned(limitBehavior: native)))
            }
            pump(0.3)
            let viaTwin = releaseDrag(twin, velocity: CGPoint(x: 0, y: 1.5), proposed: CGPoint(x: 0, y: 330))
            let viaNative = releaseDrag(plain, velocity: CGPoint(x: 0, y: 1.5), proposed: CGPoint(x: 0, y: 330))
            #expect(viaTwin != nil && viaTwin == viaNative, "\(name): twin \(String(describing: viaTwin)) vs native \(String(describing: viaNative))")
            unhost(twin); unhost(plain)
        }
        // Ours to native is one way (SwiftUI's value has no inspectable state); the built-ins convert to their SwiftUI form.
        _ = ZTronViewAlignedScrollTargetBehavior(limitBehavior: .never).native
        _ = ZTronPagingScrollTargetBehavior().native
        _ = ZTronPagingScrollTargetBehavior(PagingScrollTargetBehavior())
        if #available(iOS 18, *) {
            _ = AnyZTronScrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior()).native
            _ = AnyZTronScrollTargetBehavior(ZTronPagingScrollTargetBehavior()).native
            _ = AnyZTronScrollTargetBehavior(SnapTo(value: 1)).native
        }
    }

    @Test(arguments: OSPath.allCases) func theLayoutTwinReachesANativeScrollView(path: OSPath) {
        guard #available(iOS 17, *) else { return }
        // With the layout disabled SwiftUI aligns to nothing: the release keeps the proposed offset.
        func answer(_ enabled: Bool) -> CGPoint? {
            let w = withOSPath(path) {
                host(ScrollView { VStack(spacing: 0) { ForEach(0..<9, id: \.self) { _ in Color.red.frame(height: 100) } }
                        .ztronScrollTargetLayout(isEnabled: enabled) }
                    .ztronScrollTargetBehavior(.viewAligned(limitBehavior: .never)))
            }
            pump(0.3)
            defer { unhost(w) }
            return releaseDrag(w, velocity: .zero, proposed: CGPoint(x: 0, y: 330))
        }
        let on = answer(true), off = answer(false)
        #expect(on != nil && off != nil && on != off, "enabled \(String(describing: on)) vs disabled \(String(describing: off))")
    }
}
