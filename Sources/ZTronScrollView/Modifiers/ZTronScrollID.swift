import SwiftUI

extension View {
    /// `id(_:)` that also registers the view as a scroll target of the enclosing ``ZTronScrollView`` (SPEC S8: SwiftUI's
    /// explicit ids are not publicly observable). The registered frame lives in the unscaled content space, is written
    /// only when layout changes it, never while the view scrolls or zooms, and is removed when the view disappears.
    /// Outside a `ZTronScrollView` (or inside a SwiftUI `ScrollView`) this is the plain `id(_:)`, which SwiftUI's own
    /// `ScrollViewProxy` understands.
    public func ztronScrollID<ID: Hashable>(_ id: ID) -> some View {
        modifier(ScrollIDModifier(id: id))
    }
}

struct ScrollIDModifier<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.ztronTargetRegistry) private var registry

    @ViewBuilder
    func body(content: Content) -> some View {
        if let registry {
            // The reporter sits inside `id(_:)`: a new id is a new identity, so the old id unregisters on its own.
            content.modifier(ScrollFrameReporter(id: AnyHashable(id), registry: registry)).id(id)
        } else {
            content.id(id)
        }
    }
}

private struct ScrollFrameKey: PreferenceKey {
    /// `.null` (not finite): the value a removed view's preference resets to is not a frame and registers nothing.
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Reports the view's frame in the content space to the registry (`onGeometryChange` where available, a background
/// `GeometryReader` with a preference on the fallback path). The branch is a `let` flag of the registry (R6).
struct ScrollFrameReporter: ViewModifier {
    let id: AnyHashable
    let registry: TargetRegistry
    @State private var token = ReporterToken()

    @ViewBuilder
    func body(content: Content) -> some View {
        if registry.usesGeometryChange, #available(iOS 16, *) {
            content
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: ZTronCoordinateSpaces.content) },
                                  action: { registry.register(id, frame: $0, owner: token) })
                .onAppear { token.isActive = true; registry.restore(id, owner: token) }
                .onDisappear { token.isActive = false; registry.unregister(id, owner: token) }
        } else {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScrollFrameKey.self, value: proxy.frame(in: ZTronCoordinateSpaces.content))
                    }
                    .onPreferenceChange(ScrollFrameKey.self) { registry.register(id, frame: $0, owner: token) }
                )
                .onAppear { token.isActive = true; registry.restore(id, owner: token) }
                .onDisappear { token.isActive = false; registry.unregister(id, owner: token) }
        }
    }
}
