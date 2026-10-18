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
    static func reduce(value: inout ViewportMetrics, nextValue: () -> ViewportMetrics) { value = nextValue() }
}

/// Lives in the viewport's background, never around content.
struct ViewportObserver: ViewModifier {
    let state: ZTronScrollState

    @ViewBuilder
    func body(content: Content) -> some View {
        if state.usesGeometryChange, #available(iOS 16, *) {
            content.onGeometryChange(for: ViewportMetrics.self,
                                     of: { ViewportMetrics(size: $0.size, safeArea: $0.safeAreaInsets) },
                                     action: { state.setViewport($0) })
        } else {
            content
                .background(GeometryReader {
                    Color.clear.preference(key: ViewportMetricsKey.self,
                                           value: ViewportMetrics(size: $0.size, safeArea: $0.safeAreaInsets))
                })
                .onPreferenceChange(ViewportMetricsKey.self) { state.setViewport($0) }
        }
    }
}
