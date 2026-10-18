import SwiftUI
import ScrollArbitration

/// The viewport as a `ScrollArbitrationParticipant` (design M3-pan §7, SPEC S12 "Inside a pager", S16).
/// Answers come from cold reads of the state through the coordinator; the arbiter calls them only from inside
/// its own calls (`owner`), never per scroll frame. Registration, frame updates and unregistration are cold-path.
@MainActor
final class ArbitrationParticipant: ScrollArbitrationParticipant {
    let arbiter: any ScrollArbiter
    private weak var coordinator: PanCoordinator?
    private(set) var token: ScrollArbitrationToken?
    private(set) var frame: CGRect = .zero

    init(arbiter: any ScrollArbiter, coordinator: PanCoordinator) {
        self.arbiter = arbiter
        self.coordinator = coordinator
    }

    var isRegistered: Bool { token != nil }

    /// On appear. `frame` is in `.named(arbiter.coordinateSpaceName)`. A second call acts as `update`.
    func register(frame: CGRect) {
        self.frame = frame
        if let token { arbiter.update(token, frame: frame) } else { token = arbiter.register(self, frame: frame) }
    }

    /// On frame change (cold). Ignored while unregistered.
    func update(frame: CGRect) {
        guard let token, frame != self.frame else { return }
        self.frame = frame
        arbiter.update(token, frame: frame)
    }

    /// On disappear.
    func unregister() {
        guard let token else { return }
        arbiter.unregister(token)
        self.token = nil
    }

    /// Screen direction of the finger -> axis and sign. Finger right/down moves the content toward a lower offset.
    func canFollow(_ direction: FingerDirection) -> Bool {
        guard let env = coordinator?.environment(), env.isScrollEnabled else { return false }
        let slop: CGFloat = 0.5
        switch direction {
        case .right: return env.axes.contains(.horizontal) && env.boundsX.isScrollable
            && env.presentationOffset.x > env.boundsX.min + slop
        case .left: return env.axes.contains(.horizontal) && env.boundsX.isScrollable
            && env.presentationOffset.x < env.boundsX.max - slop
        case .down: return env.axes.contains(.vertical) && env.boundsY.isScrollable
            && env.presentationOffset.y > env.boundsY.min + slop
        case .up: return env.axes.contains(.vertical) && env.boundsY.isScrollable
            && env.presentationOffset.y < env.boundsY.max - slop
        }
    }

    /// Motion without a finger, sticky from the catch until the owner decision or the end of the sequence.
    var isMovingWithoutFinger: Bool {
        guard let c = coordinator else { return false }
        return c.environment().isMovingWithoutFinger || c.caughtUndecided
    }

    /// The zoom range arrives in M4.
    var isZoomEnabled: Bool { false }

    /// `startLocation` is local to the viewport. Not registered yet: we own the swipe.
    func owner(startLocation: CGPoint, translation: CGSize, touchCount: Int) -> ScrollOwner {
        guard let token else { return .participant }
        let start = CGPoint(x: frame.minX + startLocation.x, y: frame.minY + startLocation.y)
        return arbiter.owner(ofDragFrom: start, translation: translation, touchCount: touchCount, participant: token)
    }
}

/// Reads the viewport frame in the arbiter's space and keeps the participant registered (cold: only when the frame
/// changes). Lives in a background, so it never touches the content body.
struct ArbitrationRegistration: ViewModifier {
    @ObservedObject var coordinator: PanCoordinator
    @Environment(\.scrollArbiter) private var arbiter

    func body(content: Content) -> some View {
        coordinator.setArbiter(arbiter)
        return content.background(
            Group {
                if let arbiter {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(arbiter.coordinateSpaceName))
                        Color.clear
                            .onAppear { coordinator.participant?.register(frame: frame) }
                            .onChange(of: frame) { coordinator.participant?.update(frame: $0) }
                            .onDisappear { coordinator.participant?.unregister() }
                    }
                }
            })
    }
}
