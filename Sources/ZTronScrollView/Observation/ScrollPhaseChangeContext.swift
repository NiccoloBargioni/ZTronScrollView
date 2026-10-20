import SwiftUI

/// What a phase observer receives besides the two phases (native `ScrollPhaseChangeContext`): the geometry at the
/// delivery and the velocity of the motion, in pt/s, `nil` when unknown (a finger touching down).
public struct ZTronScrollPhaseChangeContext {
    public let geometry: ZTronScrollGeometry
    public let velocity: CGVector?

    init(geometry: ZTronScrollGeometry, velocity: CGVector?) {
        self.geometry = geometry
        self.velocity = velocity
    }
}
