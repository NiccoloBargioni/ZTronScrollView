import SwiftUI

/// A complete, drawing-free ``ScrollArbiter`` that implements every arbitration rule, for tests on both sides
/// of the contract and for simple containers.
///
/// - **Sequences.** ``beginSequence()`` and ``endSequence()`` model the first finger going down and the last
///   finger going up. Inside a sequence the first ownership question runs ``ScrollArbitrationRules/decide(_:)``
///   and caches the result; every later question from the resolved participant or the container gets the
///   cached answer, whatever its other arguments (see **Resolution** for other participants). With no active
///   sequence every question decides afresh and nothing is cached.
/// - **Touch-down state.** ``beginSequence()`` snapshots each registered participant's
///   ``ScrollArbitrationParticipant/isMovingWithoutFinger`` and ``isContainerMoving``. Participants registered
///   later, and every question asked outside a sequence, read those values live. `canFollow` and
///   `isZoomEnabled` are always read live at the deciding call.
/// - **Resolution.** A swipe belongs to the registered participant with the smallest frame containing the
///   start point (ties: the most recent registration), or, when no frame contains it, to the asking
///   participant. The rules always run on the resolved participant's state. A participant that is not the
///   resolved one gets `.container` ("not yours").
/// - **Unknown tokens** (never issued here, unregistered, or whose participant was deallocated) get
///   `.container` without deciding or touching the cache; ``update(_:frame:)`` and ``unregister(_:)``
///   ignore them.
/// - Participants are held weakly.
/// - **Log.** Every call is recorded in ``log``, which grows without bound until ``clearLog()``. A long-lived
///   container must call ``clearLog()`` regularly (for example right after each ``endSequence()``).
@MainActor public final class ReferenceScrollArbiter: ScrollArbiter {
    /// The axis the container pages along. Read at each deciding call.
    public var pagingAxis: Axis
    /// The rule 1 tolerance in degrees from the paging axis. Read at each deciding call.
    public var directionTolerance: Double
    /// Whether the container is moving now (for example decelerating). Snapshotted by ``beginSequence()``.
    public var isContainerMoving = false
    /// The name of the coordinate space that frames and start points are expressed in.
    public let coordinateSpaceName: String
    /// Every `register`, `update`, `unregister`, `beginSequence`, `endSequence`, `owner` and `containerOwner`
    /// call, in order. Append-only and unbounded until ``clearLog()``; each ownership entry holds a full
    /// ``ScrollArbitrationInput`` when it decided.
    public private(set) var log: [ScrollArbitrationLogEntry] = []

    /// Whether a sequence is active (between ``beginSequence()`` and ``endSequence()``).
    public var isSequenceActive: Bool { active != nil }
    /// The owner decided for the active sequence; `nil` when idle or not decided yet.
    public var currentOwner: ScrollOwner? { active?.decision?.owner }

    private struct Registration {
        weak var participant: (any ScrollArbitrationParticipant)?
        var frame: CGRect
    }

    private struct ActiveSequence {
        let id: Int
        let containerMoving: Bool
        let participantsMoving: [ScrollArbitrationToken: Bool]
        var decision: (token: ScrollArbitrationToken, owner: ScrollOwner)?
    }

    /// Process-wide, so a token from one arbiter is always unknown to another.
    private static var nextSerial: UInt64 = 1
    private var registrations: [ScrollArbitrationToken: Registration] = [:]
    private var active: ActiveSequence?
    private var lastSequenceID = 0

    /// Creates an idle arbiter with no registrations and an empty log.
    /// - Parameters:
    ///   - pagingAxis: The axis the container pages along.
    ///   - directionTolerance: The rule 1 tolerance in degrees.
    ///   - coordinateSpaceName: The coordinate space frames and start points are expressed in.
    public init(pagingAxis: Axis = .horizontal, directionTolerance: Double = 30,
                coordinateSpaceName: String = "ScrollArbitration.reference") {
        self.pagingAxis = pagingAxis
        self.directionTolerance = directionTolerance
        self.coordinateSpaceName = coordinateSpaceName
    }

    /// Registers `participant` (held weakly) with `frame` and returns a token never issued before.
    public func register(_ participant: any ScrollArbitrationParticipant, frame: CGRect) -> ScrollArbitrationToken {
        let token = ScrollArbitrationToken(serial: Self.nextSerial)
        Self.nextSerial += 1
        registrations[token] = Registration(participant: participant, frame: frame)
        log.append(.register(token, frame: frame))
        return token
    }

    /// Replaces the frame of a registered participant; unknown tokens are ignored (logged `known: false`).
    public func update(_ token: ScrollArbitrationToken, frame: CGRect) {
        let known = isKnown(token)
        if known { registrations[token]?.frame = frame }
        log.append(.update(token, frame: frame, known: known))
    }

    /// Removes a registration; unknown tokens are ignored (logged `known: false`).
    public func unregister(_ token: ScrollArbitrationToken) {
        let known = isKnown(token)
        registrations[token] = nil
        log.append(.unregister(token, known: known))
    }

    /// Returns who owns the drag, as asked by the participant with `token` (see the type's documentation).
    public func owner(ofDragFrom start: CGPoint, translation: CGSize, touchCount: Int,
                      participant token: ScrollArbitrationToken) -> ScrollOwner {
        arbitrate(caller: token, askedBy: .participant, start: start, translation: translation,
                  touchCount: touchCount)
    }

    /// Returns who owns the drag, as asked by the container, through the same rules and cache as
    /// ``owner(ofDragFrom:translation:touchCount:participant:)``.
    ///
    /// In a decided sequence this is the cached owner. Otherwise the swipe belongs to
    /// ``participant(at:)`` for `start`; with no participant there the answer is `.container` and nothing
    /// is cached, so a participant asking later still decides.
    public func containerOwner(ofDragFrom start: CGPoint, translation: CGSize, touchCount: Int) -> ScrollOwner {
        arbitrate(caller: participant(at: start) ?? .unregistered, askedBy: .container, start: start,
                  translation: translation, touchCount: touchCount)
    }

    /// The live participant with the smallest frame containing `point` (ties: the most recent registration),
    /// or `nil` when no frame contains it.
    public func participant(at point: CGPoint) -> ScrollArbitrationToken? {
        var best: (token: ScrollArbitrationToken, area: CGFloat)?
        for (token, registration) in registrations
        where registration.participant != nil && registration.frame.contains(point) {
            let area = registration.frame.width * registration.frame.height
            if let best, area > best.area || (area == best.area && token.serial < best.token.serial) { continue }
            best = (token, area)
        }
        return best?.token
    }

    /// Starts a sequence (first finger down) and snapshots who is moving. A no-op while one is active.
    public func beginSequence() {
        if let active {
            log.append(.beginSequence(id: active.id, started: false))
            return
        }
        lastSequenceID += 1
        var moving: [ScrollArbitrationToken: Bool] = [:]
        for (token, registration) in registrations {
            if let participant = registration.participant { moving[token] = participant.isMovingWithoutFinger }
        }
        active = ActiveSequence(id: lastSequenceID, containerMoving: isContainerMoving,
                                participantsMoving: moving, decision: nil)
        log.append(.beginSequence(id: lastSequenceID, started: true))
    }

    /// Ends the active sequence (last finger up) and drops its cached owner. A no-op when idle.
    public func endSequence() {
        log.append(.endSequence(id: active?.id, ended: active != nil))
        active = nil
    }

    /// Empties ``log``; registrations and the active sequence are untouched.
    public func clearLog() {
        log.removeAll()
    }

    private func isKnown(_ token: ScrollArbitrationToken) -> Bool {
        registrations[token]?.participant != nil
    }

    private func arbitrate(caller: ScrollArbitrationToken, askedBy: ScrollOwner, start: CGPoint,
                           translation: CGSize, touchCount: Int) -> ScrollOwner {
        var resolved: ScrollArbitrationToken?
        var input: ScrollArbitrationInput?
        var result = ScrollOwner.container
        if askedBy == .participant && !isKnown(caller) {
            // Unknown participant: `.container`, no decision, cache untouched.
        } else if let decision = active?.decision {
            resolved = decision.token
            if askedBy == .container || caller == decision.token { result = decision.owner }
        } else if let target = participant(at: start) ?? (isKnown(caller) ? caller : nil),
                  let participant = registrations[target]?.participant {
            let decidedInput = makeInput(target, participant, translation: translation, touchCount: touchCount)
            let owner = ScrollArbitrationRules.decide(decidedInput)
            active?.decision = (target, owner)
            resolved = target
            input = decidedInput
            if askedBy == .container || caller == target { result = owner }
        }
        log.append(.owner(caller: caller, askedBy: askedBy, start: start, translation: translation,
                          touchCount: touchCount, sequence: active?.id, resolved: resolved, input: input,
                          decided: input != nil, result: result))
        return result
    }

    private func makeInput(_ token: ScrollArbitrationToken, _ participant: any ScrollArbitrationParticipant,
                           translation: CGSize, touchCount: Int) -> ScrollArbitrationInput {
        let direction = ScrollArbitrationRules.fingerDirection(translation, along: pagingAxis)
        return ScrollArbitrationInput(
            pagingAxis: pagingAxis, directionTolerance: directionTolerance, translation: translation,
            touchCount: touchCount, participantCanFollow: participant.canFollow(direction),
            participantMovingAtTouchDown: active?.participantsMoving[token] ?? participant.isMovingWithoutFinger,
            participantZoomEnabled: participant.isZoomEnabled,
            containerMovingAtTouchDown: active?.containerMoving ?? isContainerMoving)
    }
}
