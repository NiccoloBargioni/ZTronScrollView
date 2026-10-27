import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// The header on the state (design M8b §3 tests 8 and 10 without hosting): inset reservation, metrics changes, the
/// `snapHeader(to:)` queue, the `.immediately` compose hook in the release pipeline and `.afterFinishAccelerating`.
@MainActor
@Suite(.serialized)
struct HeaderStateTests {
    final class Clock { var t: TimeInterval = 100 }

    /// A 402 × 874 vertical view, 62 pt safe top, 3000 pt of content, at rest; `snap` decides the header's snap mode.
    func make(_ path: OSPath, size: ZTronHeaderSize = .fixed(min: 64, max: 240), behavior: ZTronHeaderScalingBehavior = .preserve,
              snap: ZTronHeaderSnap = .disabled, content: CGFloat = 3000) -> (ZTronScrollState, Clock) {
        let clock = Clock()
        let s = makeState(path)
        s.now = { clock.t }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 402, height: 874), contentSize: CGSize(width: 402, height: content),
                                   safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), displayScale: 3))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        s.headerSpec = HeaderSizing(size: size, behavior: behavior, snap: snap)
        s.headerSpecChanged()
        return (s, clock)
    }

    func oPrime(_ s: ZTronScrollState) -> CGFloat {
        let p = s.peek
        return HeaderMath.headerOffset(offset: p.presentationOffset, zoom: p.presentationZoom, metrics: p.metrics)
    }

    func scrollTo(oPrime x: CGFloat, _ s: ZTronScrollState) {
        s.track(offset: CGPoint(x: 0, y: x - HeaderMath.base(s.peek.metrics)), zoom: 1)
    }

    func settle(_ s: ZTronScrollState, _ clock: Clock, frames: Int = 900) {
        var n = 0
        while s.isClockRunning, n < frames {
            clock.t += 1.0 / 60
            s.step(to: Date(timeIntervalSinceReferenceDate: clock.t))
            n += 1
        }
    }

    @Test(arguments: OSPath.allCases) func theRestingHeightIsReservedInTheTopInsetAndRestStaysRest(path: OSPath) {
        let (s, _) = make(path)
        #expect(s.adjustedContentInset.top == 302)
        #expect(s.contentOffset.y == -302 && oPrime(s) == 0, "a view at rest stays at rest when the header installs")
        #expect(s.headerGeometry?.height == 240 && s.headerGeometry?.progress == 0)
        #expect(s.headerHeight(at: 100) == 140 && s.headerHeight(at: 900) == 64)
        s.headerSpec = nil
        s.headerSpecChanged()
        #expect(s.adjustedContentInset.top == 62 && s.contentOffset.y == -62 && s.headerGeometry == nil)
        #expect(s.headerHeight(at: 100) == 0)
    }

    @Test(arguments: OSPath.allCases) func theGeometryReadsThePresentationOffset(path: OSPath) {
        let (s, _) = make(path, behavior: .stretch)
        scrollTo(oPrime: 88, s)
        #expect(s.geometry.header?.progress == 0.5 && s.geometry.header?.height == 152)
        scrollTo(oPrime: -40, s)
        #expect(s.geometry.header?.height == 280 && s.geometry.header?.stretch == 40)
    }

    @Test(arguments: OSPath.allCases) func aSizeChangeKeepsTheProgressAndChangesTheInsetOnce(path: OSPath) {
        let (s, _) = make(path)
        scrollTo(oPrime: 88, s)
        s.headerSpec = HeaderSizing(size: .fixed(min: 64, max: 300), behavior: .preserve, snap: .disabled)
        s.headerSpecChanged()
        #expect(s.adjustedContentInset.top == 362)
        #expect(oPrime(s) == 118 && s.headerGeometry?.progress == 0.5, "progress kept: \(oPrime(s))")
        scrollTo(oPrime: 1000, s)
        let y = s.contentOffset.y
        s.headerSpec = HeaderSizing(size: .fixed(min: 64, max: 200), behavior: .preserve, snap: .disabled)
        s.headerSpecChanged()
        #expect(s.contentOffset.y == y && s.headerGeometry?.progress == 1, "collapsed: the content does not move")
    }

    @Test(arguments: OSPath.allCases) func aSnapBeforeTheMetricsIsQueuedAppliedOnceAndClamped(path: OSPath) {
        let s = makeState(path)
        s.snapHeader(to: .collapsed, animated: true)
        #expect(s.pendingHeaderSnap == .collapsed)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 402, height: 874), contentSize: CGSize(width: 402, height: 3000),
                                   safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), displayScale: 3))
        s.headerSpec = HeaderSizing(size: .fixed(min: 64, max: 240), behavior: .preserve, snap: .disabled)
        s.headerSpecChanged()
        #expect(s.pendingHeaderSnap == nil && oPrime(s) == 176, "applied unanimated at the first layout with a header")
        #expect(!s.isClockRunning)
        scrollTo(oPrime: 0, s)
        s.headerSpec = HeaderSizing(size: .fixed(min: 64, max: 250), behavior: .preserve, snap: .disabled)
        s.headerSpecChanged()
        #expect(oPrime(s) == 0, "consumed once: a later metrics change does not snap again")
        s.snapHeader(to: .progress(5), animated: false)
        #expect(oPrime(s) == 186)
        s.snapHeader(to: .height(10), animated: false)
        #expect(oPrime(s) == 186, ".height clamps to min")
        s.snapHeader(to: .height(200), animated: false)
        #expect(oPrime(s) == 50)
    }

    @Test(arguments: OSPath.allCases) func removingTheHeaderDropsAPendingSnap(path: OSPath) {
        let s = makeState(path)
        s.snapHeader(to: .collapsed)
        s.headerSpec = nil
        s.setHeaderMetrics(nil)
        #expect(s.pendingHeaderSnap == nil)
    }

    @Test(arguments: OSPath.allCases) func collapseIsLimitedByTheBounds(path: OSPath) {
        let (s, _) = make(path, content: 600)
        s.snapHeader(to: .collapsed, animated: false)
        // Scrollable range: 600 + 34 − 874 + 302 = 62 points of o′.
        #expect(oPrime(s) == 62 && s.headerGeometry?.height == 178)
    }

    @Test(arguments: OSPath.allCases) func anAnimatedSnapRunsOnTheClock(path: OSPath) {
        let (s, clock) = make(path)
        s.snapHeader(to: .progress(0.5))
        #expect(s.isClockRunning && s.phase == .animating)
        settle(s, clock)
        #expect(abs(oPrime(s) - 88) < 0.5)
    }

    // MARK: The release pipeline (test 8)

    final class Recorder: ZTronScrollViewDelegate {
        var targets: [CGFloat] = []
        func scrollViewWillEndDragging(_ state: ZTronScrollState, withVelocity velocity: CGPoint,
                                       targetContentOffset: inout CGPoint) { targets.append(targetContentOffset.y) }
    }

    /// Releases at `oPrime` with an upward finger speed `speed` (pt/s, content offset growing).
    func release(_ s: ZTronScrollState, at x: CGFloat, speed: CGFloat, path: OSPath) -> AxisMotion {
        scrollTo(oPrime: x, s)
        let origin = s.contentOffset
        s.beginTracking(); s.beginDragging()
        var tracker = PointVelocityTracker()
        let lift = s.now()
        for i in 0...8 { tracker.add(CGPoint(x: 0, y: -speed * CGFloat(Double(i) * 0.015)), at: lift - 0.12 + Double(i) * 0.015) }
        let pan = withOSPath(path) { PanCoordinator(state: s, axes: .vertical) }
        let (_, my) = s.endDrag(ReleaseRequest(origin: origin, dragStart: origin, liftTime: lift, fallbackVelocity: nil),
                                tracker: tracker, env: pan.peekEnvironment(), settings: ReleaseSettings())
        return my
    }

    @Test(arguments: OSPath.allCases) func immediatelySnapsTheProjectedRestAndWillEndDraggingSeesIt(path: OSPath) {
        let (s, _) = make(path, snap: .immediately())
        let d = Recorder()
        s.delegate = d
        var seen: [CGFloat] = []
        _ = s.observers.addDelegate(DelegateObserverBox(kind: .willEndDragging, handler: .willEndDragging { _, _, target in
            seen.append(target.y)
        }))
        let base = HeaderMath.base(s.peek.metrics)
        let slow = release(s, at: 60, speed: 0, path: path)
        #expect(abs(slow.endPosition + base) < 1e-6, "60 of 176 at rest: back to expanded")
        #expect(d.targets.last == -base && seen.last == -base, "the delegate and the modifier see the snapped target")
        s.interrupt()
        let flick = release(s, at: 60, speed: 150, path: path)
        #expect(abs(flick.endPosition - (176 - base)) < 1e-6, "velocity-aware: the projected rest is past the middle")
        #expect(d.targets.last == 176 - base)
        s.interrupt()
        let far = release(s, at: 60, speed: 3000, path: path)
        #expect(far.endPosition + base > 176 + 1, "a landing past the band is untouched")
    }

    struct FixedLanding: ZTronScrollTargetBehavior {
        let y: CGFloat
        func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext) { target.rect.origin.y = y }
    }

    @Test(arguments: OSPath.allCases) func theSnapIsComposedAfterTheUsersBehavior(path: OSPath) {
        let (s, _) = make(path, snap: .immediately())
        // Target space: rect.origin.y = offset + aci.top = o′ (no hold). The behavior lands at o′ = 120, inside the band.
        s.targetBehavior = AnyZTronScrollTargetBehavior(FixedLanding(y: 120))
        let base = HeaderMath.base(s.peek.metrics)
        let m = release(s, at: 10, speed: 0, path: path)
        #expect(abs(m.endPosition - (176 - base)) < 1e-6, "the behavior's landing, then the header's nearest position")
        s.interrupt()
        s.targetBehavior = AnyZTronScrollTargetBehavior(FixedLanding(y: 700))
        let page = release(s, at: 10, speed: 0, path: path)
        #expect(abs(page.endPosition - (700 - base)) < 1e-6, "a landing outside the band is the behavior's alone")
    }

    @Test(arguments: OSPath.allCases) func afterFinishAcceleratingSnapsOnceTheMotionRests(path: OSPath) {
        let (s, clock) = make(path, snap: .afterFinishAccelerating())
        _ = release(s, at: 60, speed: 100, path: path)
        #expect(s.phase == .decelerating)
        settle(s, clock)
        #expect(abs(oPrime(s) - 176) < 0.5, "the deceleration rests near 110, then the nearest position: \(oPrime(s))")
        let rest = release(s, at: 120, speed: 0, path: path)
        _ = rest
        #expect(s.phase == .animating, "a release at rest inside the band animates to the nearest position")
        settle(s, clock)
        #expect(abs(oPrime(s) - 176) < 0.5)
        let outside = release(s, at: 400, speed: 0, path: path)
        _ = outside
        #expect(s.phase == .idle && abs(oPrime(s) - 400) < 0.5, "outside the band nothing moves")
    }
}
