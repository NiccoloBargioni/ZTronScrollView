import SwiftUI

/// `.fit`'s natural height (SPEC S10 "Natural height", design M8b §2.6): the header's ideal height at the viewport width,
/// measured directly (never from the height on screen, which would feed back) and reported to the state, where a change
/// is a discrete inset change. Always applied with the same structure (`active` only switches the work off), so a `size`
/// change at runtime keeps the header's identity.
/// - 16+: `HeaderLayout` asks the single header instance for its ideal size while placing it at the live height; header
///   content changes are seen on the next layout pass.
/// - 15 (and forced): a measuring pass at the first layout and on width / Dynamic Type changes: the header is laid out at
///   its ideal height (`fixedSize(vertical:)`, cropped by the live frame) with a size reporter, then returns to the live
///   proposal. Header content changes are not re-measured (documented gap).
struct HeaderMeasure: ViewModifier {
    let state: ZTronScrollState
    let active: Bool
    @StateObject private var reporter = HeaderNaturalReporter()

    @ViewBuilder
    func body(content: Content) -> some View {
        let reporter = reporter
        let _ = reporter.attach(state)
        if state.usesLayoutProtocol, #available(iOS 16, *) {
            HeaderLayout(active: active, reporter: reporter) { content }
        } else {
            content.modifier(HeaderMeasuringPass(state: state, active: active, reporter: reporter))
        }
    }
}

/// Dedupes and defers the reports out of layout (a state write during a layout pass is not allowed). Never publishes.
@MainActor
final class HeaderNaturalReporter: ObservableObject {
    private weak var state: ZTronScrollState?
    private var last: CGFloat?
    private var scheduled = false

    func attach(_ state: ZTronScrollState) { self.state = state }

    func measured(_ height: CGFloat) {
        guard height.isFinite, height >= 0 else { return }
        if let last, abs(last - height) <= 0.5 { return }
        last = height
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scheduled = false
                if let h = self.last { self.state?.setHeaderNatural(h) }
            }
        }
    }
}

/// 16+: a pass-through layout that also queries the ideal height at the proposed width.
@available(iOS 16, *)
struct HeaderLayout: Layout {
    let active: Bool
    let reporter: HeaderNaturalReporter

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let first = subviews.first else { return .zero }
        if active, let w = proposal.width, w > 0, w.isFinite {
            let natural = first.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
            MainActor.assumeIsolated { reporter.measured(natural) }
        }
        return first.sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

private struct HeaderNaturalKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

/// 15: the measuring pass. The width comes from the state's metrics (a cold channel: it changes on resize, not while
/// the header collapses), so this modifier's body never runs per frame.
struct HeaderMeasuringPass: ViewModifier {
    let state: ZTronScrollState
    let active: Bool
    let reporter: HeaderNaturalReporter
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var measuring = true
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.metrics], of: storage) }
        let width = state.storage.metrics.viewportSize.width
        let pass = active && measuring
        return content
            .fixedSize(horizontal: false, vertical: pass)
            .background(Group {
                if pass {
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderNaturalKey.self, value: proxy.size.height)
                    }
                }
            })
            .onPreferenceChange(HeaderNaturalKey.self) { h in
                guard let h else { return }
                MainActor.assumeIsolated {
                    reporter.measured(h)
                    measuring = false
                }
            }
            .onChangeCompat(of: width) { _ in measuring = true }
            .onChangeCompat(of: dynamicType) { _ in measuring = true }
            .onChangeCompat(of: active) { if $0 { measuring = true } }
    }
}
