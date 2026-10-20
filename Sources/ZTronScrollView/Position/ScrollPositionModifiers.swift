import SwiftUI

// `scrollPosition` as a member of `ZTronScrollView` and as a `View` twin (SPEC S8-2, design M6 §2). The twin writes the
// environment overlay and, where SwiftUI has the modifier (`scrollPosition(id:)` 17+, `scrollPosition(_:)` 18+), applies it
// too. The bindings are read by the container's body (so a new value re-evaluates the container only) and written back by
// `PositionDriver` at the release target and at settle.

extension ZTronScrollView {
    /// `scrollPosition(_:anchor:)` for this view on iOS 15+: scrolls when you set the position and writes it back after the
    /// user scrolls. The unprefixed spelling binds only on the `ZTronScrollView` itself; use ``SwiftUI/View/ztronScrollPosition(_:anchor:)``
    /// above it or around native scroll views.
    public func scrollPosition(_ position: Binding<ZTronScrollPosition>, anchor: UnitPoint? = nil) -> Self {
        var copy = self
        copy.config.position = PositionBinding(position, anchor: anchor)
        return copy
    }

    /// `scrollPosition(id:anchor:)` for this view on iOS 15+: `id` follows the `ztronScrollID` view under the anchor
    /// (top-leading by default) and scrolls to a view you assign (animated inside `withAnimation`).
    public func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> Self {
        var copy = self
        copy.config.position = PositionBinding(id: id, anchor: anchor)
        return copy
    }
}

extension View {
    /// Environment twin of ``ZTronScrollView/scrollPosition(_:anchor:)`` (the member wins). On iOS 18+ it also applies
    /// SwiftUI's `scrollPosition(_:anchor:)` through a bridged binding, so a native `ScrollView` below follows the same value.
    @ViewBuilder
    public func ztronScrollPosition(_ position: Binding<ZTronScrollPosition>, anchor: UnitPoint? = nil) -> some View {
        let overlaid = transformEnvironment(\.ztronScrollConfig) { $0.position = PositionBinding(position, anchor: anchor) }
        if #available(iOS 18, *) {
            overlaid.modifier(NativePositionBridge(position: position, anchor: anchor))
        } else {
            overlaid
        }
    }

    /// Environment twin of ``ZTronScrollView/scrollPosition(id:anchor:)``; on iOS 17+ it also applies SwiftUI's own.
    @ViewBuilder
    public func ztronScrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> some View {
        let overlaid = transformEnvironment(\.ztronScrollConfig) { $0.position = PositionBinding(id: id, anchor: anchor) }
        if #available(iOS 17, *) {
            overlaid.scrollPosition(id: id, anchor: anchor)
        } else {
            overlaid
        }
    }
}

/// Applies SwiftUI's `scrollPosition(_:anchor:)` to a binding of ours. SwiftUI re-reads the binding on every update, so the
/// converted value is cached per ours-value (a fresh `ScrollPosition` each read would restart the scroll); a value SwiftUI
/// writes comes back as ours with `isPositionedByUser` taken from SwiftUI's.
@available(iOS 18, *)
private struct NativePositionBridge: ViewModifier {
    let position: Binding<ZTronScrollPosition>
    let anchor: UnitPoint?
    @State private var cache = Cache()

    /// `native` is type-erased: a stored `ScrollPosition` would make the class's metadata need an iOS 18 type, and the
    /// runtime realizes every class at load, which crashes before iOS 18.
    final class Cache {
        var ours: ZTronScrollPosition?
        var native: Any?
    }

    func body(content: Content) -> some View {
        let cache = cache
        let binding = Binding<ScrollPosition>(
            get: {
                let current = position.wrappedValue
                if cache.ours != current || cache.native == nil {
                    cache.ours = current
                    cache.native = current.native
                }
                return (cache.native as? ScrollPosition) ?? current.native
            },
            set: { new in
                cache.native = new
                let converted = ZTronScrollPosition(new, serial: position.wrappedValue.serial)
                cache.ours = converted
                position.wrappedValue = converted
            })
        return content.scrollPosition(binding, anchor: anchor)
    }
}
