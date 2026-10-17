import SwiftUI
import Testing
import ScrollArbitration

private let frame = CGRect(x: 0, y: 0, width: 300, height: 300)
private let inside = CGPoint(x: 150, y: 150)
private let outside = CGPoint(x: 1_000, y: 1_000)
/// 0°: finger left along the horizontal paging axis.
private let onAxis = CGSize(width: -100, height: 0)
/// 90°: finger straight up.
private let offAxis = CGSize(width: 0, height: -100)

@Suite @MainActor struct ReferenceArbiterTests {
    @Test func defaults() {
        let arbiter = ReferenceScrollArbiter()
        #expect(arbiter.pagingAxis == .horizontal)
        #expect(arbiter.directionTolerance == 30)
        #expect(arbiter.isContainerMoving == false)
        #expect(!arbiter.coordinateSpaceName.isEmpty)
        #expect(arbiter.log.isEmpty)
        #expect(arbiter.isSequenceActive == false)
        #expect(arbiter.currentOwner == nil)

        let custom = ReferenceScrollArbiter(pagingAxis: .vertical, directionTolerance: 12, coordinateSpaceName: "x")
        #expect(custom.pagingAxis == .vertical)
        #expect(custom.directionTolerance == 12)
        #expect(custom.coordinateSpaceName == "x")
    }

    @Test func registerReturnsDistinctTokens() {
        let arbiter = ReferenceScrollArbiter()
        let other = ReferenceScrollArbiter()
        let participant = retained()
        let first = arbiter.register(participant, frame: frame)
        let second = arbiter.register(participant, frame: frame)
        let foreign = other.register(participant, frame: frame)
        #expect(first != second)
        #expect(foreign != first && foreign != second)
        #expect(arbiter.log == [.register(first, frame: frame), .register(second, frame: frame)])
        #expect(other.log == [.register(foreign, frame: frame)])
    }

    @Test func updateMovesKnownFramesAndIgnoresUnknownTokens() {
        let arbiter = ReferenceScrollArbiter()
        let participant = retained()
        let token = arbiter.register(participant, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let moved = CGRect(x: 100, y: 100, width: 100, height: 100)
        #expect(arbiter.participant(at: CGPoint(x: 150, y: 150)) == nil)
        arbiter.update(token, frame: moved)
        #expect(arbiter.participant(at: CGPoint(x: 150, y: 150)) == token)
        #expect(arbiter.participant(at: CGPoint(x: 50, y: 50)) == nil)
        #expect(arbiter.log.last == .update(token, frame: moved, known: true))

        let foreign = ReferenceScrollArbiter().register(participant, frame: frame)
        arbiter.update(foreign, frame: frame)
        #expect(arbiter.participant(at: CGPoint(x: 50, y: 50)) == nil)
        #expect(arbiter.participant(at: CGPoint(x: 150, y: 150)) == token)
        #expect(arbiter.log.last == .update(foreign, frame: frame, known: false))
    }

    @Test func unregisterLifetimes() {
        let arbiter = ReferenceScrollArbiter()
        let participant = retained(canFollow: true)
        let token = arbiter.register(participant, frame: frame)
        arbiter.unregister(token)
        #expect(arbiter.participant(at: inside) == nil)
        #expect(arbiter.log.last == .unregister(token, known: true))
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .container)
        #expect(arbiter.lastOwnerRecord?.decided == false)
        #expect(arbiter.lastOwnerRecord?.resolved == nil)
        #expect(participant.canFollowCalls == 0)
        arbiter.unregister(token)
        #expect(arbiter.log.last == .unregister(token, known: false))
        let foreign = ReferenceScrollArbiter().register(participant, frame: frame)
        arbiter.unregister(foreign)
        #expect(arbiter.log.last == .unregister(foreign, known: false))
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: foreign) == .container)
        #expect(arbiter.lastOwnerRecord?.decided == false)
    }

    @Test func noSequenceDecidesAfreshEveryCall() {
        let arbiter = ReferenceScrollArbiter()
        let token = arbiter.register(retained(canFollow: false), frame: frame)
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .container)
        #expect(arbiter.owner(ofDragFrom: inside, translation: offAxis, touchCount: 1, participant: token) == .participant)
        let records = arbiter.ownerRecords
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.sequence == nil && $0.decided && $0.resolved == token })
        #expect(arbiter.currentOwner == nil)
    }

    @Test func cachingWhenParticipantAsksFirst() {
        let arbiter = ReferenceScrollArbiter()
        let participant = retained(canFollow: true)
        let token = arbiter.register(participant, frame: frame)
        arbiter.beginSequence()
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .participant)
        participant.setCanFollow(false)
        #expect(arbiter.owner(ofDragFrom: inside, translation: offAxis, touchCount: 1, participant: token) == .participant)
        // Arguments that would decide `.container` afresh still get the cached owner.
        #expect(arbiter.owner(ofDragFrom: CGPoint(x: 10, y: 10), translation: onAxis, touchCount: 1,
                              participant: token) == .participant)
        #expect(arbiter.containerOwner(ofDragFrom: inside, translation: onAxis, touchCount: 1) == .participant)
        #expect(arbiter.currentOwner == .participant)
        #expect(arbiter.decidedCount(inSequence: 1) == 1)
        #expect(participant.canFollowCalls == 1)
        arbiter.endSequence()
        #expect(arbiter.currentOwner == nil)

        arbiter.beginSequence()
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .container)
        #expect(arbiter.decidedCount(inSequence: 2) == 1)
        arbiter.endSequence()
    }

    @Test func cachingWhenContainerAsksFirst() {
        let arbiter = ReferenceScrollArbiter()
        let participant = retained(canFollow: false)
        let token = arbiter.register(participant, frame: frame)
        arbiter.beginSequence()
        #expect(arbiter.containerOwner(ofDragFrom: inside, translation: onAxis, touchCount: 1) == .container)
        participant.setCanFollow(true)
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .container)
        #expect(arbiter.currentOwner == .container)
        #expect(arbiter.decidedCount(inSequence: 1) == 1)
        let first = arbiter.ownerRecords.first
        #expect(first?.askedBy == .container && first?.decided == true && first?.resolved == token)
        arbiter.endSequence()

        arbiter.beginSequence()
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .participant)
        #expect(arbiter.containerOwner(ofDragFrom: inside, translation: onAxis, touchCount: 1) == .participant)
        #expect(arbiter.decidedCount(inSequence: 2) == 1)
    }

    @Test func movingStateIsSnapshottedAtTouchDown() {
        // Participant moving at touch-down, stopped before the decision: rule 3 from the snapshot.
        let arbiter = ReferenceScrollArbiter()
        let participant = retained(canFollow: false, moving: true)
        let token = arbiter.register(participant, frame: frame)
        arbiter.isContainerMoving = true
        arbiter.beginSequence()
        participant.isMovingWithoutFinger = false
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .participant)
        #expect(arbiter.lastOwnerRecord?.input?.participantMovingAtTouchDown == true)
        arbiter.endSequence()

        // Container moving at touch-down, stopped before the decision: rule 4 from the snapshot.
        participant.setCanFollow(true)
        arbiter.isContainerMoving = true
        arbiter.beginSequence()
        arbiter.isContainerMoving = false
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .container)
        arbiter.endSequence()

        // Container starts moving after touch-down: not counted.
        arbiter.isContainerMoving = false
        arbiter.beginSequence()
        arbiter.isContainerMoving = true
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .participant)
        arbiter.endSequence()

        // Participant starts moving after touch-down: not counted (snapshot false).
        arbiter.isContainerMoving = false
        participant.setCanFollow(false)
        arbiter.beginSequence()
        participant.isMovingWithoutFinger = true
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .container)
        arbiter.endSequence()
    }

    @Test func participantRegisteredAfterBeginIsReadLive() {
        let arbiter = ReferenceScrollArbiter()
        arbiter.beginSequence()
        let late = retained(canFollow: false, moving: true)
        let token = arbiter.register(late, frame: frame)
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .participant)
        #expect(arbiter.lastOwnerRecord?.input?.participantMovingAtTouchDown == true)
    }

    @Test func overlappingParticipantsResolveToSmallestFrame() {
        let arbiter = ReferenceScrollArbiter()
        let outer = retained(canFollow: false)
        let inner = retained(canFollow: true)
        let outerToken = arbiter.register(outer, frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let innerToken = arbiter.register(inner, frame: CGRect(x: 100, y: 100, width: 50, height: 50))
        let start = CGPoint(x: 120, y: 120)
        #expect(arbiter.participant(at: start) == innerToken)

        arbiter.beginSequence()
        #expect(arbiter.owner(ofDragFrom: start, translation: onAxis, touchCount: 1, participant: innerToken) == .participant)
        #expect(arbiter.owner(ofDragFrom: start, translation: onAxis, touchCount: 1, participant: outerToken) == .container)
        #expect(arbiter.lastOwnerRecord?.resolved == innerToken)
        #expect(outer.canFollowCalls == 0)
        arbiter.endSequence()

        // The outer participant asks first: the rules still run on the inner (resolved) participant.
        arbiter.beginSequence()
        #expect(arbiter.owner(ofDragFrom: start, translation: onAxis, touchCount: 1, participant: outerToken) == .container)
        let record = arbiter.lastOwnerRecord
        #expect(record?.decided == true && record?.resolved == innerToken)
        #expect(record?.input?.participantCanFollow == true)
        #expect(outer.canFollowCalls == 0)
        #expect(inner.canFollowCalls == 2)
        #expect(arbiter.currentOwner == .participant)
        #expect(arbiter.owner(ofDragFrom: start, translation: onAxis, touchCount: 1, participant: innerToken) == .participant)
        arbiter.endSequence()

        // Start outside every frame: the asking participant is resolved and decides for itself.
        outer.setCanFollow(true)
        arbiter.beginSequence()
        #expect(arbiter.owner(ofDragFrom: outside, translation: onAxis, touchCount: 1, participant: outerToken) == .participant)
        #expect(arbiter.lastOwnerRecord?.resolved == outerToken)
        #expect(arbiter.lastOwnerRecord?.decided == true)
        #expect(outer.canFollowCalls == 1)
        // The container's touch-down point is outside every frame too: it still gets the cached owner.
        #expect(arbiter.containerOwner(ofDragFrom: outside, translation: onAxis, touchCount: 1) == .participant)
        arbiter.endSequence()
    }

    @Test func equalFramesResolveToMostRecentRegistration() {
        let arbiter = ReferenceScrollArbiter()
        let first = arbiter.register(retained(), frame: frame)
        let second = arbiter.register(retained(), frame: frame)
        #expect(first != second)
        #expect(arbiter.participant(at: inside) == second)
    }

    @Test func containerWithNoParticipantUnderStartLeavesSequenceUndecided() {
        let arbiter = ReferenceScrollArbiter()
        let token = arbiter.register(retained(canFollow: true), frame: frame)
        arbiter.beginSequence()
        #expect(arbiter.containerOwner(ofDragFrom: outside, translation: onAxis, touchCount: 1) == .container)
        let record = arbiter.lastOwnerRecord
        #expect(record?.decided == false && record?.resolved == nil && record?.input == nil)
        #expect(record?.sequence == 1)
        #expect(arbiter.currentOwner == nil)
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .participant)
        #expect(arbiter.lastOwnerRecord?.decided == true)
        #expect(arbiter.decidedCount(inSequence: 1) == 1)
    }

    @Test func sequenceBookkeeping() {
        let arbiter = ReferenceScrollArbiter()
        let token = arbiter.register(retained(canFollow: true), frame: frame)
        arbiter.clearLog()
        arbiter.beginSequence()
        #expect(arbiter.isSequenceActive)
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .participant)
        arbiter.beginSequence()
        #expect(arbiter.isSequenceActive)
        #expect(arbiter.currentOwner == .participant)
        arbiter.endSequence()
        #expect(!arbiter.isSequenceActive)
        arbiter.endSequence()
        arbiter.beginSequence()
        arbiter.endSequence()
        arbiter.beginSequence()
        arbiter.endSequence()
        let bookkeeping = arbiter.log.filter { $0.ownerRecord == nil }
        #expect(bookkeeping == [
            .beginSequence(id: 1, started: true), .beginSequence(id: 1, started: false),
            .endSequence(id: 1, ended: true), .endSequence(id: nil, ended: false),
            .beginSequence(id: 2, started: true), .endSequence(id: 2, ended: true),
            .beginSequence(id: 3, started: true), .endSequence(id: 3, ended: true),
        ])
        #expect(arbiter.decidedCount(inSequence: 1) == 1)
    }

    @Test func askedByRecordsWhichSideAsked() {
        let arbiter = ReferenceScrollArbiter()
        let token = arbiter.register(retained(), frame: frame)
        _ = arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token)
        #expect(arbiter.lastOwnerRecord?.askedBy == .participant)
        _ = arbiter.containerOwner(ofDragFrom: inside, translation: onAxis, touchCount: 1)
        #expect(arbiter.lastOwnerRecord?.askedBy == .container)
        #expect(arbiter.lastOwnerRecord?.caller == token)
    }

    @Test func logScript() {
        let arbiter = ReferenceScrollArbiter()
        let token = arbiter.register(retained(canFollow: true), frame: frame)
        arbiter.beginSequence()
        let first = arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token)
        let containerStart = CGPoint(x: 151, y: 149)
        let containerTranslation = CGSize(width: -12, height: 1)
        let second = arbiter.containerOwner(ofDragFrom: containerStart, translation: containerTranslation, touchCount: 2)
        arbiter.endSequence()
        arbiter.unregister(token)
        #expect(first == .participant && second == .participant)

        let input = ScrollArbitrationInput(pagingAxis: .horizontal, directionTolerance: 30, translation: onAxis,
                                           touchCount: 1, participantCanFollow: true,
                                           participantMovingAtTouchDown: false, participantZoomEnabled: false,
                                           containerMovingAtTouchDown: false)
        #expect(arbiter.log == [
            .register(token, frame: frame),
            .beginSequence(id: 1, started: true),
            .owner(caller: token, askedBy: .participant, start: inside, translation: onAxis, touchCount: 1,
                   sequence: 1, resolved: token, input: input, decided: true, result: .participant),
            .owner(caller: token, askedBy: .container, start: containerStart, translation: containerTranslation,
                   touchCount: 2, sequence: 1, resolved: token, input: nil, decided: false, result: .participant),
            .endSequence(id: 1, ended: true),
            .unregister(token, known: true),
        ])
    }

    @Test func clearLogKeepsRegistrationsAndSequence() {
        let arbiter = ReferenceScrollArbiter()
        let token = arbiter.register(retained(canFollow: true), frame: frame)
        arbiter.beginSequence()
        _ = arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token)
        arbiter.clearLog()
        #expect(arbiter.log.isEmpty)
        #expect(arbiter.participant(at: inside) == token)
        #expect(arbiter.isSequenceActive)
        #expect(arbiter.currentOwner == .participant)
        arbiter.endSequence()
        #expect(arbiter.log == [.endSequence(id: 1, ended: true)])
    }

    @Test func deallocatedParticipantBecomesUnknown() {
        let arbiter = ReferenceScrollArbiter()
        let token = registerTemporaryParticipant(with: arbiter)
        #expect(arbiter.participant(at: inside) == nil)
        arbiter.beginSequence()
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .container)
        #expect(arbiter.lastOwnerRecord?.decided == false)
        #expect(arbiter.lastOwnerRecord?.resolved == nil)
        #expect(arbiter.currentOwner == nil)
        arbiter.update(token, frame: frame)
        #expect(arbiter.log.last == .update(token, frame: frame, known: false))
        arbiter.unregister(token)
        #expect(arbiter.log.last == .unregister(token, known: false))
    }

    @Test func canFollowIsAskedAboutTheFingerDirectionAlongThePagingAxis() {
        let arbiter = ReferenceScrollArbiter()
        let participant = retained()
        participant.follow = [.left: false, .right: true, .up: true, .down: true]
        let token = arbiter.register(participant, frame: frame)
        func owner(_ width: CGFloat, _ height: CGFloat) -> ScrollOwner {
            arbiter.owner(ofDragFrom: inside, translation: CGSize(width: width, height: height), touchCount: 1,
                          participant: token)
        }
        // Horizontal paging: the on-axis sign picks the direction; the (within-tolerance) off-axis one is ignored.
        #expect(owner(-100, 40) == .container)
        #expect(participant.askedDirections == [.left])
        #expect(arbiter.lastOwnerRecord?.input?.participantCanFollow == false)
        #expect(owner(100, -40) == .participant)
        #expect(participant.askedDirections == [.left, .right])
        #expect(arbiter.lastOwnerRecord?.input?.participantCanFollow == true)

        arbiter.pagingAxis = .vertical
        participant.follow = [.left: true, .right: true, .up: false, .down: true]
        #expect(owner(40, -100) == .container)
        #expect(participant.askedDirections.last == .up)
        #expect(owner(-40, 100) == .participant)
        #expect(participant.askedDirections.last == .down)

        // The container's question asks the same direction.
        arbiter.beginSequence()
        #expect(arbiter.containerOwner(ofDragFrom: inside, translation: CGSize(width: 40, height: -100),
                                       touchCount: 1) == .container)
        #expect(participant.askedDirections.last == .up)
        #expect(participant.canFollowCalls == 5)
        arbiter.endSequence()
    }

    @Test func pagingAxisIsReadAtEachDecision() {
        let arbiter = ReferenceScrollArbiter()
        let token = arbiter.register(retained(canFollow: false), frame: frame)
        let up = CGSize(width: 0, height: -100)
        let left = CGSize(width: -100, height: 0)
        func owner(_ translation: CGSize) -> ScrollOwner {
            arbiter.owner(ofDragFrom: inside, translation: translation, touchCount: 1, participant: token)
        }
        // Horizontal paging: an upward drag is off-axis (rule 1).
        #expect(owner(up) == .participant)
        #expect(arbiter.lastOwnerRecord?.input?.pagingAxis == .horizontal)
        // Vertical paging: the same drag is on-axis and falls through to rule 6; a leftward one is off-axis.
        arbiter.pagingAxis = .vertical
        #expect(owner(up) == .container)
        #expect(arbiter.lastOwnerRecord?.input?.pagingAxis == .vertical)
        #expect(owner(left) == .participant)
        #expect(arbiter.containerOwner(ofDragFrom: inside, translation: left, touchCount: 1) == .participant)
        #expect(arbiter.containerOwner(ofDragFrom: inside, translation: up, touchCount: 1) == .container)
        // Changed after touch-down, before the decision: the deciding call reads the new axis.
        arbiter.pagingAxis = .horizontal
        arbiter.beginSequence()
        arbiter.pagingAxis = .vertical
        #expect(owner(up) == .container)
        #expect(arbiter.lastOwnerRecord?.input?.pagingAxis == .vertical)
        arbiter.endSequence()
    }

    @Test func directionToleranceIsReadAtEachDecision() {
        let arbiter = ReferenceScrollArbiter()
        let token = arbiter.register(retained(canFollow: false), frame: frame)
        // About 20° off the horizontal paging axis.
        let twentyDegrees = CGSize(width: -100, height: 36.4)
        func owner() -> ScrollOwner {
            arbiter.owner(ofDragFrom: inside, translation: twentyDegrees, touchCount: 1, participant: token)
        }
        #expect(owner() == .container)
        #expect(arbiter.lastOwnerRecord?.input?.directionTolerance == 30)
        arbiter.directionTolerance = 10
        #expect(owner() == .participant)
        #expect(arbiter.lastOwnerRecord?.input?.directionTolerance == 10)
        #expect(arbiter.containerOwner(ofDragFrom: inside, translation: twentyDegrees, touchCount: 1) == .participant)
        #expect(arbiter.lastOwnerRecord?.input?.directionTolerance == 10)
        // Changed after touch-down, before the decision: the deciding call reads the new tolerance.
        arbiter.beginSequence()
        arbiter.directionTolerance = 45
        #expect(owner() == .container)
        #expect(arbiter.lastOwnerRecord?.input?.directionTolerance == 45)
        arbiter.endSequence()
    }

    @Test func multiTouchZoomIsDecidedThroughTheArbiter() {
        let arbiter = ReferenceScrollArbiter()
        let participant = retained(canFollow: false, zoom: true)
        let token = arbiter.register(participant, frame: frame)
        arbiter.isContainerMoving = true
        func owner(touches: Int) -> ScrollOwner {
            arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: touches, participant: token)
        }
        // Rule 2 beats rule 4 only with two or more touches.
        #expect(owner(touches: 2) == .participant)
        var input = arbiter.lastOwnerRecord?.input
        #expect(input?.touchCount == 2 && input?.participantZoomEnabled == true)
        #expect(owner(touches: 1) == .container)
        #expect(arbiter.lastOwnerRecord?.input?.touchCount == 1)

        // Zoom switched off after touch-down: read live at the deciding call, not snapshotted.
        arbiter.beginSequence()
        participant.isZoomEnabled = false
        #expect(owner(touches: 2) == .container)
        input = arbiter.lastOwnerRecord?.input
        #expect(input?.touchCount == 2 && input?.participantZoomEnabled == false)
        arbiter.endSequence()

        // Zoom switched on after touch-down, container asks first with two touches.
        arbiter.beginSequence()
        participant.isZoomEnabled = true
        #expect(arbiter.containerOwner(ofDragFrom: inside, translation: onAxis, touchCount: 2) == .participant)
        input = arbiter.lastOwnerRecord?.input
        #expect(input?.touchCount == 2 && input?.participantZoomEnabled == true)
        #expect(owner(touches: 1) == .participant)
        arbiter.endSequence()
    }

    @Test func unknownTokenOverALiveParticipantNeverDecides() {
        let arbiter = ReferenceScrollArbiter()
        let participant = retained(canFollow: true)
        let token = arbiter.register(participant, frame: frame)
        let foreign = ReferenceScrollArbiter().register(participant, frame: frame)
        let gone = arbiter.register(retained(canFollow: true), frame: frame)
        arbiter.unregister(gone)
        #expect(arbiter.participant(at: inside) == token)
        func expectIgnored(_ unknown: ScrollArbitrationToken, sequence: Int?) {
            #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: unknown)
                    == .container)
            let record = arbiter.lastOwnerRecord
            #expect(record?.decided == false && record?.resolved == nil && record?.input == nil)
            #expect(record?.sequence == sequence)
        }

        expectIgnored(foreign, sequence: nil)
        expectIgnored(gone, sequence: nil)
        arbiter.beginSequence()
        expectIgnored(foreign, sequence: 1)
        expectIgnored(gone, sequence: 1)
        #expect(arbiter.currentOwner == nil)
        #expect(participant.canFollowCalls == 0)
        // The registered participant still decides for the sequence.
        #expect(arbiter.owner(ofDragFrom: inside, translation: onAxis, touchCount: 1, participant: token) == .participant)
        #expect(arbiter.lastOwnerRecord?.decided == true)
        #expect(arbiter.currentOwner == .participant)
        // After the decision unknown tokens still get `.container` and are never resolved.
        expectIgnored(foreign, sequence: 1)
        #expect(arbiter.decidedCount(inSequence: 1) == 1)
        arbiter.endSequence()
    }

    /// Registers a participant that is released when this function returns.
    private func registerTemporaryParticipant(with arbiter: ReferenceScrollArbiter) -> ScrollArbitrationToken {
        let participant = FakeParticipant(canFollow: true)
        let token = arbiter.register(participant, frame: frame)
        #expect(arbiter.participant(at: inside) == token)
        return token
    }

    /// The arbiter holds participants weakly; this keeps them alive for the whole test.
    private let retainer = Retainer()

    private func retained(canFollow: Bool = false, moving: Bool = false, zoom: Bool = false) -> FakeParticipant {
        let participant = FakeParticipant(canFollow: canFollow, moving: moving, zoom: zoom)
        retainer.objects.append(participant)
        return participant
    }
}

@Suite @MainActor struct EnvironmentTests {
    @Test func scrollArbiterDefaultsToNilAndRoundTrips() {
        #expect(EnvironmentValues().scrollArbiter == nil)
        let arbiter = ReferenceScrollArbiter()
        var environment = EnvironmentValues()
        environment.scrollArbiter = arbiter
        #expect(environment.scrollArbiter === arbiter)
        environment.scrollArbiter = nil
        #expect(environment.scrollArbiter == nil)
    }

    @Test func gestureName() {
        #expect(scrollArbitrationGestureName == "ScrollArbitration.participant")
    }
}
