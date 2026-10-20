import SwiftUI

// The refresher API (SPEC S9, design M8b §1.2): four members of `ZTronScrollView` + the edge-aware form, each returning
// `Self` and storing a declaration that the container's cold refresh host resolves (`RefreshResolver`). The
// `ztronRefresher` twins (Modifiers/RefreshTwins.swift) carry the same declarations in the environment.
//
// Mandatory shapes (user, 2026-10-19), all compiling exactly as spelled:
//   .refresher { await load() }                                   async action, `.default` style, built-in indicator
//   .refresher { done in … }                                      completion handler (overloads resolve by closure arity)
//   .refresher(refreshView: { MyLoader($0) }) { await load() }    custom indicator + action
// If both `.refreshable` and an explicit refresher are set, the explicit one wins (per edge).

/// One `refresher(…)` call as stored: the edges it names (`nil` = the configuration's `allowedEdges`, else the start edge
/// of the primary axis, decided by the container, which knows the axes) and what runs.
struct RefresherDecl {
    var edges: Edge.Set?
    var spec: RefresherSpec

    static func async(edges: Edge.Set? = nil, style: ZTronRefreshStyle, overlay: Bool, configuration: ZTronRefreshConfiguration,
                      indicator: ((Binding<ZTronRefreshState>) -> AnyView)? = nil,
                      action: @escaping @MainActor (Edge) async -> Void) -> RefresherDecl {
        RefresherDecl(edges: edges, spec: RefresherSpec(style: style, overlay: overlay, configuration: configuration,
                                                        action: action, indicator: indicator))
    }

    /// A completion-handler action: the refresh ends when `done` is called (idempotent, any thread).
    static func completion(style: ZTronRefreshStyle, overlay: Bool, configuration: ZTronRefreshConfiguration,
                           indicator: ((Binding<ZTronRefreshState>) -> AnyView)? = nil,
                           action: @escaping @MainActor (_ done: @escaping @Sendable () -> Void) -> Void) -> RefresherDecl {
        RefresherDecl(edges: nil, spec: RefresherSpec(style: style, overlay: overlay, configuration: configuration,
                                                      action: RefresherSpec.awaiting(action), indicator: indicator))
    }
}

extension ZTronScrollView {
    /// Pull to refresh with the built-in indicator. The refresh ends when the async `action` returns; the action runs once
    /// per pull and its `Task` is cancelled when the view disappears. The pull edge is the start edge of the primary axis
    /// (`.top`; `.leading` on a horizontal-only view) unless `configuration.allowedEdges` says otherwise
    /// (`.loadMore` = the bottom edge). Attaching a refresher makes its axis bounce even when the content fits.
    ///
    /// An explicit refresher wins over SwiftUI's `.refreshable` on the same edge, and a later `refresher` call replaces
    /// the edges it names.
    public func refresher(style: ZTronRefreshStyle = .default, overlay: Bool = false,
                          configuration: ZTronRefreshConfiguration = .default,
                          action: @escaping @MainActor () async -> Void) -> Self {
        adding(.async(style: style, overlay: overlay, configuration: configuration, action: { _ in await action() }))
    }

    /// The completion-handler form: the refresh ends when `done` is called. `done` is idempotent and safe to call from any
    /// thread; it hops to the main actor. If it is never called the refresh never ends (UIKit's `endRefreshing` parity).
    public func refresher(style: ZTronRefreshStyle = .default, overlay: Bool = false,
                          configuration: ZTronRefreshConfiguration = .default,
                          action: @escaping @MainActor (_ done: @escaping @Sendable () -> Void) -> Void) -> Self {
        adding(.completion(style: style, overlay: overlay, configuration: configuration, action: action))
    }

    /// A custom indicator built from a binding to the refresh state. Writing `.mode = .refreshing` / `.notRefreshing`
    /// through the binding begins / ends the refresh (no action is run, as `beginRefreshing()`); other writes are ignored.
    public func refresher<RefreshView: View>(@ViewBuilder refreshView: @escaping (Binding<ZTronRefreshState>) -> RefreshView,
                                             overlay: Bool = false, configuration: ZTronRefreshConfiguration = .default,
                                             action: @escaping @MainActor () async -> Void) -> Self {
        adding(.async(style: .default, overlay: overlay, configuration: configuration,
                      indicator: { AnyView(refreshView($0)) }, action: { _ in await action() }))
    }

    /// A custom indicator with a completion-handler action.
    public func refresher<RefreshView: View>(@ViewBuilder refreshView: @escaping (Binding<ZTronRefreshState>) -> RefreshView,
                                             overlay: Bool = false, configuration: ZTronRefreshConfiguration = .default,
                                             action: @escaping @MainActor (_ done: @escaping @Sendable () -> Void) -> Void) -> Self {
        adding(.completion(style: .default, overlay: overlay, configuration: configuration,
                           indicator: { AnyView(refreshView($0)) }, action: action))
    }

    /// The edge-aware form: one action for every edge in `edges` (the configuration's `allowedEdges` is ignored); the
    /// action learns which edge fired. An edge on an axis the view does not scroll is ignored.
    public func refresher(edges: Edge.Set, style: ZTronRefreshStyle = .default, overlay: Bool = false,
                          configuration: ZTronRefreshConfiguration = .default,
                          action: @escaping @MainActor (Edge) async -> Void) -> Self {
        adding(.async(edges: edges, style: style, overlay: overlay, configuration: configuration, action: action))
    }

    private func adding(_ decl: RefresherDecl) -> Self {
        var copy = self
        copy.config.refreshers.append(decl)
        return copy
    }
}
