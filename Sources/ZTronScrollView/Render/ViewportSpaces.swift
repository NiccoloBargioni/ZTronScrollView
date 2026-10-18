import SwiftUI

/// Named coordinate spaces (design §7). `content` sits under the transform effect: frames read in it do not change
/// while scrolling; `viewport` is the clipped, untransformed container.
public enum ZTronCoordinateSpaces {
    public static var content: CoordinateSpace { CoordinateSpace.named("ztronScroll.content") }
    public static var viewport: CoordinateSpace { CoordinateSpace.named("ztronScroll.viewport") }
}

@available(iOS 17, *)
public extension NamedCoordinateSpace {
    static var ztronContent: NamedCoordinateSpace { .named("ztronScroll.content") }
    static var ztronViewport: NamedCoordinateSpace { .named("ztronScroll.viewport") }
}

struct ViewportMetrics: Equatable {
    var size: CGSize
    var safeArea: EdgeInsets
}

/// Declares a coordinate space; the `if` is on a `let` flag, so the placeholder's branch never flips (R6).
struct NamedSpaceModifier: ViewModifier {
    let name: String
    let useNew: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useNew, #available(iOS 17, *) {
            content.coordinateSpace(.named(name))
        } else {
            content.coordinateSpace(name: name)
        }
    }
}

struct ViewportMetricsKey: PreferenceKey {
    static let defaultValue = ViewportMetrics(size: .zero, safeArea: EdgeInsets())
    static func reduce(value: inout ViewportMetrics, nextValue: () -> ViewportMetrics) {
        let n = nextValue()
        if n.size != .zero { value = n }   // siblings contribute the default; keep the real one
    }
}

/// Lives in the viewport's background, never around content.
struct ViewportObserver: ViewModifier {
    let state: ZTronScrollState
    /// The edges the viewport root ignores the safe area on. The observed frame lies inside the safe area, so the
    /// viewport (what the effect is asked about) is that frame plus the ignored insets.
    let edges: Edge.Set

    private func metrics(size: CGSize, safe: EdgeInsets) -> ViewportMetrics {
        ViewportMetrics(size: CGSize(width: size.width + (edges.contains(.leading) ? safe.leading : 0) + (edges.contains(.trailing) ? safe.trailing : 0),
                                     height: size.height + (edges.contains(.top) ? safe.top : 0) + (edges.contains(.bottom) ? safe.bottom : 0)),
                        safeArea: safe)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if state.usesGeometryChange, #available(iOS 16, *) {
            content.onGeometryChange(for: ViewportMetrics.self,
                                     of: { metrics(size: $0.size, safe: $0.safeAreaInsets) },
                                     action: { state.setViewport($0) })
        } else {
            content
                .background(GeometryReader {
                    Color.clear.preference(key: ViewportMetricsKey.self,
                                           value: metrics(size: $0.size, safe: $0.safeAreaInsets))
                })
                .onPreferenceChange(ViewportMetricsKey.self) { state.setViewport($0) }
        }
    }
}
