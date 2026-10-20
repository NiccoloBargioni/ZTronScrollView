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

public extension ZTronScrollPhase {
    /// Native parity (`ScrollPhase.isScrolling`): anything but `.idle`.
    var isScrolling: Bool { self != .idle }
}

@available(iOS 18, *)
extension ZTronScrollPhase {
    /// The matching phase of SwiftUI's `ScrollPhase`.
    public init(_ native: ScrollPhase) {
        switch native {
        case .idle: self = .idle
        case .tracking: self = .tracking
        case .interacting: self = .interacting
        case .decelerating: self = .decelerating
        case .animating: self = .animating
        @unknown default: self = .idle
        }
    }

    /// SwiftUI's phase for this one.
    public var native: ScrollPhase {
        switch self {
        case .idle: return .idle
        case .tracking: return .tracking
        case .interacting: return .interacting
        case .decelerating: return .decelerating
        case .animating: return .animating
        }
    }
}

@available(iOS 18, *)
extension ZTronScrollPhaseChangeContext {
    /// A context from SwiftUI's (geometry without zoom, native velocity).
    @MainActor
    public init(_ native: ScrollPhaseChangeContext) {
        self.init(geometry: ZTronScrollGeometry(native.geometry), velocity: native.velocity)
    }
}
