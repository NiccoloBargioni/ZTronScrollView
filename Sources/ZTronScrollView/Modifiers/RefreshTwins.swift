import SwiftUI

// `ztronRefresher` twins (SPEC S9, design M8b §1.2, S8 strategy 2b): the same declarations as the members of
// `ZTronScrollView`, carried by the environment so one call above a scroll view configures every `ZTronScrollView` below
// it. Inner calls come later in the list, so they replace the outer ones per edge. The environment value is cold; no
// hot value ever travels through it.

private struct RefreshSpecsKey: EnvironmentKey {
    static var defaultValue: [RefresherDecl] { [] }
}

private struct ReachEdgesKey: EnvironmentKey {
    static var defaultValue: [ReachEdgeDecl] { [] }
}

extension EnvironmentValues {
    /// The refreshers the `ztronRefresher` twins declared above this view, outermost first.
    var ztronRefreshSpecs: [RefresherDecl] {
        get { self[RefreshSpecsKey.self] }
        set { self[RefreshSpecsKey.self] = newValue }
    }

    /// The `onZTronScrollReachEdge` registrations declared above this view, outermost first.
    var ztronReachEdges: [ReachEdgeDecl] {
        get { self[ReachEdgesKey.self] }
        set { self[ReachEdgesKey.self] = newValue }
    }
}

/// One `onZTronScrollReachEdge` call as stored; the closure is refreshed in place on every evaluation.
struct ReachEdgeDecl {
    var edge: Edge
    var threshold: CGFloat
    var perform: () -> Void
}

extension View {
    private func declaring(_ decl: RefresherDecl) -> some View {
        transformEnvironment(\.ztronRefreshSpecs) { $0.append(decl) }
    }

    /// Environment twin of ``ZTronScrollView/refresher(style:overlay:configuration:action:)`` (async action). The member
    /// wins over the twin on the same edge; both win over SwiftUI's `.refreshable`.
    public func ztronRefresher(style: ZTronRefreshStyle = .default, overlay: Bool = false,
                               configuration: ZTronRefreshConfiguration = .default,
                               action: @escaping @MainActor () async -> Void) -> some View {
        declaring(.async(style: style, overlay: overlay, configuration: configuration, action: { _ in await action() }))
    }

    /// Twin of the completion-handler form: the refresh ends when `done` is called (idempotent, any thread).
    public func ztronRefresher(style: ZTronRefreshStyle = .default, overlay: Bool = false,
                               configuration: ZTronRefreshConfiguration = .default,
                               action: @escaping @MainActor (_ done: @escaping @Sendable () -> Void) -> Void) -> some View {
        declaring(.completion(style: style, overlay: overlay, configuration: configuration, action: action))
    }

    /// Twin with a custom indicator built from a binding to the refresh state.
    public func ztronRefresher<RefreshView: View>(@ViewBuilder refreshView: @escaping (Binding<ZTronRefreshState>) -> RefreshView,
                                                  overlay: Bool = false, configuration: ZTronRefreshConfiguration = .default,
                                                  action: @escaping @MainActor () async -> Void) -> some View {
        declaring(.async(style: .default, overlay: overlay, configuration: configuration,
                         indicator: { AnyView(refreshView($0)) }, action: { _ in await action() }))
    }

    /// Twin with a custom indicator and a completion-handler action.
    public func ztronRefresher<RefreshView: View>(@ViewBuilder refreshView: @escaping (Binding<ZTronRefreshState>) -> RefreshView,
                                                  overlay: Bool = false, configuration: ZTronRefreshConfiguration = .default,
                                                  action: @escaping @MainActor (_ done: @escaping @Sendable () -> Void) -> Void) -> some View {
        declaring(.completion(style: .default, overlay: overlay, configuration: configuration,
                              indicator: { AnyView(refreshView($0)) }, action: action))
    }

    /// Twin of the edge-aware form.
    public func ztronRefresher(edges: Edge.Set, style: ZTronRefreshStyle = .default, overlay: Bool = false,
                               configuration: ZTronRefreshConfiguration = .default,
                               action: @escaping @MainActor (Edge) async -> Void) -> some View {
        declaring(.async(edges: edges, style: style, overlay: overlay, configuration: configuration, action: action))
    }

    /// Calls `perform` once each time a `ZTronScrollView` below this view ARRIVES within `threshold` points of `edge`
    /// ("did reach bottom"): it re-arms only when the offset is more than 1 pt further away, so a bounce at the edge fires
    /// once, and a content append (which moves the end edge away) re-arms it. Evaluated when the scroll view flushes
    /// `didScroll` (at most once per frame) and on every layout change, never from a view body. Appears at the edge
    /// (short content, a list at the top) counts as an arrival.
    public func onZTronScrollReachEdge(_ edge: Edge, threshold: CGFloat = 0, perform: @escaping () -> Void) -> some View {
        transformEnvironment(\.ztronReachEdges) {
            $0.append(ReachEdgeDecl(edge: edge, threshold: threshold, perform: perform))
        }
    }
}
