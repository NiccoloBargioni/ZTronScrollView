import SwiftUI
import ScrollArbitration

/// The registration half of a `ScrollArbitrationParticipant` (docs/design/NESTED-mixed.md §1): one registration of one
/// object with one `ScrollArbiter`, its frame in the arbiter's space and the ownership question. Shared by the viewport's
/// own `ArbitrationParticipant` and by the public `ZTronScrollArbitrationRegistration` (any object the caller supplies).
/// Registration, frame updates and unregistration are cold-path calls (appear, frame change, disappear).
///
/// The view is *placed* between `register(frame:)` and `unregister()`. The registration with the arbiter exists while the
/// view is placed **and** a `participant` is set, so the two can arrive in either order and the object can be swapped or
/// cleared (clearing unregisters; the next object registers with the last frame).
@MainActor
final class ArbitrationRegistrar {
    private static var nextSerial = 0
    /// Identity of this registrar: the frame reader is keyed by it, so a new arbiter (a new registrar) reads its frame afresh.
    let serial: Int
    let arbiter: any ScrollArbiter
    private(set) var token: ScrollArbitrationToken?
    private(set) var frame: CGRect = .zero
    /// The object the arbiter consults. Held weakly, as the arbiter does.
    weak var participant: (any ScrollArbitrationParticipant)? {
        didSet { if participant !== oldValue { sync() } }
    }
    private weak var registeredParticipant: (any ScrollArbitrationParticipant)?
    private var isPlaced = false

    init(arbiter: any ScrollArbiter) {
        Self.nextSerial += 1
        serial = Self.nextSerial
        self.arbiter = arbiter
    }

    var isRegistered: Bool { token != nil && participant != nil }

    /// On appear. `frame` is in `.named(arbiter.coordinateSpaceName)`. A second call acts as `update`.
    func register(frame: CGRect) {
        self.frame = frame
        isPlaced = true
        if let token { arbiter.update(token, frame: frame) } else { sync() }
    }

    /// On frame change (cold). Ignored while the view is not placed; remembered while no participant is set.
    func update(frame: CGRect) {
        guard isPlaced, frame != self.frame else { return }
        self.frame = frame
        if let token { arbiter.update(token, frame: frame) }
    }

    /// On disappear.
    func unregister() {
        isPlaced = false
        sync()
    }

    /// `startLocation` is local to the registered view. Not registered yet: the participant owns the swipe.
    func owner(startLocation: CGPoint, translation: CGSize, touchCount: Int) -> ScrollOwner {
        guard let token else { return .participant }
        let start = CGPoint(x: frame.minX + startLocation.x, y: frame.minY + startLocation.y)
        return arbiter.owner(ofDragFrom: start, translation: translation, touchCount: touchCount, participant: token)
    }

    /// The participant's own touch sequence ended. Closes a sequence a nested container began at this participant's ask
    /// (what `PanCoordinator` does for the viewport); kept for a registration whose pan the container never sees.
    func registrationSequenceEnded() {
        (arbiter as? NestedScrollArbiter)?.participantSequenceEnded()
    }

    /// Brings the arbiter's registration in line with (placed, participant): register, re-register for another object,
    /// or unregister.
    private func sync() {
        let wanted = isPlaced ? participant : nil
        if let token, wanted == nil || registeredParticipant !== wanted {
            arbiter.unregister(token)
            self.token = nil
            registeredParticipant = nil
        }
        if token == nil, let wanted {
            token = arbiter.register(wanted, frame: frame)
            registeredParticipant = wanted
        }
    }
}

/// Reads the view's frame in the arbiter's space and keeps `registrar` registered (cold: only when the frame changes).
/// Lives in a background, so it never touches the content body. The reader is keyed by the registrar, so a new
/// arbiter (a new registrar) appears afresh and registers with a frame in its own space.
struct ParticipantFrameRegistration: ViewModifier {
    let registrar: ArbitrationRegistrar?

    func body(content: Content) -> some View {
        content.background(
            Group {
                if let registrar {
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(registrar.arbiter.coordinateSpaceName))
                        Color.clear
                            .onAppear { registrar.register(frame: frame) }
                            .onChange(of: frame) { registrar.update(frame: $0) }
                            .onDisappear { registrar.unregister() }
                    }
                    .id(registrar.serial)
                }
            })
    }
}
