import SwiftUI

/// Proposes nil on scrollable axes (content takes its ideal size) and the viewport length on the others; fills the
/// parent's proposal itself; places the content at the origin (design §4).
@available(iOS 16, *)
struct ScrollContentLayout: Layout {
    let axes: Axis.Set

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = ProposedViewSize(width: axes.contains(.horizontal) ? nil : bounds.width,
                                 height: axes.contains(.vertical) ? nil : bounds.height)
        for sub in subviews { sub.place(at: bounds.origin, anchor: .topLeading, proposal: p) }
    }
}

/// Path selection is an `if` on `let` flags fixed at state creation around the placeholder, so the content's
/// identity never changes (R6).
struct ContentLayoutHost: ViewModifier {
    let axes: Axis.Set
    let useLayout: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useLayout, #available(iOS 16, *) {
            ScrollContentLayout(axes: axes) { content }
        } else {
            // The host takes the parent's proposal; the content overflows it from the top-leading corner. (A flexible
            // frame around the fixed-size content would adopt the overflowing size and get centered by the parent.)
            Color.clear.overlay(alignment: .topLeading) {
                content.fixedSize(horizontal: axes.contains(.horizontal), vertical: axes.contains(.vertical))
            }
        }
    }
}

// MARK: Content size measurement (unscaled: below the transform)

struct ContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

/// Preference values travel to every ancestor, and the fallback measurements (`ContentSizeKey`, `ViewportMetricsKey`)
/// belong to one `ZTronScrollView`: without this, a `ZTronScrollView` in the content of another one overwrote the
/// outer's content size and viewport with its own (the outer then fit its content and never scrolled). Applied outside
/// the receivers, so each view still reads its own values.
struct MeasurementIsolation: ViewModifier {
    func body(content: Content) -> some View {
        content
            .transformPreference(ContentSizeKey.self) { $0 = ContentSizeKey.defaultValue }
            .transformPreference(ViewportMetricsKey.self) { $0 = ViewportMetricsKey.defaultValue }
    }
}

struct ContentSizeMeasure: ViewModifier {
    let state: ZTronScrollState

    @ViewBuilder
    func body(content: Content) -> some View {
        if state.usesGeometryChange, #available(iOS 16, *) {
            content.onGeometryChange(for: CGSize.self, of: { $0.size }, action: { state.setContentSize($0) })
        } else {
            content
                .background(GeometryReader { Color.clear.preference(key: ContentSizeKey.self, value: $0.size) })
                .onPreferenceChange(ContentSizeKey.self) { state.setContentSize($0) }
        }
    }
}
