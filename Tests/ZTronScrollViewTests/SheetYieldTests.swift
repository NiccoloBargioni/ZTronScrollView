import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

private struct SheetYieldOtherKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    /// An unrelated environment key, the baseline for "what any environment change costs".
    var sheetYieldOther: Bool {
        get { self[SheetYieldOtherKey.self] }
        set { self[SheetYieldOtherKey.self] = newValue }
    }
}

/// `View.ztronScrollYieldsToSheet(_:)` (SPEC S12 "Inside a bottom sheet", SHEET-s2): the environment plumbing, the gate that
/// keeps the one source no gesture mask covers (the iOS 15-16 UIKit observer) out of the coordinator, and the in-flight
/// cases: a drag, a pinch, a catch, a held release, a deceleration when the flag turns true. "Ends like a cancelled touch" is
/// pinned against the real thing: the same sequence ended by the system's cancel (`cancelIfActive`) leaves the same
/// delegate log and the same state.
@MainActor
@Suite(.serialized)
struct SheetYieldTests {
    @MainActor final class Log: ZTronScrollViewDelegate {
        var events: [String] = []
        func scrollViewWillBeginDragging(_ s: ZTronScrollState) { events.append("willBeginDragging") }
        func scrollViewDidEndDragging(_ s: ZTronScrollState, willDecelerate d: Bool) { events.append("didEndDragging(\(d))") }
        func scrollViewWillBeginDecelerating(_ s: ZTronScrollState) { events.append("willBeginDecelerating") }
        func scrollViewDidEndDecelerating(_ s: ZTronScrollState) { events.append("didEndDecelerating") }
        func scrollViewWillBeginZooming(_ s: ZTronScrollState) { events.append("willBeginZooming") }
        func scrollViewDidEndZooming(_ s: ZTronScrollState, atScale scale: CGFloat) { events.append("didEndZooming") }
    }

    final class Clock { var t: TimeInterval = 100 }

    @MainActor struct Rig {
        let state: ZTronScrollState
        let coord: PanCoordinator
        let log: Log
        let clock: Clock
        var now: TimeInterval {
            get { clock.t }
            nonmutating set { clock.t = newValue }
        }
        func tick() { now += 1.0 / 60; state.step(to: Date(timeIntervalSinceReferenceDate: now)) }
        /// Runs the clock until the state is at rest (no clock, idle), bounded.
        func settle(_ maxTicks: Int = 900) {
            for _ in 0..<maxTicks {
                if state.phase == .idle && !state.isClockRunning { return }
                tick()
            }
        }
        /// What the adapter does when the environment value turns true (`PanGestureAdapter`).
        func yield() {
            coord.yieldsToSheet = true
            coord.cancelForSheetYield()
        }
        /// The system's cancel of a gesture in flight, for the reference run.
        func systemCancel() { coord.cancelIfActive() }
    }

    func make(_ path: OSPath, offset: CGPoint = CGPoint(x: 0, y: 1000)) -> Rig {
        let s = makeState(path)
        let log = Log()
        s.delegate = log
        let clock = Clock()
        s.now = { clock.t }
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(3))
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 200, height: 400), contentSize: CGSize(width: 200, height: 4000),
                                   displayScale: 2))
        s.track(offset: offset, zoom: 1)
        let c = withOSPath(path) { PanCoordinator(state: s, axes: .vertical) }
        return Rig(state: s, coord: c, log: log, clock: clock)
    }

    let start = CGPoint(x: 100, y: 300)

    /// A one-finger drag in flight: touch down and `steps` samples of `dy` pt each (negative = finger up).
    func drag(_ r: Rig, steps: Int, dy: CGFloat) {
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        for i in 1...steps {
            r.now += 0.016
            r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: CGFloat(i) * dy), startLocation: start, time: r.now))
        }
        r.state.step(to: Date(timeIntervalSinceReferenceDate: r.now))
    }

    /// The comparable result of a sequence: delegate log, flags, offset.
    func outcome(_ r: Rig) -> String {
        "\(r.log.events) tracking=\(r.state.isTracking) dragging=\(r.state.isDragging) zooming=\(r.state.isZooming) "
            + "phase=\(r.state.phase) clock=\(r.state.isClockRunning) lock=\(r.state.catchLocksContent) "
            + "session=\(r.coord.isSequenceActive) y=\(Int(r.state.contentOffset.y)) z=\(r.state.zoomScale)"
    }

    // MARK: in flight: a drag

    /// Within the bounds: the flip releases the drag like a cancelled one (no velocity, so no deceleration).
    @Test(arguments: OSPath.allCases) func aDragInFlightEndsLikeACancelledTouch(path: OSPath) {
        let a = make(path), b = make(path)
        drag(a, steps: 6, dy: -20); drag(b, steps: 6, dy: -20)
        #expect(a.state.isTracking && a.state.isDragging && a.state.contentOffset.y > 1100 && a.state.contentOffset.y < 1130,
                "\(a.state.contentOffset.y)")
        a.yield(); b.systemCancel()
        a.settle(); b.settle()
        #expect(outcome(a) == outcome(b), "yield: \(outcome(a)) / system cancel: \(outcome(b))")
        #expect(!a.state.isTracking && !a.state.isDragging && a.state.phase == .idle && !a.state.isClockRunning)
        #expect(a.log.events == ["willBeginDragging", "didEndDragging(false)"], "\(a.log.events)")
        #expect(!a.state.catchLocksContent)
    }

    /// Past the top edge: the rubber band springs back after the flip, on the state clock, and the clock stops.
    @Test(arguments: OSPath.allCases) func anOverscrolledDragSpringsBack(path: OSPath) {
        let a = make(path, offset: .zero), b = make(path, offset: .zero)
        drag(a, steps: 6, dy: 20); drag(b, steps: 6, dy: 20)
        #expect(a.state.contentOffset.y < 0, "pulled past the top")
        a.yield(); b.systemCancel()
        a.settle(); b.settle()
        #expect(outcome(a) == outcome(b), "yield: \(outcome(a)) / system cancel: \(outcome(b))")
        #expect(a.state.contentOffset.y == 0 && a.state.phase == .idle && !a.state.isClockRunning)
        #expect(a.log.events.filter { $0 == "didEndDragging(true)" || $0 == "didEndDragging(false)" }.count == 1, "\(a.log.events)")
        #expect(a.log.events.filter { $0 == "didEndDecelerating" }.count <= 1, "\(a.log.events)")
    }

    // MARK: in flight: a catch, a held release, a pinch

    /// A touch that caught a decelerating view and has not moved yet: the catch lock and the tracking flag go with it.
    @Test(arguments: OSPath.allCases) func aCatchInFlightLeavesNothingLocked(path: OSPath) {
        let r = make(path)
        drag(r, steps: 4, dy: -40)
        r.now += 0.016
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -160), time: r.now, fallbackVelocity: CGVector(dx: 0, dy: -2500)))
        #expect(r.state.isDecelerating)
        r.tick()
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))   // catches the motion
        #expect(r.state.isTracking && r.state.catchLocksContent && !r.state.isDecelerating)
        r.yield()
        r.settle()
        #expect(!r.state.isTracking && !r.state.catchLocksContent && r.state.phase == .idle && !r.state.isClockRunning)
        #expect(!r.coord.isSequenceActive)
    }

    /// The DragGesture ended on a second finger and the release is held for the observer (D29): the yield applies it as
    /// a release without motion, so the drag is not stuck open.
    @Test(arguments: OSPath.allCases) func aHeldReleaseIsAppliedWithoutMotion(path: OSPath) {
        let r = make(path)
        r.coord.pinch.centroidSource = .spatial
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -40), startLocation: start, time: r.now))
        let c = CGPoint(x: 100, y: 200)
        r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now))
        r.coord.handlePinch(.began(centroid: c, time: r.now))
        r.coord.handlePinch(.changed(magnification: 1.5, centroid: c, time: r.now)); r.tick()
        r.now += 0.016
        r.coord.handlePinch(.fingerCountChanged(count: 1, remaining: CGPoint(x: 100, y: 260), time: r.now))   // one finger lifts
        var t = CGSize(width: 0, height: -40)
        for _ in 1...3 {
            r.now += 0.016; t.height -= 40
            r.coord.handle(.dragChanged(translation: t, startLocation: start, time: r.now))
        }
        r.now += 0.016
        r.coord.handle(.dragEnded(translation: t, time: r.now, fallbackVelocity: CGVector(dx: 0, dy: -2500)))
        #expect(!r.state.isDecelerating, "held, not released")
        r.yield()
        r.settle()
        #expect(!r.state.isTracking && !r.state.isDragging && !r.state.isDecelerating && !r.state.isZooming)
        #expect(r.state.phase == .idle && !r.state.isClockRunning, "\(outcome(r))")
        #expect(!r.log.events.contains("willBeginDecelerating"), "a held release never flings: \(r.log.events)")
        // The observer's late "no fingers" finds nothing to release.
        r.coord.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: r.now))
        r.coord.handle(.touchesEnded(time: r.now))
        #expect(!r.state.isDecelerating && r.state.phase == .idle)
    }

    @Test(arguments: OSPath.allCases) func aPinchInFlightEndsLikeACancelledPinch(path: OSPath) {
        func run(_ cancel: (Rig) -> Void) -> (Rig, String) {
            let r = make(path)
            r.coord.pinch.centroidSource = .spatial
            let c = CGPoint(x: 100, y: 200)
            r.coord.handle(.touchDown(location: c, time: r.now, touchCount: 2))
            r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: c, time: r.now))
            r.coord.handlePinch(.began(centroid: c, time: r.now))
            for m in [1.2, 1.6, 2.4] as [CGFloat] {
                r.now += 0.016
                r.coord.handlePinch(.changed(magnification: m, centroid: c, time: r.now)); r.tick()
            }
            #expect(r.state.isZooming && r.coord.pinch.isActive)
            cancel(r)
            r.settle()
            return (r, outcome(r))
        }
        let (a, oa) = run { $0.yield() }
        let (_, ob) = run { $0.coord.handlePinch(.cancelled); $0.systemCancel() }
        #expect(oa == ob, "yield: \(oa) / cancelled pinch: \(ob)")
        #expect(!a.coord.pinch.isActive && !a.state.isZooming && !a.state.isTracking && a.state.phase == .idle && !a.state.isClockRunning)
        #expect(a.state.zoomScale >= 1 && a.state.zoomScale <= 3)
        // The magnify gesture's own late end finds the session already closed.
        a.coord.handlePinch(.ended(time: a.now))
        #expect(!a.coord.pinch.isActive && !a.state.isZooming)
    }

    // MARK: in flight: a deceleration

    /// The decided case: the deceleration is not interrupted (nothing cancels a finger-free motion; `ztronScrollDisabled`
    /// does the same). It settles on its own clock, once, and the clock stops. While inert nothing can catch it.
    @Test(arguments: OSPath.allCases) func aDecelerationKeepsSettlingAndStopsTheClock(path: OSPath) {
        let r = make(path)
        drag(r, steps: 4, dy: -40)
        r.now += 0.016
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -160), time: r.now, fallbackVelocity: CGVector(dx: 0, dy: -2500)))
        r.coord.handle(.touchesEnded(time: r.now))
        r.tick()
        #expect(r.state.isDecelerating && r.state.isClockRunning)
        let before = r.log.events
        let y0 = r.state.contentOffset.y
        r.yield()
        #expect(r.log.events == before, "the flip itself adds no delegate call")
        #expect(r.state.isDecelerating && r.state.isClockRunning)
        // A touch on the inert view is not a catch.
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        #expect(!r.state.isTracking && !r.state.catchLocksContent && r.state.isDecelerating)
        for _ in 0..<5 { r.tick() }
        #expect(r.state.contentOffset.y > y0, "it keeps moving")
        r.settle()
        #expect(r.state.phase == .idle && !r.state.isClockRunning && !r.state.isDecelerating)
        #expect(r.log.events.filter { $0 == "didEndDecelerating" }.count == 1, "\(r.log.events)")
        #expect(r.log.events.filter { $0 == "willBeginDecelerating" }.count == 1, "\(r.log.events)")
    }

    // MARK: the gate

    /// The UIKit observer (15-16) reports through the coordinator: while yielding nothing of it begins a sequence.
    @Test(arguments: OSPath.allCases) func eventsAreDroppedWhileYielding(path: OSPath) {
        let r = make(path)
        r.yield()
        r.coord.handle(.touchDown(location: start, time: r.now, touchCount: 1))
        r.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -60), startLocation: start, time: r.now))
        r.coord.handlePinch(.fingerCountChanged(count: 2, remaining: start, time: r.now))
        r.coord.handlePinch(.began(centroid: start, time: r.now))
        r.coord.handlePinch(.changed(magnification: 1.5, centroid: start, time: r.now))
        r.coord.synthesizePan(location: start, time: r.now)
        r.coord.handle(.touchesEnded(time: r.now))
        r.tick()
        #expect(!r.coord.isSequenceActive && !r.coord.pinch.isActive)
        #expect(!r.state.isTracking && !r.state.isZooming && r.state.phase == .idle && !r.state.isClockRunning)
        #expect(r.state.contentOffset.y == 1000 && r.state.zoomScale == 1)
        #expect(r.log.events.isEmpty, "\(r.log.events)")
    }

    /// Turning it back off re-arms everything: a fresh drag scrolls as before, with its delegate calls.
    @Test(arguments: OSPath.allCases) func theViewIsLiveAgainWhenTheFlagTurnsFalse(path: OSPath) {
        let r = make(path)
        drag(r, steps: 3, dy: -20)
        r.yield()
        r.settle()
        r.log.events.removeAll()
        r.coord.yieldsToSheet = false
        drag(r, steps: 6, dy: -20)
        #expect(r.state.isTracking && r.state.isDragging && r.state.contentOffset.y > 1100, "\(outcome(r))")
        r.now += 0.016
        r.coord.handle(.dragEnded(translation: CGSize(width: 0, height: -120), time: r.now, fallbackVelocity: nil))
        r.coord.handle(.touchesEnded(time: r.now))
        r.settle()
        #expect(r.log.events.first == "willBeginDragging" && r.log.events.contains { $0.hasPrefix("didEndDragging") }, "\(r.log.events)")
        #expect(!r.state.isTracking && r.state.phase == .idle)
    }

    /// With nothing in flight the flip is a no-op for the state.
    @Test(arguments: OSPath.allCases) func aFlipAtRestChangesNothing(path: OSPath) {
        let r = make(path)
        let before = outcome(r)
        r.yield()
        r.coord.yieldsToSheet = false
        #expect(outcome(r) == before && r.log.events.isEmpty)
    }

    @Test func theCatchObserverResetForgetsADownTouch() {
        let o = CatchObserverState()
        o.down = true; o.activeCount = 2; o.centroid = CGPoint(x: 1, y: 2); o.panStart = CGPoint(x: 3, y: 4)
        o.reset()
        #expect(!o.down && o.activeCount == 0 && o.centroid == nil && o.panStart == nil)
    }

    // MARK: environment and adapter plumbing (hosted)

    @MainActor final class Seen { var values: [String: Bool] = [:] }
    struct EnvProbe: View {
        let seen: Seen
        let tag: String
        @Environment(\.ztronYieldsToSheet) private var yields
        var body: some View {
            seen.values[tag] = yields
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    @Test func theEnvironmentValueDefaultsToFalsePropagatesAndTheInnerValueWins() {
        let seen = Seen()
        let w = host(VStack {
            EnvProbe(seen: seen, tag: "none")
            VStack { EnvProbe(seen: seen, tag: "child"); VStack { EnvProbe(seen: seen, tag: "grandchild") } }
                .ztronScrollYieldsToSheet()
            VStack { EnvProbe(seen: seen, tag: "explicitTrue") }.ztronScrollYieldsToSheet(true)
            VStack { EnvProbe(seen: seen, tag: "explicitFalse") }.ztronScrollYieldsToSheet(false)
            VStack { EnvProbe(seen: seen, tag: "nearestFalse") }.ztronScrollYieldsToSheet(false).ztronScrollYieldsToSheet(true)
            VStack { EnvProbe(seen: seen, tag: "nearestTrue") }.ztronScrollYieldsToSheet(true).ztronScrollYieldsToSheet(false)
        })
        #expect(seen.values["none"] == false)
        #expect(seen.values["child"] == true && seen.values["grandchild"] == true)
        #expect(seen.values["explicitTrue"] == true && seen.values["explicitFalse"] == false)
        // Like any environment value, the modifier nearest the view wins.
        #expect(seen.values["nearestFalse"] == false)
        #expect(seen.values["nearestTrue"] == true)
        _ = w
    }

    @MainActor final class YieldModel: ObservableObject { @Published var yields = false }

    /// The adapter alone (no ZTronScrollView): the flag reaches the coordinator, and turning it true ends a sequence in flight.
    private struct AdapterHost: View {
        @ObservedObject var model: YieldModel
        let coordinator: PanCoordinator
        var body: some View {
            Color.clear.frame(width: 200, height: 200)
                .modifier(PanGestureAdapter(coordinator: coordinator, axes: .vertical))
                .ztronScrollYieldsToSheet(model.yields)
        }
    }

    @Test(arguments: OSPath.allCases) func theAdapterMirrorsTheFlagAndCancelsWhatIsInFlight(path: OSPath) {
        let s = makeState(path)
        let log = Log()
        s.delegate = log
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 200, height: 200), contentSize: CGSize(width: 200, height: 2000),
                                   displayScale: 2))
        let c = withOSPath(path) { PanCoordinator(state: s, axes: .vertical) }
        let model = YieldModel()
        let w = withOSPath(path) { host(AdapterHost(model: model, coordinator: c)) }
        #expect(!c.yieldsToSheet)
        // A drag the adapter's gestures would have delivered.
        c.handle(.touchDown(location: CGPoint(x: 100, y: 150), time: s.now(), touchCount: 1))
        c.handle(.dragChanged(translation: CGSize(width: 0, height: -40), startLocation: CGPoint(x: 100, y: 150), time: s.now()))
        #expect(s.isTracking && s.isDragging)
        withOSPath(path) { model.yields = true; pump(0.15) }
        #expect(c.yieldsToSheet)
        #expect(!s.isTracking && !s.isDragging, "turning the flag true ends the drag")
        #expect(log.events.contains("didEndDragging(false)"), "\(log.events)")
        withOSPath(path) { model.yields = false; pump(0.15) }
        #expect(!c.yieldsToSheet)
        _ = w
    }

    /// S4: flipping the flag re-evaluates the gesture attachment, never the content. Two shapes. (1) The demo's: a parent
    /// whose body re-runs with the flag and rebuilds the scroll view around an input-free content, which SwiftUI skips
    /// (`content.body` stays 0). (2) A content that carries a non-Equatable input: SwiftUI re-runs such a body on ANY
    /// environment change, so the flag is held to "no worse than an unrelated key", and the content keeps its identity.
    private struct KeyWriter: ViewModifier {
        @ObservedObject var model: YieldModel
        let isFlag: Bool
        @ViewBuilder func body(content: Content) -> some View {
            if isFlag {
                content.ztronScrollYieldsToSheet(model.yields)
            } else {
                content.environment(\.sheetYieldOther, model.yields)
            }
        }
    }

    @MainActor final class PlainCount { static var bodies = 0; static var appears = 0 }
    struct PlainContent: View {
        var body: some View {
            PlainCount.bodies += 1
            return Color.red.frame(height: 1000).onAppear { PlainCount.appears += 1 }
        }
    }
    private struct Rebuilding: View {
        @ObservedObject var model: YieldModel
        let state: ZTronScrollState
        var body: some View {
            ZTronScrollView(.vertical, state: state) { PlainContent() }.ztronScrollYieldsToSheet(model.yields)
        }
    }

    @Test(arguments: OSPath.allCases) func flippingTheFlagCostsTheContentNothingBeyondAnyEnvironmentKey(path: OSPath) {
        func flips(isFlag: Bool) -> (bodies: Int, counts: BodyCount) {
            let s = makeState(path)
            let counts = BodyCount()
            let model = YieldModel()
            let w = withOSPath(path) {
                host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                    .modifier(KeyWriter(model: model, isFlag: isFlag)))
            }
            let before = counts.bodies
            for _ in 0..<3 {
                withOSPath(path) { model.yields = true; pump(0.15) }
                model.yields = false; pump(0.15)
            }
            _ = w
            return (counts.bodies - before, counts)
        }
        let flag = flips(isFlag: true), other = flips(isFlag: false)
        #expect(flag.bodies <= other.bodies, "flag \(flag.bodies) vs unrelated key \(other.bodies) content bodies for 6 flips")
        #expect(flag.counts.ids.count == 1 && flag.counts.appears == 1, "the content keeps its identity")
    }

    @Test(arguments: OSPath.allCases) func aParentThatRebuildsTheScrollViewWithTheFlagRunsNoContentBody(path: OSPath) {
        let s = makeState(path)
        let model = YieldModel()
        PlainCount.bodies = 0; PlainCount.appears = 0
        let w = withOSPath(path) { host(Rebuilding(model: model, state: s)) }
        #expect(PlainCount.bodies == 1 && PlainCount.appears == 1)
        for _ in 0..<3 {
            withOSPath(path) { model.yields = true; pump(0.15) }
            model.yields = false; pump(0.15)
        }
        #expect(PlainCount.bodies == 1 && PlainCount.appears == 1, "bodies \(PlainCount.bodies), appears \(PlainCount.appears)")
        _ = w
    }
}
