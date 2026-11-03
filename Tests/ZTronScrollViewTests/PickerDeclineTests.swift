import Foundation
import SwiftUI
import Testing
import ScrollArbitration
import ZTronScrollPhysics
@testable import ZTronScrollView
#if canImport(UIKit) && os(iOS)
import UIKit
#endif

/// Spike PICKER-s1 (open items 37-39, D84): a sequence whose first finger lands on a wheel / date picker is the picker's
/// along its axis. The window probe reports it (`touchSequenceBegan(onPicker:)`); the coordinator drops that sequence's
/// drag samples when the first one is within 45° of vertical, settles a caught motion and tells a nested container
/// (`participantDeclined`). Real coordinators, real nested arbiter; the UIKit side is `UIKitObserverShellTests`'.
@MainActor
@Suite(.serialized)
struct PickerDeclineTests {
    final class Clock { var t: TimeInterval = 100 }

    @MainActor struct Side {
        let state: ZTronScrollState
        let coord: PanCoordinator
        let delegate: ReleaseDelegate
        var offset: CGPoint { state.peek.presentationOffset }
        var dragCallbacks: [String] {
            delegate.log.filter { $0 == "willBeginDragging" || $0 == "willEndDragging" || $0.hasPrefix("didEndDragging") }
        }
    }

    func makeSide(_ path: OSPath, axes: Axis.Set, content: CGSize, offset: CGPoint = .zero, paging: Bool = false,
                  viewport: CGSize = CGSize(width: 100, height: 200), clock: Clock) -> Side {
        let s = makeState(path)
        let d = ReleaseDelegate()
        s.delegate = d
        s.now = { clock.t }
        s.isPagingEnabled = paging
        s.setMetrics(ScrollMetrics(viewportSize: viewport, contentSize: content, displayScale: 2))
        s.track(offset: offset, zoom: 1)
        d.log.removeAll()
        let c = withOSPath(path) { PanCoordinator(state: s, axes: axes) }
        return Side(state: s, coord: c, delegate: d)
    }

    func tick(_ clock: Clock, _ sides: Side..., frames: Int = 1) {
        for _ in 0..<frames {
            clock.t += 1.0 / 60
            for s in sides { s.state.step(to: Date(timeIntervalSinceReferenceDate: clock.t)) }
        }
    }

    let start = CGPoint(x: 50, y: 150)

    /// The SwiftUI pan of one sequence: three samples along `step`, its end, the last finger up (the observer's).
    func drag(_ sides: [Side], _ clock: Clock, step: CGSize) {
        for k in 1...3 {
            clock.t += 0.016
            let t = CGSize(width: step.width * CGFloat(k), height: step.height * CGFloat(k))
            for s in sides { s.coord.handle(.dragChanged(translation: t, startLocation: start, time: clock.t)) }
        }
        clock.t += 0.016
        let end = CGSize(width: step.width * 3, height: step.height * 3)
        for s in sides { s.coord.handle(.dragEnded(translation: end, time: clock.t, fallbackVelocity: nil)) }
        for s in sides { s.coord.handle(.touchesEnded(time: clock.t)) }
    }

    func vertical(_ path: OSPath, _ clock: Clock) -> Side {
        makeSide(path, axes: .vertical, content: CGSize(width: 100, height: 1000), offset: CGPoint(x: 0, y: 300), clock: clock)
    }

    // MARK: One view

    /// Baseline: the same drag without the probe's report scrolls.
    @Test(arguments: OSPath.allCases) func withoutAPickerTheDragScrolls(path: OSPath) {
        let clock = Clock()
        let v = vertical(path, clock)
        v.coord.touchSequenceBegan(onPicker: false)
        drag([v], clock, step: CGSize(width: 0, height: -20))
        #expect(v.offset.y > 300 && v.dragCallbacks.first == "willBeginDragging")
    }

    /// The wheel's drag: nothing moves, no drag callback, the sequence closes, nothing is left latched.
    @Test(arguments: OSPath.allCases) func aVerticalDragThatBeganOnAPickerNeverScrolls(path: OSPath) {
        let clock = Clock()
        let v = vertical(path, clock)
        v.coord.touchSequenceBegan(onPicker: true)
        drag([v], clock, step: CGSize(width: 4, height: -20))
        tick(clock, v, frames: 30)
        #expect(v.offset == CGPoint(x: 0, y: 300))
        #expect(v.dragCallbacks.isEmpty, "\(v.delegate.log)")
        #expect(!v.coord.isSequenceActive && !v.coord.declinedForPicker && v.state.phase == .idle)
    }

    /// The decline is the sequence's: the next one, from anywhere else, scrolls again.
    @Test(arguments: OSPath.allCases) func theNextSequenceScrollsAgain(path: OSPath) {
        let clock = Clock()
        let v = vertical(path, clock)
        v.coord.touchSequenceBegan(onPicker: true)
        drag([v], clock, step: CGSize(width: 0, height: -20))
        #expect(v.offset.y == 300)
        v.coord.touchSequenceBegan(onPicker: false)
        drag([v], clock, step: CGSize(width: 0, height: -20))
        #expect(v.offset.y > 300)
    }

    /// A drag cancelled by SwiftUI (no `.dragEnded`) leaves the latch on; the next sequence's report clears it.
    @Test func aNewReportClearsALeftoverLatch() {
        let clock = Clock()
        let v = vertical(.preferred, clock)
        v.coord.touchSequenceBegan(onPicker: true)
        v.coord.handle(.dragChanged(translation: CGSize(width: 0, height: -20), startLocation: start, time: clock.t))
        #expect(v.coord.declinedForPicker)
        v.coord.touchSequenceBegan(onPicker: false)
        #expect(!v.coord.declinedForPicker)
        drag([v], clock, step: CGSize(width: 0, height: -20))
        #expect(v.offset.y > 300)
    }

    /// Flatter than 45°: the wheel's pan fails across its axis (UIKit), so the drag stays this two-axis view's.
    @Test(arguments: OSPath.allCases) func aFlatDragOnAPickerStaysTheViews(path: OSPath) {
        let clock = Clock()
        let v = makeSide(path, axes: [.horizontal, .vertical], content: CGSize(width: 1000, height: 1000),
                         offset: CGPoint(x: 300, y: 300), clock: clock)
        v.coord.touchSequenceBegan(onPicker: true)
        drag([v], clock, step: CGSize(width: -20, height: -8))
        #expect(v.offset.x > 300 && v.dragCallbacks.first == "willBeginDragging")
        #expect(!v.coord.declinedForPicker)
    }

    /// Exactly 45° is the picker's (ties go to the wheel, as in `abs(dy) >= abs(dx)`).
    @Test func fortyFiveDegreesIsThePickers() {
        let clock = Clock()
        let v = makeSide(.preferred, axes: [.horizontal, .vertical], content: CGSize(width: 1000, height: 1000),
                         offset: CGPoint(x: 300, y: 300), clock: clock)
        v.coord.touchSequenceBegan(onPicker: true)
        drag([v], clock, step: CGSize(width: -15, height: -15))
        #expect(v.offset == CGPoint(x: 300, y: 300) && v.dragCallbacks.isEmpty)
    }

    /// A touch on the wheel catches a deceleration (the observer's touch-down), then the wheel takes the drag: the catch
    /// settles where it stopped the content (D60's `.settle`), no drag callback fires.
    @Test(arguments: OSPath.allCases) func aCaughtMotionSettlesWithoutDragCallbacks(path: OSPath) {
        let clock = Clock()
        let v = vertical(path, clock)
        v.state.beginDeceleration(x: .rest(position: 0), y: .spring(CriticalSpring(origin: 300, target: 500), start: clock.t),
                                  at: clock.t)
        v.delegate.log.removeAll()
        v.coord.touchSequenceBegan(onPicker: true)
        v.coord.handle(.touchDown(location: start, time: clock.t, touchCount: 1))
        #expect(v.coord.caughtUndecided && v.offset.y == 300)
        drag([v], clock, step: CGSize(width: 0, height: -20))
        tick(clock, v, frames: 60)
        #expect(abs(v.offset.y - 300) < 0.5, "rests at \(v.offset.y)")
        #expect(v.dragCallbacks.isEmpty, "\(v.delegate.log)")
        #expect(!v.coord.isSequenceActive && v.state.phase == .idle)
    }

    // MARK: Nested (open item 38)

    @MainActor struct Rig {
        let outer: Side
        let inner: Side
        let clock: Clock
        var arbiter: NestedScrollArbiter { outer.coord.nestedArbiter }
    }

    /// Outer vertical list holding a vertical inner list (the picker is in the inner), or a horizontal pager whose page 0
    /// is that inner list.
    func make(_ path: OSPath, pager: Bool) -> Rig {
        let clock = Clock()
        let outer = pager
            ? makeSide(path, axes: .horizontal, content: CGSize(width: 300, height: 200), paging: true, clock: clock)
            : makeSide(path, axes: .vertical, content: CGSize(width: 100, height: 1000), offset: CGPoint(x: 0, y: 300), clock: clock)
        let inner = makeSide(path, axes: .vertical, content: CGSize(width: 100, height: 1000), offset: CGPoint(x: 0, y: 300),
                             clock: clock)
        inner.coord.setArbiter(outer.coord.nestedArbiter)
        inner.coord.participant?.register(frame: CGRect(x: 0, y: pager ? 0 : 300, width: 100, height: 200))
        outer.delegate.log.removeAll(); inner.delegate.log.removeAll()
        return Rig(outer: outer, inner: inner, clock: clock)
    }

    /// Both probes saw the picker (one window, one hit view): whichever SwiftUI pan reports first, nothing moves, and the
    /// arbiter's sequence ends with the touch.
    @Test(arguments: OSPath.allCases, [true, false]) func aWheelDragInANestedInnerMovesNeitherView(path: OSPath, innerFirst: Bool) {
        let r = make(path, pager: false)
        for s in [r.inner, r.outer] { s.coord.touchSequenceBegan(onPicker: true) }
        r.outer.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        r.inner.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        drag(innerFirst ? [r.inner, r.outer] : [r.outer, r.inner], r.clock, step: CGSize(width: 0, height: -20))
        tick(r.clock, r.outer, r.inner, frames: 30)
        #expect(r.outer.offset.y == 300 && r.inner.offset.y == 300)
        #expect(r.outer.dragCallbacks.isEmpty && r.inner.dragCallbacks.isEmpty)
        #expect(!r.arbiter.isSequenceActive && !r.outer.coord.isSequenceActive && !r.inner.coord.isSequenceActive)
    }

    /// Baseline of the same rig without the report: the shared vertical drag is the inner's (the arbiter's rule).
    @Test(arguments: OSPath.allCases) func baselineTheNestedDragIsTheInnersWithoutAPicker(path: OSPath) {
        let r = make(path, pager: false)
        for s in [r.inner, r.outer] { s.coord.touchSequenceBegan(onPicker: false) }
        r.outer.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        r.inner.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        drag([r.outer, r.inner], r.clock, step: CGSize(width: 0, height: -20))
        #expect(r.inner.offset.y > 300 && r.outer.offset.y == 300)
    }

    /// Pager: a vertical wheel drag on page 0 moves nothing; a horizontal swipe from the wheel still pages.
    @Test(arguments: OSPath.allCases) func aPagerPageKeepsPagingFromTheWheel(path: OSPath) {
        let r = make(path, pager: true)
        for s in [r.inner, r.outer] { s.coord.touchSequenceBegan(onPicker: true) }
        r.outer.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        r.inner.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        drag([r.outer, r.inner], r.clock, step: CGSize(width: 0, height: -20))
        tick(r.clock, r.outer, r.inner, frames: 30)
        #expect(r.outer.offset.x == 0 && r.inner.offset.y == 300)
        #expect(r.outer.dragCallbacks.isEmpty && r.inner.dragCallbacks.isEmpty)

        for s in [r.inner, r.outer] { s.coord.touchSequenceBegan(onPicker: true) }
        r.outer.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        r.inner.coord.handle(.touchDown(location: start, time: r.clock.t, touchCount: 1))
        drag([r.outer, r.inner], r.clock, step: CGSize(width: -20, height: 0))
        tick(r.clock, r.outer, r.inner, frames: 120)
        #expect(r.outer.offset.x == 100, "paged to \(r.outer.offset.x)")
        #expect(r.inner.offset.y == 300 && r.inner.dragCallbacks.isEmpty)
    }
}

#if canImport(UIKit) && os(iOS)
/// The probe's two pure answers on real UIKit views (the touch overrides are the demo UI tests').
@MainActor
@Suite struct PickerProbeRuleTests {
    @Test func aViewInsideAPickerViewIsInAPicker() {
        let picker = UIPickerView(), cell = UIView(), leaf = UIView()
        picker.addSubview(cell); cell.addSubview(leaf)
        #expect(UIKitTouchObserverRecognizer.isInPicker(leaf))
        #expect(UIKitTouchObserverRecognizer.isInPicker(picker))
    }

    @Test func aViewInsideAWheelsDatePickerIsInAPicker() {
        let picker = UIDatePicker(), leaf = UIView()
        picker.preferredDatePickerStyle = .wheels
        picker.addSubview(leaf)
        #expect(picker.datePickerStyle == .wheels)
        #expect(UIKitTouchObserverRecognizer.isInPicker(leaf))
    }

    /// Compact and graphical date pickers do not turn under a vertical drag: it scrolls, as in a native `ScrollView`.
    @Test(arguments: [UIDatePickerStyle.compact, .inline]) func aCompactOrGraphicalDatePickerIsNot(style: UIDatePickerStyle) {
        let picker = UIDatePicker(), leaf = UIView()
        picker.preferredDatePickerStyle = style
        picker.addSubview(leaf)
        #expect(picker.datePickerStyle == style)
        #expect(!UIKitTouchObserverRecognizer.isInPicker(leaf))
    }

    @Test func anyOtherViewIsNot() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800)), host = UIView(), leaf = UIView()
        window.addSubview(host); host.addSubview(leaf)
        #expect(!UIKitTouchObserverRecognizer.isInPicker(leaf))
        #expect(!UIKitTouchObserverRecognizer.isInPicker(UISlider()))
        #expect(!UIKitTouchObserverRecognizer.isInPicker(nil))
    }

    @Test func anEventWithNoOtherTouchBeginsASequence() {
        #expect(UIKitTouchObserverRecognizer.beginsSequence([], UIEvent()))
    }

    /// Probe-only (17+): the recognizer reports, feeds nothing and writes no catch state; `install` neither.
    @Test func theProbeOnlyRecognizerFeedsNothing() {
        let coordinator = PanCoordinator(state: ZTronScrollState(), axes: .vertical)
        let catchState = CatchObserverState()
        catchState.down = true
        let anchor = UIKitTouchAnchorView()
        let r = UIKitTouchObserverRecognizer(anchor: anchor, coordinator: coordinator, catchState: catchState, feedsCore: false,
                                             reportsPickers: true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        r.install(on: window)
        r.touchesBegan([], with: UIEvent())
        r.touchesMoved([], with: UIEvent())
        r.touchesEnded([], with: UIEvent())
        #expect(catchState.down, "probe-only never writes the SwiftUI observer's catch state")
        #expect(!coordinator.isSequenceActive && !coordinator.declinedForPicker)
        #expect(r.state == .possible && r.view === window)
        r.install(on: nil)
    }
}
#endif
