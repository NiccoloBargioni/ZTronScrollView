import SwiftUI
import ScrollArbitration

@MainActor final class StandInModel: ScrollArbitrationParticipant, ObservableObject {
    @Published var canFollowValue = true
    @Published var moving = false
    /// Launch arguments (`-canFollow<i> 0|1`, `-moving<i> 1`) preset the toggles so tests need not tap them.
    init(index: Int) {
        let d = UserDefaults.standard
        if d.object(forKey: "canFollow\(index)") != nil { canFollowValue = d.bool(forKey: "canFollow\(index)") }
        if d.object(forKey: "moving\(index)") != nil { moving = d.bool(forKey: "moving\(index)") }
    }

    var token: ScrollArbitrationToken?
    var panOwner: ScrollOwner?
    var observerCount = 0
    var sequenceBegun = false

    func canFollow(_ direction: FingerDirection) -> Bool { canFollowValue }
    var isMovingWithoutFinger: Bool { moving }
    var isZoomEnabled: Bool { true }
}
