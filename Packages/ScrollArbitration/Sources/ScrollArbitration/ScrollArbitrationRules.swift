import SwiftUI

/// Everything ``ScrollArbitrationRules/decide(_:)`` looks at, captured at the deciding call.
public struct ScrollArbitrationInput: Sendable, Equatable {
    /// The axis the container pages along.
    public var pagingAxis: Axis
    /// How many degrees the translation may deviate from the paging axis and still count as on-axis.
    /// Default 30. Exactly at the tolerance counts as on-axis, with a 1e-9° slack so a translation built at the
    /// tolerance angle with trigonometry stays on-axis despite rounding. Not clamped: 90 or more disables
    /// rule 1, a negative value makes every non-zero translation off-axis.
    public var directionTolerance: Double
    /// The finger's movement so far, screen space: `+width` right, `+height` down.
    public var translation: CGSize
    /// The number of fingers down; `0` and `1` both count as a single touch.
    public var touchCount: Int
    /// `canFollow(fingerDirection(translation, along: pagingAxis))` of the participant.
    public var participantCanFollow: Bool
    /// Whether the participant was moving without a finger when the sequence began.
    public var participantMovingAtTouchDown: Bool
    /// Whether the participant zooms with two or more fingers.
    public var participantZoomEnabled: Bool
    /// Whether the container was moving (for example decelerating) when the sequence began.
    public var containerMovingAtTouchDown: Bool

    /// Creates an input. Every argument maps to the property of the same name.
    public init(pagingAxis: Axis, directionTolerance: Double = 30, translation: CGSize, touchCount: Int,
                participantCanFollow: Bool, participantMovingAtTouchDown: Bool,
                participantZoomEnabled: Bool, containerMovingAtTouchDown: Bool) {
        self.pagingAxis = pagingAxis
        self.directionTolerance = directionTolerance
        self.translation = translation
        self.touchCount = touchCount
        self.participantCanFollow = participantCanFollow
        self.participantMovingAtTouchDown = participantMovingAtTouchDown
        self.participantZoomEnabled = participantZoomEnabled
        self.containerMovingAtTouchDown = containerMovingAtTouchDown
    }
}

/// The arbitration rules as pure functions. Every arbiter must decide through ``decide(_:)``.
public enum ScrollArbitrationRules {
    /// The finger's direction along `axis`, from the sign of the on-axis component only.
    ///
    /// Horizontal: `width < 0` is `.left`, anything else (`0`, `-0.0`, NaN, positive) is `.right`.
    /// Vertical: `height < 0` is `.up`, anything else is `.down`. The off-axis component is ignored.
    public static func fingerDirection(_ translation: CGSize, along axis: Axis) -> FingerDirection {
        switch axis {
        case .horizontal: return translation.width < 0 ? .left : .right
        case .vertical: return translation.height < 0 ? .up : .down
        }
    }

    /// Returns the owner for `input`: the first matching rule, in this order.
    ///
    /// 1. The translation is more than `directionTolerance` degrees off the paging axis → `.participant`.
    ///    The angle is `atan2(|off-axis|, |on-axis|)` in degrees, in [0, 90]; it must exceed the tolerance by
    ///    more than 1e-9°, so exactly at the tolerance (up to rounding) is on-axis. A zero translation is
    ///    always on-axis and a NaN angle is on-axis.
    /// 2. `touchCount >= 2` and zoom enabled → `.participant`.
    /// 3. The participant was moving without a finger at touch-down → `.participant`.
    /// 4. The container was moving at touch-down → `.container`.
    /// 5. The participant can follow the finger along the paging axis → `.participant`.
    /// 6. Otherwise → `.container`.
    public static func decide(_ input: ScrollArbitrationInput) -> ScrollOwner {
        if isOffAxis(input.translation, along: input.pagingAxis, tolerance: input.directionTolerance) {
            return .participant
        }
        if input.touchCount >= 2 && input.participantZoomEnabled { return .participant }
        if input.participantMovingAtTouchDown { return .participant }
        if input.containerMovingAtTouchDown { return .container }
        if input.participantCanFollow { return .participant }
        return .container
    }

    /// How far past the tolerance, in degrees, rule 1's angle must be. `atan2` of a translation built at the
    /// tolerance angle with `tan` or `cos`/`sin` can land a few ulps (about 1e-14°) above it; that is still
    /// "exactly at the tolerance".
    private static let toleranceSlack = 1e-9

    /// Rule 1. A zero translation has no direction, so it never counts as off-axis.
    private static func isOffAxis(_ translation: CGSize, along axis: Axis, tolerance: Double) -> Bool {
        let width = Double(translation.width.magnitude)
        let height = Double(translation.height.magnitude)
        let (onAxis, offAxis) = axis == .horizontal ? (width, height) : (height, width)
        guard onAxis != 0 || offAxis != 0 else { return false }
        let offAxisDegrees = atan2(offAxis, onAxis) * 180 / .pi
        return offAxisDegrees > tolerance + toleranceSlack
    }
}
