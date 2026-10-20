import SwiftUI

// Observation modifiers (SPEC S8-2, design M7 §2). Each exists as a member of `ZTronScrollView` returning `Self` (binds to
// that view only) and as an `onZTronScroll…` `View` twin carried by the environment (binds to every `ZTronScrollView` below
// it and applies SwiftUI's own modifier on iOS 18, so one call site observes native and ZTron scroll views alike).
// Both write boxes the container registers with the state's `ObserverHub`: appended, never replaced, so nesting works.

/// What a member or a twin writes: a recipe for the box. Members are plain value calls in the parent's body and a twin
/// is carried down the environment, so the box itself lives in the receiving container's `ObserverStore` (one box per
/// container and `key`: a twin above two scroll views seeds each separately); `apply` re-assigns the closures on
/// every evaluation of the owner (R7: never stale) and fails when the box has another type.
@MainActor
struct ObserverDescriptor {
    /// Stable per modifier: a twin's `@State` token, a member's position.
    let key: AnyHashable
    let make: () -> ObserverBox
    let apply: (ObserverBox) -> Bool
}

/// The boxes of one container, by descriptor key across the parent's re-evaluations (cold, never observed).
@MainActor
final class ObserverStore: ObservableObject {
    private var boxes: [AnyHashable: ObserverBox] = [:]

    func boxes(for descriptors: [ObserverDescriptor]) -> [ObserverBox] {
        var next: [AnyHashable: ObserverBox] = [:]
        var ordered: [ObserverBox] = []
        for d in descriptors {
            let box: ObserverBox
            if let kept = boxes[d.key], d.apply(kept) { box = kept } else { box = d.make() }
            next[d.key] = box
            ordered.append(box)
        }
        boxes = next
        return ordered
    }
}

/// Identity of one twin modifier instance.
final class ObserverKey: Hashable {
    static func == (l: ObserverKey, r: ObserverKey) -> Bool { l === r }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

extension ObserverDescriptor {
    static func geometry<T: Equatable>(key: AnyHashable, transform: @escaping (ZTronScrollGeometry) -> T,
                                       action: @escaping (T, T) -> Void) -> ObserverDescriptor {
        ObserverDescriptor(
            key: key,
            make: { TypedGeometryBox<T>(transform: transform, action: action) },
            apply: { box in
                guard let typed = box as? TypedGeometryBox<T> else { return false }
                typed.transform = transform
                typed.action = action
                return true
            })
    }
}

/// Registers the container's boxes with the state on appear, whenever the box set changes, and removes them on disappear.
struct ObserverRegistration: ViewModifier {
    let state: ZTronScrollState
    let boxes: [ObserverBox]

    func body(content: Content) -> some View {
        content
            .onAppear { state.observers.sync(boxes) }
            .onChangeCompat(of: boxes.map(ObjectIdentifier.init)) { _ in state.observers.sync(boxes) }
            .onDisappear { state.observers.sync([]) }
    }
}

// MARK: Members (S8-2a)

extension ZTronScrollView {
    /// `onScrollGeometryChange(for:of:action:)` for this view on iOS 15+. `action(old, new)` runs when `transform` of the
    /// geometry changes, and once with `(v, v)` when the view first has a size. The unprefixed spelling binds only on the
    /// `ZTronScrollView` itself; use ``SwiftUI/View/onZTronScrollGeometryChange(for:of:action:)`` above it or around native
    /// scroll views.
    public func onScrollGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (ZTronScrollGeometry) -> T,
                                                     action: @escaping (T, T) -> Void) -> Self {
        var copy = self
        copy.config.observers.append(.geometry(key: "member.\(config.observers.count)", transform: transform, action: action))
        return copy
    }
}

// MARK: Twins (S8-2b)

extension View {
    /// Environment twin of ``ZTronScrollView/onScrollGeometryChange(for:of:action:)``: observes every `ZTronScrollView`
    /// below it. On iOS 18+ it also applies SwiftUI's `onScrollGeometryChange` (the transform sees the native geometry as a
    /// `ZTronScrollGeometry` with `zoomScale` 1), so a native `ScrollView` below is observed by the same call.
    public func onZTronScrollGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (ZTronScrollGeometry) -> T,
                                                          action: @escaping (T, T) -> Void) -> some View {
        modifier(GeometryObserverModifier(transform: transform, action: action))
    }
}

struct GeometryObserverModifier<T: Equatable>: ViewModifier {
    let transform: (ZTronScrollGeometry) -> T
    let action: (T, T) -> Void
    @State private var key = ObserverKey()

    @ViewBuilder
    func body(content: Content) -> some View {
        let descriptor = ObserverDescriptor.geometry(key: key, transform: transform, action: action)
        let overlaid = content.transformEnvironment(\.ztronScrollConfig) { $0.observers.append(descriptor) }
        if #available(iOS 18, *) {
            overlaid.onScrollGeometryChange(for: T.self, of: nativeTransform, action: action)
        } else {
            overlaid
        }
    }

    @available(iOS 18, *)
    private var nativeTransform: @Sendable (ScrollGeometry) -> T {
        let boxed = UncheckedTransform(transform)
        return { native in boxed.run(native) }
    }
}

/// Carries a main-actor transform into SwiftUI's `@Sendable` native callback (SwiftUI calls it on the main thread).
private final class UncheckedTransform<T>: @unchecked Sendable {
    let transform: (ZTronScrollGeometry) -> T
    private var result: T?
    init(_ transform: @escaping (ZTronScrollGeometry) -> T) { self.transform = transform }

    @available(iOS 18, *)
    func run(_ native: ScrollGeometry) -> T {
        MainActor.assumeIsolated { result = transform(ZTronScrollGeometry(native)) }
        return result!
    }
}
