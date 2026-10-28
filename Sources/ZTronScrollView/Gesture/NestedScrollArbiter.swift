import SwiftUI
import ScrollArbitration

/// The arbiter a `ZTronScrollView` offers to the `ZTronScrollView`s in its content (docs/design/NESTED-arbitration.md
/// §3 "Container side"). One per view identity, owned by the outer's `PanCoordinator`, injected into the content's
/// environment together with a named coordinate space on the outer's *content*: in that space an inner's frame does
/// not change while the outer scrolls, so registration stays cold.
///
/// Decisions go through `ScrollArbitrationRules.decide` (a `ReferenceScrollArbiter` does the bookkeeping):
/// - `pagingAxis` is the outer's single *effective* axis (D15: declared axes plus any axis its zoomed content
///   exceeds the viewport on, read at the deciding call); an outer effective on two axes decides with the dominant
///   axis of the translation and rule 1 disabled (it can follow any direction);
/// - `isContainerMoving` is the outer's `isMovingWithoutFinger`, snapshotted when the sequence begins;
/// - a sequence begins at the outer's touch-down (18+ spatial observer) or lazily at the first ask (≤ 17, gated
///   observer) and ends when the outer's pan session returns to idle;
/// - an outer that cannot scroll (`.ztronScrollDisabled`, no axis) is no container: its inners are answered
///   `.participant` without a sequence or a decision, as if they were alone.
/// - a participant whose UIKit pan declined the sequence (D60) is passed over until the sequence ends
///   (`participantDeclined(_:)`).
/// The log holds the current (or last) sequence only; the frozen contract is used additively (S16).
@MainActor
final class NestedScrollArbiter: ScrollArbiter {
    private static var nextSerial = 0
    private let reference: ReferenceScrollArbiter
    private var tokens: Set<ScrollArbitrationToken> = []
    /// Every registered participant's frame, also while the reference holds `.null` for it.
    private var frames: [ScrollArbitrationToken: CGRect] = [:]
    /// Participants that declined the active sequence: the reference holds `.null` for them until it ends.
    private var declined: Set<ScrollArbitrationToken> = []
    /// The container took a swipe decided for a participant that declined it afterwards.
    private var revived = false
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
    /// The decided owner; `.container` once the container took a swipe its participant declined (the reference keeps
    /// its own cached answer).
    var currentOwner: ScrollOwner? { revived ? .container : reference.currentOwner }
    /// Every call of the current or last sequence (cleared when a sequence begins).
    var log: [ScrollArbitrationLogEntry] { reference.log }

    // MARK: ScrollArbiter (participant side)

    func register(_ participant: any ScrollArbitrationParticipant, frame: CGRect) -> ScrollArbitrationToken {
        let token = reference.register(participant, frame: frame)
        tokens.insert(token)
        frames[token] = frame
        return token
    }

    func update(_ token: ScrollArbitrationToken, frame: CGRect) {
        if tokens.contains(token) { frames[token] = frame }
        // A declined participant's frame reaches the reference when the sequence ends.
        guard !declined.contains(token) else { return }
        reference.update(token, frame: frame)
    }

    func unregister(_ token: ScrollArbitrationToken) {
        tokens.remove(token)
        frames[token] = nil
        declined.remove(token)
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
        revived = false
        for token in declined { reference.update(token, frame: frames[token] ?? .null) }
        declined.removeAll()
    }

    /// The participant with `token` declined this sequence: its UIKit pan's `shouldBegin` answered false (D60 §2
    /// "Decline"). Until the sequence ends the reference sees a `.null` frame for it, so `containerOwner` resolves past
    /// it to the next participant under the point, or to `.container` when there is none, and the rules (rule 3
    /// included) never hand it a swipe it declined. If the sequence was already decided for it (the container asked
    /// first), the container takes the swipe after all. A sequence that is not active begins lazily, and ends with
    /// that participant's (`participantSequenceEnded()`). External arbiters are not told.
    func participantDeclined(_ token: ScrollArbitrationToken) {
        guard isArbitrating, tokens.contains(token), !declined.contains(token) else { return }
        if !reference.isSequenceActive { beginSequence(lazily: true) }
        declined.insert(token)
        reference.update(token, frame: .null)
        guard reference.currentOwner == .participant, decidedToken == token else { return }
        revived = true
        container?.reviveAfterParticipantDeclined()
    }

    /// The participant the active sequence was decided for: the reference keeps it private, its log records it (the
    /// log is cleared when a sequence begins, so the last deciding entry is this sequence's).
    private var decidedToken: ScrollArbitrationToken? {
        for entry in reference.log.reversed() {
            if case let .owner(_, _, _, _, _, _, resolved, _, true, _) = entry { return resolved }
        }
        return nil
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
        // D15 effective axes, not the declared ones: a zoomed outer whose content exceeds the viewport on an axis
        // outside `axes` pages on that axis too (rule 1 must not hand such a swipe to an inner that cannot move).
        let axes = container?.effectiveAxes ?? [.horizontal, .vertical]
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
