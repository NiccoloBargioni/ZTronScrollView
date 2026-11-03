import CoreGraphics
import Foundation

// Pure core of the opt-in UIKit pan (D60; design docs/design/UIKIT-pan.md §2 at 9e6d448, spike U1 folded in). No UIKit
// and no `#if`: it compiles everywhere and `UIKitPanCoreTests` covers it 100 %. The shell (U3) turns the recognizer's
// delegate calls and actions, and the D31 observer's outputs, into these calls and forwards the returned `PanEvent`s to
// `PanCoordinator.handle`, in the order returned.

/// Half-angles, in degrees, of the acceptance cones around each axis (§2 "Acceptance cones"). A direction lies in a
/// cone when its angle to that axis is strictly less than the half-angle: a tie goes outside. The shell picks the
/// constants with `#available`; the core takes them as an input.
struct UIKitPanCones: Equatable, Sendable {
    var horizontal: Double
    var vertical: Double

    /// Every view where N does not hold, S included.
    static let standard = UIKitPanCones(horizontal: 45, vertical: 45)
    /// N on iOS 26.x: a native inner list took every angle from 10° above horizontal (U1 Q3e), so the boundary sits at
    /// 5° (C2 option b, user 2026-10-28).
    static let nativePage26 = UIKitPanCones(horizontal: 45, vertical: 85)
    /// N on iOS 27.0, and on later OSes until a newer runtime is swept (R10): nothing moved at 20°, the list took 30°.
    static let nativePage27 = UIKitPanCones(horizontal: 45, vertical: 65)
}

/// The UIKit pan's sequence bookkeeping (§2 "Mapping", "Lift", "Second finger") and its `shouldBegin` rule (§2 "Axis
/// rule"). One instance per recognizer, on the main thread.
///
/// - The observer's touch-down opens a sequence and fixes `startLocation`; its last lift closes it. The pan's own
///   `.ended` comes after that lift in the same event (U1 C5), so closing a sequence never touches the pan's state.
/// - A second touch ends an active pan once (`.dragEnded`, the 18+ shape) and asks the shell to reset the recognizer.
///   A reset that finds the pan began or changed arms the swallow of its one `.cancelled` (U1 C4).
/// - `shouldBegin` answers false while the sequence has seen two touches; a false answer is forwarded as `.declined`
///   once per sequence.
/// - An active pan with no `.ended` or `.cancelled` before the next touch-down ends as `.cancelled` there.
struct UIKitPanCore: Sendable {
    /// `UIGestureRecognizer.State` raw values (public and stable); the core never imports UIKit. `recognized` is `ended`.
    enum RawState {
        static let possible = 0
        static let began = 1
        static let changed = 2
        static let ended = 3
        static let cancelled = 4
        static let failed = 5
    }

    enum Axis: Sendable {
        case horizontal, vertical

        var cross: Axis { self == .horizontal ? .vertical : .horizontal }
    }

    /// What "can move on an axis" reads (§2 "Axis rule"). Never `PanEnvironment.bouncesX/Y`: `.automatic` makes them true
    /// for every declared axis, so a 1× zoomer would take every drag.
    struct AxisInput: Equatable, Sendable {
        /// The axis is one of the view's effective axes (`PanEnvironment.axes`, D15).
        var isInAxes = false
        var isScrollable = false
        /// The axis's bounce behavior is `.always`.
        var bouncesAlways = false
        /// `alwaysBounceHorizontal` / `alwaysBounceVertical`.
        var alwaysBounces = false
        /// A refresher on an edge of this axis bounces it.
        var refresherBounces = false

        var canMove: Bool { isInAxes && (isScrollable || bouncesAlways || alwaysBounces || refresherBounces) }
    }

    /// The one-axis container this view is a participant of (`PanEnvironment.hasArbiter`): the arbiter's paging axis
    /// and rule 1 tolerance. Nil when the view is alone or its container follows both axes.
    struct Container: Equatable, Sendable {
        var pagingAxis: Axis
        var tolerance: Double = 30
    }

    /// Everything `decide(_:)` reads. The shell fills the static inputs; `shouldBegin(_:location:velocity:)` fills
    /// `direction` and `sawSecondFinger` from the sequence.
    struct Input: Equatable, Sendable {
        /// `PanEnvironment.isScrollEnabled`: `ztronScrollDisabled`, `scrollDisabled` and the UIKit knob, merged.
        var isScrollEnabled = true
        /// `ztronScrollYieldsToSheet(true)`.
        var yieldsToSheet = false
        /// `@Environment(\.isEnabled)`: a `.disabled` ancestor disables neither route by itself (U1 C6).
        var isEnvironmentEnabled = true
        var horizontal = AxisInput()
        var vertical = AxisInput()
        var container: Container?
        var cones = UIKitPanCones.standard
        /// The drag's direction (`UIKitPanCore.direction(displacement:velocity:)`).
        var direction = CGSize.zero
        /// The observer counted two touches or more in this sequence.
        var sawSecondFinger = false

        subscript(axis: Axis) -> AxisInput { axis == .horizontal ? horizontal : vertical }
    }

    /// Below this displacement the direction is UIKit's velocity (§2 "The direction vector").
    static let minimumDisplacement: CGFloat = 8
    /// Exactly at a tolerance or a half-angle, up to rounding, is a tie (`ScrollArbitrationRules`' slack).
    static let angleSlack = 1e-9

    /// The observer's touch-down location of the live sequence, in viewport space; set from the pan's first sample
    /// when the observer missed the touch-down (≈ 10 pt along the drag, Q5).
    private(set) var startLocation: CGPoint?
    /// Between the observer's touch-down and its last lift.
    private(set) var isSequenceLive = false
    private(set) var sawSecondFinger = false
    /// The pan began and has had no `.ended` or `.cancelled` yet.
    private(set) var isPanActive = false
    private(set) var isSwallowArmed = false
    private(set) var didDecline = false
    private var lastTranslation = CGSize.zero
    private var lastVelocity = CGVector.zero

    // MARK: Observer

    /// The observer's first touch of a sequence. An active pan left from an earlier sequence is closed first: the
    /// returned events go to the coordinator before the observer's `.touchDown`.
    mutating func touchDown(at location: CGPoint, touchCount: Int) -> [PanEvent] {
        let dangling = isPanActive
        isPanActive = false
        isSequenceLive = true
        startLocation = location
        sawSecondFinger = touchCount >= 2
        isSwallowArmed = false
        didDecline = false
        return dangling ? [.cancelled] : []
    }

    /// The observer's touch count changed. The first count of two or more in a live sequence ends an active pan once
    /// and asks the shell to reset the recognizer (`willReset(stateRaw:)`, then `isEnabled` off and on). Touches that
    /// land together never begin the pan (it stays `.possible`), so a touch-down with two touches asks nothing.
    mutating func touchCountChanged(to count: Int, time: TimeInterval) -> (events: [PanEvent], resetsRecognizer: Bool) {
        guard isSequenceLive, count >= 2, !sawSecondFinger else { return ([], false) }
        sawSecondFinger = true
        guard isPanActive else { return ([], true) }
        isPanActive = false
        return ([.dragEnded(translation: lastTranslation, time: time, fallbackVelocity: lastVelocity)], true)
    }

    /// The observer's last lift or its cancel. It comes before the pan's own `.ended` (U1 C5): the pan stays active.
    mutating func sequenceEnded() {
        isSequenceLive = false
        startLocation = nil
        sawSecondFinger = false
        isSwallowArmed = false
        didDecline = false
    }

    // MARK: Recognizer

    /// Right before the shell resets the recognizer. A reset that finds the pan began or changed makes UIKit send exactly
    /// one `.cancelled`: inside the `isEnabled = false` call on 17.5 and 18.x, after it returns on 26+ (U1 Q5). It is
    /// dropped; a reset in `.possible` sends nothing and arms nothing.
    mutating func willReset(stateRaw: Int) {
        if stateRaw == RawState.began || stateRaw == RawState.changed { isSwallowArmed = true }
    }

    /// `gestureRecognizerShouldBegin`. `location` is `location(in:)` in viewport space, `velocity` is `velocity(in:)`.
    /// A false answer is the only source of `.declined` (UIKit sends no action for `.failed`), at most once per sequence.
    mutating func shouldBegin(_ input: Input, location: CGPoint, velocity: CGVector) -> (begins: Bool, events: [PanEvent]) {
        var i = input
        i.direction = Self.direction(displacement: startLocation.map { CGSize(width: location.x - $0.x, height: location.y - $0.y) },
                                     velocity: velocity)
        i.sawSecondFinger = sawSecondFinger
        if Self.decide(i) { return (true, []) }
        guard !didDecline else { return (false, []) }
        didDecline = true
        return (false, [.declined])
    }

    /// The recognizer's action (§2 "Mapping"): began / changed → `.dragChanged`, ended → `.dragEnded` with UIKit's
    /// velocity, cancelled → `.cancelled` unless the swallow is armed, every other raw value → nothing. Samples after a
    /// second touch, and an `.ended` of a pan that is not active, are dropped: the second touch already ended it.
    mutating func handle(stateRaw: Int, translation: CGSize, velocity: CGVector, location: CGPoint,
                         time: TimeInterval) -> PanEvent? {
        switch stateRaw {
        case RawState.began, RawState.changed:
            guard !sawSecondFinger else { return nil }
            isPanActive = true
            lastTranslation = translation
            lastVelocity = velocity
            let start = startLocation ?? CGPoint(x: location.x - translation.width, y: location.y - translation.height)
            startLocation = start
            return .dragChanged(translation: translation, startLocation: start, time: time)
        case RawState.ended:
            guard isPanActive else { return nil }
            isPanActive = false
            return .dragEnded(translation: translation, time: time, fallbackVelocity: velocity)
        case RawState.cancelled:
            isPanActive = false
            guard !isSwallowArmed else { isSwallowArmed = false; return nil }
            return .cancelled
        default:
            return nil
        }
    }

    // MARK: Axis rule (pure)

    /// Precedence, first match wins (§2 "Axis rule"):
    /// 1. decline everything when scrolling is disabled, the view yields to the sheet, `\.isEnabled` is false, or the
    ///    sequence has seen two touches;
    /// 2. as a participant of a one-axis container, accept a drag more than the container's tolerance off its paging
    ///    axis when the view can move on the cross axis (the arbiter's rule 1 gives it that drag);
    /// 3. otherwise accept iff the view can move on an axis whose cone holds the drag.
    static func decide(_ i: Input) -> Bool {
        guard i.isScrollEnabled, !i.yieldsToSheet, i.isEnvironmentEnabled, !i.sawSecondFinger else { return false }
        if let c = i.container, isOffAxis(i.direction, from: c.pagingAxis, tolerance: c.tolerance), i[c.pagingAxis.cross].canMove {
            return true
        }
        return (i.horizontal.canMove && lies(i.direction, inConeOf: .horizontal, halfAngle: i.cones.horizontal))
            || (i.vertical.canMove && lies(i.direction, inConeOf: .vertical, halfAngle: i.cones.vertical))
    }

    /// The finger's displacement since the observer's touch-down when it is at least 8 pt long, otherwise UIKit's
    /// velocity (also when the observer missed the touch-down). Never UIKit's translation: it subtracts the 10 pt
    /// hysteresis per axis and bends toward the dominant axis (U1 Q5).
    static func direction(displacement: CGSize?, velocity: CGVector) -> CGSize {
        if let d = displacement, hypot(d.width, d.height) >= minimumDisplacement { return d }
        return CGSize(width: velocity.dx, height: velocity.dy)
    }

    /// The angle in degrees, in [0, 90], between `v` and `axis`. A zero vector reads 0 for both axes (it lies in every
    /// cone, as a zero translation is on-axis for the arbiter); a NaN component reads NaN (it lies in none).
    static func angle(of v: CGSize, to axis: Axis) -> Double {
        let w = Double(v.width.magnitude), h = Double(v.height.magnitude)
        let (on, off) = axis == .horizontal ? (w, h) : (h, w)
        return atan2(off, on) * 180 / .pi
    }

    static func lies(_ v: CGSize, inConeOf axis: Axis, halfAngle: Double) -> Bool {
        angle(of: v, to: axis) < halfAngle - angleSlack
    }

    /// The arbiter's rule 1 on the same numbers: more than `tolerance` off the axis. A zero vector never is, whatever the
    /// tolerance; a NaN angle never is.
    static func isOffAxis(_ v: CGSize, from axis: Axis, tolerance: Double) -> Bool {
        guard v.width != 0 || v.height != 0 else { return false }
        return angle(of: v, to: axis) > tolerance + angleSlack
    }
}
