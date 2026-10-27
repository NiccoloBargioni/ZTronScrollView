import SwiftUI

/// `.fit`'s natural height (SPEC S10 "Natural height", design M8b §2.6): the header's ideal height at the viewport width,
/// measured directly (never from the height on screen, which would feed back) and reported to the state, where a change
/// is a discrete inset change. Always applied with the same structure (`active` only switches the work off), so a `size`
/// change at runtime keeps the header's identity.
/// - 16+: the frame layout (`HeaderSlotLayout`) asks the header for its ideal size at the proposed width while placing it
///   at the live height and records it synchronously (`headerNaturalLive`); header content changes are seen on the next
///   layout pass. Nothing to do here.
/// - 15 (and forced): a measuring pass at the first layout and on width / Dynamic Type changes: the header is laid out at
///   its ideal height (`fixedSize(vertical:)`, cropped by the live frame) with a size reporter, then returns to the live
///   proposal; at rest the frame itself is the ideal height (`HeaderFallbackFrame`) and reports in the same update.
///   Header content changes are not re-measured inside the band (documented gap).
struct HeaderMeasure: ViewModifier {
    let state: ZTronScrollState
    let active: Bool
    @StateObject private var reporter = HeaderNaturalReporter()

    @ViewBuilder
    func body(content: Content) -> some View {
        let reporter = reporter
        let _ = reporter.attach(state)
        if state.usesLayoutProtocol, #available(iOS 16, *) {
            content
        } else {
            content.modifier(HeaderMeasuringPass(state: state, active: active, reporter: reporter))
        }
    }
}

/// Records each measurement on the state synchronously (`headerNaturalLive`: a cold write, no update; the viewport commit
/// of the same update adopts it) and delivers it as a natural-height change at the next main run-loop iteration (a
/// run-loop block, not a main-queue hop: a nested run loop, a synchronous test's `pump`, drains it too), for changes that
/// are not a resize (a header content change). Dedupes; never publishes.
@MainActor
final class HeaderNaturalReporter: ObservableObject {
    private weak var state: ZTronScrollState?
    /// The frame leaf's last followed header offset (`HeaderLiveInput.offset`), held while a resize is open. Plain storage
    /// (never published): the leaf's body writes it.
    var heldOffset: CGFloat = 0
    private var last: CGFloat?
    private var scheduled = false

    func attach(_ state: ZTronScrollState) { self.state = state }

    /// A measurement at `width`.
    func measured(_ height: CGFloat, width: CGFloat) {
        // A measurement at no width (the hosting view's first, zero-sized layout) says nothing about the header.
        guard height.isFinite, height >= 0, width.isFinite, width > 0 else { return }
        state?.headerNaturalLive = (width, height)
        if let last, abs(last - height) <= 0.5 { return }
        last = height
        guard !scheduled else { return }
        scheduled = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scheduled = false
                if let h = self.last { self.state?.setHeaderNatural(h) }
            }
        }
    }
}

private struct HeaderNaturalReport: Equatable {
    var size: CGSize
    var generation: Int
}

private struct HeaderNaturalKey: PreferenceKey {
    static let defaultValue: HeaderNaturalReport? = nil
    static func reduce(value: inout HeaderNaturalReport?, nextValue: () -> HeaderNaturalReport?) { value = nextValue() ?? value }
}

/// 15: the measuring pass. The width comes from the state's metrics (a cold channel: it changes on resize, not while
/// the header collapses), so this modifier's body never runs per frame. While a resize is open the report joins the open
/// commit in the same update (the new resting height is part of the rotation, not a run-loop turn later).
struct HeaderMeasuringPass: ViewModifier {
    let state: ZTronScrollState
    let active: Bool
    let reporter: HeaderNaturalReporter
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var measuring = true
    /// Bumped at every (re)arming, so a re-measurement that finds the same size still reports (a preference reports
    /// changes only: the pass was otherwise left on, the header laid out at its ideal height under the live frame).
    @State private var generation = 0
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.metrics], of: storage) }
        let width = state.storage.metrics.viewportSize.width
        let pass = active && measuring
        let state = state
        return content
            .fixedSize(horizontal: false, vertical: pass)
            .background(Group {
                if pass {
                    GeometryReader { proxy in
                        Color.clear.preference(key: HeaderNaturalKey.self,
                                               value: HeaderNaturalReport(size: proxy.size, generation: generation))
                    }
                }
            })
            .onPreferenceChange(HeaderNaturalKey.self) { report in
                guard let size = report?.size else { return }
                MainActor.assumeIsolated {
                    reporter.measured(size.height, width: size.width)
                    // A zero-width pass (the first layout of an overlay outside the safe-area region) is ignored and the
                    // pass stays on: the next layout at the real width reports.
                    if size.width > 0 {
                        measuring = false
                        if state.isResizeInFlight { state.unanimated { state.setHeaderNatural(size.height) } }
                    }
                }
            }
            .onChangeCompat(of: width) { _ in arm() }
            .onChangeCompat(of: dynamicType) { _ in arm() }
            .onChangeCompat(of: active) { if $0 { arm() } }
    }

    private func arm() {
        measuring = true
        generation &+= 1
    }
}
