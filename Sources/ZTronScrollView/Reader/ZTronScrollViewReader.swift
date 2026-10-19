import SwiftUI

/// How a programmatic scroll animates when the caller names it (design M6 §2): `.uikit` is `setContentOffset(_:animated:)`'s
/// curve on the state clock, `.swiftUI` runs through the transaction path (the effect interpolates the target), and
/// `nil` is unanimated. The overload without `animation:` honors the ambient `withAnimation`.
public enum ZTronScrollAnimation: Equatable {
    case uikit
    case swiftUI(Animation)
}

/// The `ZTronScrollView`s inside one ``ZTronScrollViewReader`` (and the readers nested in it). A scroll view joins the
/// nearest scope when it appears; the proxy searches own members first, in appear order, then the nested scopes
/// (outer to inner): the first scroll view that registered the id wins, like SwiftUI's proxy.
@MainActor
final class ProxyScope: ObservableObject, Equatable {
    private struct WeakScope { weak var scope: ProxyScope? }

    private(set) var members: [ZTronScrollState] = []
    private var children: [WeakScope] = []

    func attach(_ state: ZTronScrollState) {
        guard !members.contains(where: { $0 === state }) else { return }
        members.append(state)
    }

    func detach(_ state: ZTronScrollState) {
        members.removeAll { $0 === state }
    }

    func attach(child: ProxyScope) {
        children.removeAll { $0.scope == nil }
        guard !children.contains(where: { $0.scope === child }) else { return }
        children.append(WeakScope(scope: child))
    }

    func detach(child: ProxyScope) {
        children.removeAll { $0.scope == nil || $0.scope === child }
    }

    /// The first scroll view, own members before nested scopes, whose registry holds `id`.
    func owner(of id: AnyHashable) -> ZTronScrollState? {
        if let member = members.first(where: { $0.targets.frame(of: id) != nil }) { return member }
        for child in children {
            if let found = child.scope?.owner(of: id) { return found }
        }
        return nil
    }

    nonisolated static func == (l: ProxyScope, r: ProxyScope) -> Bool { l === r }
}

private struct ProxyScopeKey: EnvironmentKey {
    static var defaultValue: ProxyScope? { nil }
}

extension EnvironmentValues {
    var ztronProxyScope: ProxyScope? {
        get { self[ProxyScopeKey.self] }
        set { self[ProxyScopeKey.self] = newValue }
    }
}

/// `ScrollViewProxy` for ``ZTronScrollView``: `scrollTo(_:anchor:)` scrolls the first `ZTronScrollView` inside the reader
/// that holds a `ztronScrollID(_:)` with that id; ids it does not know go to the SwiftUI `ScrollView`s inside the reader
/// (an internal `ScrollViewReader`). Zoom is never changed.
@MainActor
public struct ZTronScrollViewProxy {
    let scope: ProxyScope
    let native: ScrollViewProxy?

    /// Identical to `ScrollViewProxy.scrollTo(_:anchor:)`: animated iff called inside `withAnimation`. A `nil` anchor
    /// scrolls the minimum that makes the target visible.
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        perform(id, anchor: anchor, animation: nil, ambient: true)
    }

    /// Names the animation instead of reading the ambient transaction; `nil` is unanimated.
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint?, animation: ZTronScrollAnimation?) {
        perform(id, anchor: anchor, animation: animation, ambient: false)
    }

    private func perform<ID: Hashable>(_ id: ID, anchor: UnitPoint?, animation: ZTronScrollAnimation?, ambient: Bool) {
        if let owner = scope.owner(of: AnyHashable(id)) {
            owner.scrollTo(id: AnyHashable(id), anchor: anchor, animation: animation, ambient: ambient)
            return
        }
        #if DEBUG
        ZTronRenderCounters.increment("proxy.native")
        #endif
        guard let native else { return }
        if ambient {
            native.scrollTo(id, anchor: anchor)
        } else if let animation {
            switch animation {
            case .uikit: withAnimation(.easeInOut(duration: 0.3)) { native.scrollTo(id, anchor: anchor) }
            case let .swiftUI(a): withAnimation(a) { native.scrollTo(id, anchor: anchor) }
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { native.scrollTo(id, anchor: anchor) }
        }
    }
}

/// `ScrollViewReader` for ``ZTronScrollView`` (and the SwiftUI `ScrollView`s inside it). The content builder re-runs
/// only with its owner; scrolling re-evaluates nothing.
public struct ZTronScrollViewReader<Content: View>: View {
    private let content: (ZTronScrollViewProxy) -> Content
    @StateObject private var scope = ProxyScope()
    @Environment(\.ztronProxyScope) private var outer

    public init(@ViewBuilder content: @escaping (ZTronScrollViewProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        ScrollViewReader { native in
            content(ZTronScrollViewProxy(scope: scope, native: native))
        }
        .environment(\.ztronProxyScope, scope)
        .onAppear { outer?.attach(child: scope) }
        .onDisappear { outer?.detach(child: scope) }
    }
}
