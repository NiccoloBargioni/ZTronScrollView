import SwiftUI
import ScrollArbitration

/// A participant whose answers the test sets directly; records every direction `canFollow` is asked about.
@MainActor final class FakeParticipant: ScrollArbitrationParticipant {
    var follow: [FingerDirection: Bool] = [:]
    var isMovingWithoutFinger: Bool
    var isZoomEnabled: Bool
    /// The `canFollow` arguments, in call order.
    private(set) var askedDirections: [FingerDirection] = []
    var canFollowCalls: Int { askedDirections.count }

    init(canFollow: Bool = false, moving: Bool = false, zoom: Bool = false) {
        isMovingWithoutFinger = moving
        isZoomEnabled = zoom
        setCanFollow(canFollow)
    }

    func setCanFollow(_ value: Bool) {
        follow = [.left: value, .right: value, .up: value, .down: value]
    }

    func canFollow(_ direction: FingerDirection) -> Bool {
        askedDirections.append(direction)
        return follow[direction] ?? false
    }
}

/// Keeps objects alive for as long as the test suite instance that owns it.
@MainActor final class Retainer {
    var objects: [AnyObject] = []
}

/// An input with every flag false, one touch, tolerance 30, horizontal axis and translation (100, 0),
/// unless overridden.
func makeInput(axis: Axis = .horizontal, tolerance: Double = 30,
               translation: CGSize = CGSize(width: 100, height: 0), touchCount: Int = 1,
               canFollow: Bool = false, participantMoving: Bool = false, zoom: Bool = false,
               containerMoving: Bool = false) -> ScrollArbitrationInput {
    ScrollArbitrationInput(pagingAxis: axis, directionTolerance: tolerance, translation: translation,
                           touchCount: touchCount, participantCanFollow: canFollow,
                           participantMovingAtTouchDown: participantMoving, participantZoomEnabled: zoom,
                           containerMovingAtTouchDown: containerMoving)
}

/// `translation` written for the horizontal axis, re-expressed for `axis` (components swapped for vertical).
func oriented(_ width: CGFloat, _ height: CGFloat, for axis: Axis) -> CGSize {
    axis == .horizontal ? CGSize(width: width, height: height) : CGSize(width: height, height: width)
}

/// The fields of a `.owner` log entry, for assertions that ignore some of them.
struct OwnerRecord: Equatable {
    var caller: ScrollArbitrationToken
    var askedBy: ScrollOwner
    var sequence: Int?
    var resolved: ScrollArbitrationToken?
    var input: ScrollArbitrationInput?
    var decided: Bool
    var result: ScrollOwner
}

extension ScrollArbitrationLogEntry {
    var ownerRecord: OwnerRecord? {
        guard case let .owner(caller, askedBy, _, _, _, sequence, resolved, input, decided, result) = self else {
            return nil
        }
        return OwnerRecord(caller: caller, askedBy: askedBy, sequence: sequence, resolved: resolved,
                           input: input, decided: decided, result: result)
    }
}

extension ReferenceScrollArbiter {
    var ownerRecords: [OwnerRecord] { log.compactMap { $0.ownerRecord } }
    var lastOwnerRecord: OwnerRecord? { ownerRecords.last }

    func decidedCount(inSequence id: Int?) -> Int {
        ownerRecords.filter { $0.decided && $0.sequence == id }.count
    }
}
