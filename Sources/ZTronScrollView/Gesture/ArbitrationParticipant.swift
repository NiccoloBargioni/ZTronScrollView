import SwiftUI
import ScrollArbitration

/// The viewport as a `ScrollArbitrationParticipant` (design M3-pan §7, SPEC S12 "Inside a pager", S16).
/// Answers come from cold reads of the state through the coordinator; the arbiter calls them only from inside
/// its own calls (`owner`), never per scroll frame. Registration, frame updates and unregistration are cold-path.
@MainActor
final class ArbitrationParticipant: ScrollArbitrationParticipant {
    /// The registration half (token, frame, ownership question): shared with the public registration type.
    let registrar: ArbitrationRegistrar
    private weak var coordinator: PanCoordinator?

    init(arbiter: any ScrollArbiter, coordinator: PanCoordinator) {
        registrar = ArbitrationRegistrar(arbiter: arbiter)
        self.coordinator = coordinator
        registrar.participant = self
    }

    var arbiter: any ScrollArbiter { registrar.arbiter }
    var token: ScrollArbitrationToken? { registrar.token }
    var frame: CGRect { registrar.frame }
    var isRegistered: Bool { registrar.isRegistered }

    /// On appear. `frame` is in `.named(arbiter.coordinateSpaceName)`. A second call acts as `update`.
    func register(frame: CGRect) { registrar.register(frame: frame) }

    /// On frame change (cold). Ignored while unregistered.
    func update(frame: CGRect) { registrar.update(frame: frame) }

    /// On disappear.
    func unregister() { registrar.unregister() }

    /// Rule 5's answer, through the view's `ZTronNestedScrollPolicy` (NESTED §3): `.innerWhileScrollable` is the
    /// bounds test, `.innerWhenZoomed` is `zoomScale > minimumZoomScale + ε`, `.inner` / `.outer` are constant and
    /// `.custom` asks the closure with a non-tracked context. Rules 1–4 are the arbiter's and are not affected.
    func canFollow(_ direction: FingerDirection) -> Bool {
        guard let c = coordinator else { return false }
        let env = c.environment()
        let scrollable = Self.canScroll(direction, env: env)
        switch c.nestedPolicy.kind {
        case .innerWhileScrollable, .independent:
            return scrollable
        case .innerWhenZoomed:
            return env.isScrollEnabled && c.state.peek.presentationZoom > c.state.minimumZoomScale + Self.zoomEpsilon
        case .inner:
            return true
        case .outer:
            return false
        case let .custom(decide):
            let context = ZTronNestedScrollContext(geometry: c.state.peekGeometry(),
                                                   minimumZoomScale: c.state.minimumZoomScale,
                                                   fingerDirection: direction, canFollow: scrollable)
            return decide(context) == .inner
        }
    }

    /// `.innerWhenZoomed`: how far above the minimum scale counts as zoomed (a settled zoom-out lands within this).
    static let zoomEpsilon: CGFloat = 0.001

    /// Screen direction of the finger -> axis and sign. Finger right/down moves the content toward a lower offset.
    /// `true` only if the content can move with the finger without rubber-banding (0.5 pt edge slop).
    static func canScroll(_ direction: FingerDirection, env: PanEnvironment) -> Bool {
        guard env.isScrollEnabled else { return false }
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

    /// Mirrors the resolved zoom range (rule 2: a pinch on a zoomable view never pages).
    var isZoomEnabled: Bool { coordinator?.state.isZoomEnabled ?? false }

    /// `startLocation` is local to the viewport. Not registered yet: we own the swipe.
    func owner(startLocation: CGPoint, translation: CGSize, touchCount: Int) -> ScrollOwner {
        registrar.owner(startLocation: startLocation, translation: translation, touchCount: touchCount)
    }
}

/// Keeps the viewport's participant registered with the arbiter in the environment (frame in the arbiter's space, cold:
/// see `ParticipantFrameRegistration`). Lives in a background, so it never touches the content body.
struct ArbitrationRegistration: ViewModifier {
    @ObservedObject var coordinator: PanCoordinator
    /// `ZTronScrollView.nestedScrollPolicy(_:)`; nil falls back to the environment twin.
    var policy: ZTronNestedScrollPolicy?
    @Environment(\.scrollArbiter) private var arbiter
    @Environment(\.ztronNestedScrollPolicy) private var envPolicy

    func body(content: Content) -> some View {
        let policy = policy ?? envPolicy
        coordinator.setArbiter(arbiter, policy: policy)
        // The coordinator has a participant exactly when there is an arbiter this view joins (`policy.joins`).
        return content.modifier(ParticipantFrameRegistration(registrar: coordinator.participant?.registrar))
    }
}
