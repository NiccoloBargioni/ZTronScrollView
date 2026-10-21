import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

@MainActor
private final class DisabledModel: ObservableObject { @Published var disabled: Bool; init(_ d: Bool) { disabled = d } }

/// The bridge from SwiftUI's `scrollDisabled(_:)` to the pan (DBG-s3): `NativeEnabledBridge` must deliver `\.isScrollEnabled`
/// to `PanCoordinator.nativeScrollEnabled`. Its reader used to be a `ViewModifier` returning its content, whose body never ran,
/// so `scrollDisabled` did nothing to a `ZTronScrollView`; the existing tests only set the property by hand.
@MainActor
@Suite(.serialized)
struct NativeScrollEnabledTests {
    @available(iOS 16, *)
    private struct Rig: View {
        @ObservedObject var model: DisabledModel
        let coordinator: PanCoordinator
        var body: some View {
            Color.red.frame(width: 50, height: 50)
                .modifier(NativeEnabledBridge(coordinator: coordinator))
                .scrollDisabled(model.disabled)
        }
    }

    private func coordinator() -> PanCoordinator { PanCoordinator(state: ZTronScrollState(), axes: .vertical) }

    @Test func scrollDisabledReachesTheCoordinator() {
        guard #available(iOS 16, *) else { return }
        let c = coordinator()
        let model = DisabledModel(true)
        let w = host(Rig(model: model, coordinator: c))
        #expect(!c.nativeScrollEnabled, "disabled from the first evaluation")
        model.disabled = false; pump(0.15)
        #expect(c.nativeScrollEnabled, "enabled when the modifier flips")
        model.disabled = true; pump(0.15)
        #expect(!c.nativeScrollEnabled, "disabled again")
        _ = w
    }

    /// Without the modifier the pan stays enabled, and an environment value written above the view (a parent) counts too.
    @Test func parentScrollDisabledCountsAndDefaultIsEnabled() {
        guard #available(iOS 16, *) else { return }
        let plain = coordinator(), parent = coordinator()
        let w1 = host(Color.red.modifier(NativeEnabledBridge(coordinator: plain)))
        let w2 = host(VStack { Color.red.modifier(NativeEnabledBridge(coordinator: parent)) }.scrollDisabled(true))
        #expect(plain.nativeScrollEnabled)
        #expect(!parent.nativeScrollEnabled)
        _ = (w1, w2)
    }

    /// The pan's gate: the environment a drag is handled against reads the native flag per event.
    @Test func theGateReadsTheNativeFlag() {
        let c = coordinator()
        #expect(c.peekEnvironment().isScrollEnabled)
        c.nativeScrollEnabled = false
        #expect(!c.peekEnvironment().isScrollEnabled)
        c.nativeScrollEnabled = true
        #expect(c.peekEnvironment().isScrollEnabled)
    }
}
