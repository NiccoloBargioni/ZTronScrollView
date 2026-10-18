import SwiftUI
import ScrollArbitration

@MainActor final class StandInModel: ScrollArbitrationParticipant, ObservableObject {
    @Published var canFollowValue = true
    @Published var moving = false
    var token: ScrollArbitrationToken?
    var panOwner: ScrollOwner?
    var observerCount = 0
    var sequenceBegun = false

    func canFollow(_ direction: FingerDirection) -> Bool { canFollowValue }
    var isMovingWithoutFinger: Bool { moving }
    var isZoomEnabled: Bool { true }
}
