import SwiftUI

/// Which refresher answers each edge (SPEC S9, design M8b §1.2). Pure and cold: the container's refresh host runs it in
/// its body and hands the result to the coordinator.
///
/// Per edge: the member's `refresher(…)` ?? the `ztronRefresher` twin ?? SwiftUI's `.refreshable` (style `.system`, the
/// start edge of the primary axis, the default configuration) ?? none. Inside one layer a later call replaces the edges
/// it names (a dictionary merge, never an accumulation).
enum RefreshResolver {
    static func resolve(member: [RefresherDecl], twin: [RefresherDecl], refreshable: (@MainActor () async -> Void)?,
                        axes: Axis.Set) -> [Edge: RefresherSpec] {
        var result: [Edge: RefresherSpec] = [:]
        if let refreshable {
            result[startEdge(axes)] = RefresherSpec(style: .system, overlay: false, configuration: .default,
                                                    action: { _ in await refreshable() }, indicator: nil)
        }
        result.merge(layer(twin, axes: axes)) { _, new in new }
        result.merge(layer(member, axes: axes)) { _, new in new }
        return result
    }

    /// The start edge of the primary axis: `.top`, or `.leading` for a horizontal-only view.
    static func startEdge(_ axes: Axis.Set) -> Edge {
        axes.contains(.horizontal) && !axes.contains(.vertical) ? .leading : .top
    }

    /// The edges a declaration names, narrowed to the axes the view scrolls (a `.top` refresher on a horizontal-only view
    /// has no pull to measure). Explicit edges (the edge-aware form) beat the configuration's `allowedEdges`.
    static func edges(of decl: RefresherDecl, axes: Axis.Set) -> [Edge] {
        let named = decl.edges ?? decl.spec.configuration.allowedEdges ?? Edge.Set(startEdge(axes))
        return [Edge.top, .leading, .bottom, .trailing].filter { edge in
            named.contains(Edge.Set(edge)) && axes.contains(axis(of: edge))
        }
    }

    static func axis(of edge: Edge) -> Axis.Set {
        edge == .top || edge == .bottom ? .vertical : .horizontal
    }

    private static func layer(_ decls: [RefresherDecl], axes: Axis.Set) -> [Edge: RefresherSpec] {
        var result: [Edge: RefresherSpec] = [:]
        for decl in decls {
            for edge in edges(of: decl, axes: axes) { result[edge] = decl.spec }
        }
        return result
    }

    /// The values of a spec the coordinator compares to decide whether an engine must be rebuilt (closures never compare).
    struct Signature: Equatable {
        var style: ZTronRefreshStyle
        var overlay: Bool
        var configuration: ZTronRefreshConfiguration
        var custom: Bool
    }

    static func signature(_ specs: [Edge: RefresherSpec]) -> [Edge: Signature] {
        specs.mapValues { Signature(style: $0.style, overlay: $0.overlay, configuration: $0.configuration, custom: $0.indicator != nil) }
    }
}
