import SwiftUI

/// How a programmatic scroll animates when the caller names it (design M6 §2): `.uikit` is `setContentOffset(_:animated:)`'s
/// curve on the state clock, `.swiftUI` runs through the transaction path (the effect interpolates the target), and
/// `nil` is unanimated. The overload without `animation:` honors the ambient `withAnimation`.
public enum ZTronScrollAnimation: Equatable {
    case uikit
    case swiftUI(Animation)
}

/// The `ZTronScrollView`s inside one ``ZTronScrollViewReader`` (and the readers nested in it). A scroll view joins the
/// nearest scope when it appears; the proxy searches own members first, then the nested scopes (outer to inner): the
/// first scroll view that registered the id wins. "First" is frame order (top, then leading) in the reader's space, which
/// is what SwiftUI's proxy does over two scroll views holding the same id (measured on 27.0 in the demo's twin section:
/// the upper one scrolls; `onAppear` itself fires in reverse tree order there). A member whose frame is not known yet
/// comes after the ones that have one, in appear order.
@MainActor
final class ProxyScope: ObservableObject, Equatable {
    private struct WeakScope { weak var scope: ProxyScope? }

    private(set) var members: [ZTronScrollState] = []
    private var children: [WeakScope] = []
    /// The coordinate space the reader declares on its content; its scroll views report their frames in it.
    let spaceName = "ztronReader.\(UUID().uuidString)"
    private var frames: [ObjectIdentifier: CGRect] = [:]

    func attach(_ state: ZTronScrollState) {
        guard !members.contains(where: { $0 === state }) else { return }
        members.append(state)
    }

    func detach(_ state: ZTronScrollState) {
        members.removeAll { $0 === state }
        frames.removeValue(forKey: ObjectIdentifier(state))
    }

    /// A scroll view's frame in ``spaceName`` (cold: on appear and when it changes).
    func report(_ state: ZTronScrollState, frame: CGRect) {
        frames[ObjectIdentifier(state)] = frame
    }

    /// The members in the order the proxy searches them.
    var ordered: [ZTronScrollState] {
        let tolerance: CGFloat = 1
        return members.enumerated().sorted { a, b in
            switch (frames[ObjectIdentifier(a.element)], frames[ObjectIdentifier(b.element)]) {
            case let (fa?, fb?):
                if abs(fa.minY - fb.minY) > tolerance { return fa.minY < fb.minY }
                if abs(fa.minX - fb.minX) > tolerance { return fa.minX < fb.minX }
                return a.offset < b.offset
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
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
        if let member = ordered.first(where: { $0.targets.frame(of: id) != nil }) { return member }
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
    /// Fixed at creation (R6): which coordinate-space API the reader's space uses.
    private let usesNamedSpace = ZTronAvailability.isAvailable(.namedCoordinateSpace)

    public init(@ViewBuilder content: @escaping (ZTronScrollViewProxy) -> Content) {
        self.content = content
    }

    public var body: some View {
        ScrollViewReader { native in
            content(ZTronScrollViewProxy(scope: scope, native: native))
        }
        .modifier(NamedSpaceModifier(name: scope.spaceName, useNew: usesNamedSpace))
        .environment(\.ztronProxyScope, scope)
        .onAppear { outer?.attach(child: scope) }
        .onDisappear { outer?.detach(child: scope) }
    }
}

/// Reports a scroll view's frame in its reader's space, so the proxy can search by position (cold: it fires on appear and
/// when the frame changes, never while the view scrolls). Lives in the container's background.
struct ProxyFrameReporter: View {
    let scope: ProxyScope
    let state: ZTronScrollState

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(scope.spaceName))
            Color.clear
                .onAppear { scope.report(state, frame: frame) }
                .onChangeCompat(of: frame) { scope.report(state, frame: $0) }
        }
    }
}
