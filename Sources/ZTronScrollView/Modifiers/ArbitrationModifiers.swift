import SwiftUI
import ScrollArbitration

/// One registration with the nearest `ScrollArbiter`: an enclosing ``ZTronScrollView``'s nested arbiter, or an external
/// one (ZTronPages'). Own it in your representable's model, hand it to ``SwiftUI/View/ztronScrollArbitrationParticipant(_:)``
/// on the representable, set ``participant`` from `makeUIView`, and ask ``owner(ofDragFrom:translation:touchCount:)`` from
/// the UIKit side.
///
/// The type is not observable: reading it in a view body does not subscribe the view, and neither setting ``participant``
/// nor a frame change re-evaluates anything. It is cold-path state, like the library's own participant.
@MainActor
public final class ZTronScrollArbitrationRegistration {
    /// The registration with the arbiter in the environment; nil while the modifier has found none.
    private(set) var registrar: ArbitrationRegistrar?

    public init() {}

    /// The object the arbiter consults (`canFollow`, `isMovingWithoutFinger`, `isZoomEnabled`). Held weakly. The
    /// registration happens once both this and an arbiter are present; clearing it unregisters.
    public weak var participant: (any ScrollArbitrationParticipant)? {
        didSet { registrar?.participant = participant }
    }

    /// Whether the arbiter currently holds this registration (the modifier has an arbiter, the view is on screen and a
    /// ``participant`` is set).
    public var isRegistered: Bool { registrar?.isRegistered ?? false }

    /// Once per touch sequence, at the UIKit pan's own slop (`gestureRecognizerShouldBegin`). `startLocation` is local to
    /// the registered view (touch-down: `location(in:) − translation(in:)`, minus `bounds.origin` for a UIScrollView).
    /// `.participant` with no arbiter, while unregistered, or while the container cannot take a swipe.
    public func owner(ofDragFrom startLocation: CGPoint, translation: CGSize, touchCount: Int) -> ScrollOwner {
        registrar?.owner(startLocation: startLocation, translation: translation, touchCount: touchCount) ?? .participant
    }

    /// Follows the environment's arbiter (called from the modifier's body, cheap unless the instance changed): a new
    /// instance unregisters from the old one and starts a registrar for the new one, which registers when its frame
    /// reader appears.
    func setArbiter(_ arbiter: (any ScrollArbiter)?) {
        if let arbiter {
            if registrar?.arbiter === arbiter { return }
            registrar?.unregister()
            let next = ArbitrationRegistrar(arbiter: arbiter)
            next.participant = participant
            registrar = next
        } else if let registrar {
            registrar.unregister()
            self.registrar = nil
        }
    }
}

extension View {
    /// Registers `registration` with the nearest arbiter using this view's frame in the arbiter's space; cold (appear,
    /// frame change, disappear). Apply it to the representable (or to the subtree whose frame is the scroller's).
    public func ztronScrollArbitrationParticipant(_ registration: ZTronScrollArbitrationRegistration) -> some View {
        modifier(ArbitrationParticipantModifier(registration: registration))
    }
}

/// Reads `@Environment(\.scrollArbiter)` and keeps `registration` pointed at it; the frame half is the library's own
/// `ParticipantFrameRegistration`.
private struct ArbitrationParticipantModifier: ViewModifier {
    let registration: ZTronScrollArbitrationRegistration
    @Environment(\.scrollArbiter) private var arbiter

    func body(content: Content) -> some View {
        registration.setArbiter(arbiter)
        return content.modifier(ParticipantFrameRegistration(registrar: registration.registrar))
    }
}
