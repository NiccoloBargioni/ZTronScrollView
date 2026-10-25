import SwiftUI

/// The container's header hook (design M8b §2.2): drawn in the viewport overlay, top edge pinned, above the content and
/// below the refresh indicators and the scroll indicators. Cold: its body runs on install, on a parent rebuild (a new
/// builder closure is always applied, R7) and never because of scrolling, refreshing, collapse or stretch.
struct HeaderHost: View {
    let spec: HeaderSpec
    let state: ZTronScrollState

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("header.builder")
        #endif
        // The ONLY place the user's builder runs. The erased type is fixed at the call site, so the header keeps its
        // identity and `@State` across every update; the modifiers below never change structure (a `size` change keeps it).
        return spec.builder(ZTronHeaderProxy(state: state))
            .modifier(HeaderMeasure(state: state, active: spec.size.isFit))
            .modifier(HeaderInteractionGate(state: state))
            .modifier(HeaderFrameModifier(state: state, fade: spec.fade))
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(1)                // "precedes the content": announced before it
    }
}

/// The overlay slot: the header when one is installed, nothing otherwise.
struct HeaderOverlay: View {
    let spec: HeaderSpec?
    let state: ZTronScrollState

    var body: some View {
        if let spec {
            HeaderHost(spec: spec, state: state)
        }
    }
}

/// On a view whose axes exclude `.vertical` the header is a banner stacked above the content (SPEC S10): the content's
/// height proposal is the viewport minus the resting height. A leaf on `.metrics` around the content placeholder (no
/// content body runs when it changes, only a layout pass); 0 on a vertical view or without a header, so it never changes
/// the content's structure. Inside the layout host: the content is proposed `V − R` and the padded box keeps `V`.
struct HeaderContentReserve: ViewModifier {
    let state: ZTronScrollState
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.metrics], of: storage) }
        let header = state.storage.metrics.header
        return content.padding(.bottom, header.map { $0.vertical ? 0 : $0.resting } ?? 0)
    }
}

extension ZTronScrollState {
    /// The container's spec changed (install, removal, `size` / behavior / snap): re-resolve at the current width.
    func headerSpecChanged() {
        if headerSpec == nil { headerNatural = nil }
        let m = peek.metrics
        let next = headerSpec.flatMap {
            $0.resolve(width: m.viewportSize.width, natural: headerNatural, vertical: scrollAxes.contains(.vertical))
        }
        guard next != m.header else { return }
        setHeaderMetrics(next)
    }

    /// `.fit`: the header's measured ideal height at the viewport width (`HeaderMeasure`); a change is a discrete inset
    /// change, never per frame.
    func setHeaderNatural(_ height: CGFloat) {
        guard height.isFinite, abs(height - (headerNatural ?? -1)) > 0.5 else { return }
        headerNatural = height
        #if DEBUG
        ZTronRenderCounters.increment("header.measure")
        #endif
        headerSpecChanged()
    }
}
