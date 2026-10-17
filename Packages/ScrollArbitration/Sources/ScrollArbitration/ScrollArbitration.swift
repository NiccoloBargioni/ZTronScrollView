import SwiftUI

/// The direction a finger moves, in screen space.
///
/// Directions name the finger, not the content: `.left` means the finger moved left, so the content should
/// move left and reveal what lies to its right. Directions ignore layout direction; a participant in a
/// right-to-left layout maps `.left` / `.right` to its own leading / trailing edges inside
/// ``ScrollArbitrationParticipant/canFollow(_:)``.
public enum FingerDirection: Sendable, Hashable {
    /// The finger moved towards the left edge of the screen (negative `translation.width`).
    case left
    /// The finger moved towards the right edge of the screen (positive or zero `translation.width`).
    case right
    /// The finger moved towards the top edge of the screen (negative `translation.height`).
    case up
    /// The finger moved towards the bottom edge of the screen (positive or zero `translation.height`).
    case down
}

/// Which side owns a touch sequence: the inner scroller or the outer pager.
public enum ScrollOwner: Sendable, Hashable {
    /// The participant (the inner scroller) follows the finger; the container must not move.
    case participant
    /// The container (the pager) follows the finger; the participant ignores the rest of the sequence.
    case container
}

/// An opaque handle for one registration with a ``ScrollArbiter``.
///
/// Tokens are created only by arbiters. A ``ReferenceScrollArbiter`` never reuses a token, and a token
/// issued by one arbiter is unknown to every other arbiter.
public struct ScrollArbitrationToken: Sendable, Hashable {
    /// Process-wide unique serial; `0` is never issued.
    let serial: UInt64

    init(serial: UInt64) {
        self.serial = serial
    }

    /// A token no arbiter ever issues; it stands in for "no participant under the start point".
    static let unregistered = ScrollArbitrationToken(serial: 0)
}

/// An inner scroller that shares its touches with a container (for example a page inside a pager).
///
/// An arbiter calls these members only from inside its own calls (``ReferenceScrollArbiter`` from
/// ``ReferenceScrollArbiter/beginSequence()``, ``ScrollArbiter/owner(ofDragFrom:translation:touchCount:participant:)``
/// and ``ReferenceScrollArbiter/containerOwner(ofDragFrom:translation:touchCount:)``). Implementations must answer
/// synchronously and must never call back into the arbiter from any of these members.
@MainActor public protocol ScrollArbitrationParticipant: AnyObject {
    /// Whether the participant can still scroll with a finger moving in `direction` (screen space).
    ///
    /// Return `false` at an edge: a participant that would only rubber-band leaves the drag to the container.
    func canFollow(_ direction: FingerDirection) -> Bool
    /// Whether the participant is moving without a finger: decelerating, bouncing or animating.
    var isMovingWithoutFinger: Bool { get }
    /// Whether the participant zooms with two or more fingers.
    var isZoomEnabled: Bool { get }
}

/// Decides, once per touch sequence, whether a drag belongs to a participant or to its container.
///
/// Every arbiter decides through ``ScrollArbitrationRules/decide(_:)``. Frames and start points are in
/// `.named(coordinateSpaceName)`. Registration and frame updates are cold-path calls (appear, geometry change,
/// disappear), never per scroll frame. Everything runs on the main actor and no call re-enters the arbiter.
@MainActor public protocol ScrollArbiter: AnyObject {
    /// The name of the coordinate space that frames and start points are expressed in.
    var coordinateSpaceName: String { get }
    /// Registers `participant` with its current `frame` and returns the token for later calls.
    ///
    /// The arbiter does not keep the participant alive.
    func register(_ participant: any ScrollArbitrationParticipant, frame: CGRect) -> ScrollArbitrationToken
    /// Replaces the frame of a registered participant. Unknown tokens are ignored.
    func update(_ token: ScrollArbitrationToken, frame: CGRect)
    /// Removes a registration. Unknown tokens are ignored.
    func unregister(_ token: ScrollArbitrationToken)
    /// Returns who owns the drag that started at `start` and has moved by `translation` so far.
    ///
    /// A touch sequence runs from the first finger down to the last finger up, as the arbiter sees it
    /// (``ReferenceScrollArbiter`` is told through ``ReferenceScrollArbiter/beginSequence()`` and
    /// ``ReferenceScrollArbiter/endSequence()``). Within one sequence the first call decides; later calls from
    /// the participant the swipe was resolved to get the same owner whatever the other arguments, and every
    /// other participant gets `.container`. An unknown token gets `.container`.
    /// - Parameters:
    ///   - start: The touch-down point in `.named(coordinateSpaceName)`.
    ///   - translation: The finger's movement so far: `+width` right, `+height` down.
    ///   - touchCount: The number of fingers on the participant.
    ///   - participant: The asking participant's token.
    func owner(ofDragFrom start: CGPoint, translation: CGSize, touchCount: Int,
               participant: ScrollArbitrationToken) -> ScrollOwner
}

/// The gesture name participants give their gestures on iOS 18+.
///
/// Containers may let their own recognizers run alongside recognizers with this name.
public let scrollArbitrationGestureName = "ScrollArbitration.participant"
