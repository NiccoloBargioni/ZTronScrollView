import SwiftUI

// Scroll-view-level modifiers whose state SwiftUI keeps private (SPEC S8-2, design M6 §1): each exists as a member of
// `ZTronScrollView` returning `Self` (binds to that view only) and as a `ztronScroll`-prefixed `View` twin carried by the
// environment (binds to every `ZTronScrollView` below it, and applies SwiftUI's own modifier where it exists, so one call
// site configures native and ZTron scroll views alike). Resolution inside the container: member, else environment, else default.

/// The settings the members and the twins carry. M6 session 1 holds the target behavior; position and anchors follow.
struct ScrollViewConfig {
    var behavior: AnyZTronScrollTargetBehavior?
    /// Observer recipes (M7): the member's calls, or on the environment the `onZTronScroll…` twins' (appended, outermost
    /// first). The container builds one box per recipe (`ObserverStore`).
    var observers: [ObserverDescriptor] = []
    /// `scrollPosition` (M6 s3) and the `defaultScrollAnchor` roles; an anchor that is absent is the role's default.
    var position: PositionBinding?
    var anchors: [ZTronScrollAnchorRole: UnitPoint] = [:]
}

private struct ScrollConfigKey: EnvironmentKey {
    static var defaultValue: ScrollViewConfig { ScrollViewConfig() }
}

extension EnvironmentValues {
    var ztronScrollConfig: ScrollViewConfig {
        get { self[ScrollConfigKey.self] }
        set { self[ScrollConfigKey.self] = newValue }
    }
}

// MARK: Members (S8-2a)

extension ZTronScrollView {
    /// `scrollTargetBehavior(_:)` for this view on iOS 15+: decides where a release lands (`.paging`, a custom
    /// behavior). An explicit behavior wins over `isPagingEnabled`. The unprefixed spelling binds only on the
    /// `ZTronScrollView` itself; use ``SwiftUI/View/ztronScrollTargetBehavior(_:)`` above it or around native scroll views.
    public func scrollTargetBehavior(_ behavior: some ZTronScrollTargetBehavior) -> Self {
        var copy = self
        copy.config.behavior = AnyZTronScrollTargetBehavior(behavior)
        return copy
    }
}

// MARK: Twins (S8-2b)

extension View {
    /// Environment twin of ``ZTronScrollView/scrollTargetBehavior(_:)`` (the member wins when both are set). On iOS 17+
    /// it also applies SwiftUI's `scrollTargetBehavior(_:)` (`.paging` as SwiftUI's own, a custom behavior bridged), so a
    /// native `ScrollView` below follows the same behavior.
    @ViewBuilder
    public func ztronScrollTargetBehavior(_ behavior: some ZTronScrollTargetBehavior) -> some View {
        let erased = AnyZTronScrollTargetBehavior(behavior)
        let overlaid = transformEnvironment(\.ztronScrollConfig) { $0.behavior = erased }
        if #available(iOS 17, *) {
            overlaid.applyingNativeScrollTargetBehavior(erased)
        } else {
            overlaid
        }
    }
}

/// A ZTron behavior running inside a SwiftUI `ScrollView` (iOS 17+), through the twin. SwiftUI's context is not
/// constructible, so the reverse (a native behavior inside a `ZTronScrollView`) is impossible; the context a bridged
/// behavior sees carries SwiftUI's public values and derives the library-internal extras (`ZTronScrollTargetBehaviorContext.init(_:)`).
@available(iOS 17, *)
public struct ZTronBridgedScrollTargetBehavior: ScrollTargetBehavior, @unchecked Sendable {
    let base: AnyZTronScrollTargetBehavior

    public init(_ base: some ZTronScrollTargetBehavior) {
        self.base = AnyZTronScrollTargetBehavior(base)
    }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        // SwiftUI calls this on the main thread; the behavior's requirements are main-actor isolated.
        let ours = UncheckedBox(ZTronScrollTarget(target))
        let ourContext = UncheckedBox(ZTronScrollTargetBehaviorContext(context))
        MainActor.assumeIsolated { base.updateTarget(&ours.value, context: ourContext.value) }
        ours.value.write(to: &target)
    }

    @available(iOS 18.4, *)
    public func properties(context: PropertiesContext) -> Properties {
        let ourContext = UncheckedBox(ZTronScrollTargetBehaviorPropertiesContext(
            axes: context.axes, contentSize: .zero, containerSize: .zero, environment: context.environment))
        let ours = MainActor.assumeIsolated { base.properties(context: ourContext.value) }
        var native = ScrollTargetBehaviorProperties()
        native.limitsScrolls = ours.limitsVelocity
        return native
    }
}

/// Carries a non-`Sendable` value into `MainActor.assumeIsolated` from SwiftUI's nonisolated callbacks.
private final class UncheckedBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

// MARK: Container plumbing

/// Holds the container's captured environment for the state (see `ZTronScrollState.targetEnvironment`).
@MainActor
final class TargetEnvironmentBox {
    var values = EnvironmentValues()
}

/// 0x0 leaf in the container's background: copies the container's environment into the box it owns (cold) so a
/// behavior's context can read `context.horizontalSizeClass`. Only this leaf depends on the whole environment (R3);
/// content bodies are not touched by it.
struct TargetEnvironmentCapture: View {
    let state: ZTronScrollState
    @Environment(\.self) private var environment
    @State private var box = TargetEnvironmentBox()

    var body: some View {
        box.values = environment
        state.adoptEnvironment(box)
        return Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
    }
}
