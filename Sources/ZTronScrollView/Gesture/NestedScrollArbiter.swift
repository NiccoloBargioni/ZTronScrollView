import SwiftUI
import ScrollArbitration

/// The arbiter a `ZTronScrollView` offers to the `ZTronScrollView`s in its content (docs/design/NESTED-arbitration.md
/// §3 "Container side"). One per view identity, owned by the outer's `PanCoordinator`, injected into the content's
/// environment together with a named coordinate space on the outer's *content*: in that space an inner's frame does
/// not change while the outer scrolls, so registration stays cold.
///
/// Decisions go through `ScrollArbitrationRules.decide` (a `ReferenceScrollArbiter` does the bookkeeping):
/// - `pagingAxis` is the outer's single axis; a two-axis outer decides with the dominant axis of the translation and
///   rule 1 disabled (it can follow any direction);
/// - `isContainerMoving` is the outer's `isMovingWithoutFinger`, snapshotted when the sequence begins;
/// - a sequence begins at the outer's touch-down (18+ spatial observer) or lazily at the first ask (≤ 17, gated
///   observer) and ends when the outer's pan session returns to idle;
/// - an outer that cannot scroll (`.ztronScrollDisabled`, no axis) is no container: its inners are answered
///   `.participant` without a sequence or a decision, as if they were alone.
/// The log holds the current (or last) sequence only; the frozen contract is used additively (S16).
@MainActor
final class NestedScrollArbiter: ScrollArbiter {
    private static var nextSerial = 0
    private let reference: ReferenceScrollArbiter
    private var tokens: Set<ScrollArbitrationToken> = []
    /// The active sequence began at a participant's ask, not at the outer's touch-down: it also ends with that
    /// participant's sequence, so a touch the outer never saw cannot leave a stale decision behind.
    private var beganLazily = false
    /// The outer; read at the deciding call (axes) and at `beginSequence` (motion).
    weak var container: PanCoordinator?

    let coordinateSpaceName: String

    init() {
        Self.nextSerial += 1
        coordinateSpaceName = "ztronScroll.nested.\(Self.nextSerial)"
        reference = ReferenceScrollArbiter(pagingAxis: .horizontal, coordinateSpaceName: coordinateSpaceName)
    }

    /// At least one inner is registered; the outer asks only then (an outer without inners behaves as today).
    var hasParticipants: Bool { !tokens.isEmpty }
    /// False while the outer cannot take a swipe (scroll disabled, no axis): its inners behave as if alone (no ask,
    /// tracking from touch-down: `PanEnvironment.hasArbiter` reads this), and an ask that still arrives is answered
    /// `.participant` without a sequence, a decision or a log entry.
    var isArbitrating: Bool { container?.canTakeSwipe ?? true }
    var isSequenceActive: Bool { reference.isSequenceActive }
    var currentOwner: ScrollOwner? { reference.currentOwner }
    /// Every call of the current or last sequence (cleared when a sequence begins).
    var log: [ScrollArbitrationLogEntry] { reference.log }

    // MARK: ScrollArbiter (participant side)

    func register(_ participant: any ScrollArbitrationParticipant, frame: CGRect) -> ScrollArbitrationToken {
        let token = reference.register(participant, frame: frame)
        tokens.insert(token)
        return token
    }

    func update(_ token: ScrollArbitrationToken, frame: CGRect) {
        reference.update(token, frame: frame)
    }

    func unregister(_ token: ScrollArbitrationToken) {
        tokens.remove(token)
        reference.unregister(token)
    }

    func owner(ofDragFrom start: CGPoint, translation: CGSize, touchCount: Int,
               participant: ScrollArbitrationToken) -> ScrollOwner {
        // Rule 6 must not hand a swipe to a container that ignores it (see `isArbitrating`).
        guard isArbitrating else { return .participant }
        prepare(translation)
        return reference.owner(ofDragFrom: start, translation: translation, touchCount: touchCount, participant: participant)
    }

    // MARK: Container side

    /// The outer's own question, through the same rules and cache. `start` is in the outer's content space.
    func containerOwner(ofDragFrom start: CGPoint, translation: CGSize, touchCount: Int) -> ScrollOwner {
        prepare(translation)
        return reference.containerOwner(ofDragFrom: start, translation: translation, touchCount: touchCount)
    }

    /// First finger down on the outer. A no-op while a sequence is active.
    func beginSequence() {
        beginSequence(lazily: false)
    }

    /// Last finger up on the outer. A no-op when idle.
    func endSequence() {
        guard reference.isSequenceActive else { return }
        reference.endSequence()
        beganLazily = false
    }

    /// A registered inner's own sequence ended: closes a sequence that began lazily at an ask (≤ 17 without the
    /// outer's observer); one begun by the outer's touch-down ends with the outer.
    func participantSequenceEnded() {
        if beganLazily { endSequence() }
    }

    private func beginSequence(lazily: Bool) {
        guard !reference.isSequenceActive else { return }
        reference.clearLog()
        reference.isContainerMoving = container?.isMovingForNestedArbiter ?? false
        reference.beginSequence()
        beganLazily = lazily
    }

    private func prepare(_ translation: CGSize) {
        if !reference.isSequenceActive { beginSequence(lazily: true) }
        let axes = container?.axes ?? [.horizontal, .vertical]
        switch (axes.contains(.horizontal), axes.contains(.vertical)) {
        case (true, false):
            reference.pagingAxis = .horizontal
            reference.directionTolerance = 30
        case (false, true):
            reference.pagingAxis = .vertical
            reference.directionTolerance = 30
        default:
            // Two axes: the outer follows any direction, so rule 1 is moot; the finger's dominant axis decides rule 5.
            reference.pagingAxis = abs(translation.width) >= abs(translation.height) ? .horizontal : .vertical
            reference.directionTolerance = 90
        }
    }
}
