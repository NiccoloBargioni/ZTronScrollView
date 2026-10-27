import SwiftUI

/// The container's header hook (design M8b §2.2): drawn in an overlay of the viewport attached after its
/// `.ignoresSafeArea` (SwiftUI places the header slot's top edge at the safe-area top in the same layout pass as the
/// container), above the content and below the refresh indicators and the scroll indicators. Cold: its body runs on
/// install, on a parent rebuild (a new builder closure is always applied, R7) and never because of scrolling,
/// refreshing, collapse, stretch or a resize.
struct HeaderHost: View {
    let spec: HeaderSpec
    let state: ZTronScrollState

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("header.builder")
        #endif
        // The ONLY place the user's builder runs. The erased type is fixed at the call site, so the header keeps its
        // identity and `@State` across every update; the modifiers below never change structure (a `size` change keeps it).
        let built = spec.builder(ZTronHeaderProxy(state: state))
        // The header stack, built here (cold) and framed by the hot leaf: the content fills the live frame (top-aligned;
        // proposed no height, its ideal height: `.fit` measures through it), the background below it fills the same frame
        // (an ambient copy is the same builder result, a second instance), the fade above it.
        return built
            .modifier(HeaderMeasure(state: state, active: spec.size.isFit))
            .modifier(HeaderInteractionGate(state: state))
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
            .background(HeaderBackgroundView(background: spec.background, copy: built))
            .overlay(HeaderFade(fade: spec.fade))
            .modifier(HeaderFrameModifier(state: state, size: spec.size, overflow: spec.overflow))
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
        let container = HeaderMath.containerHeight(viewport: m.viewportSize, safe: m.safeAreaInsets,
                                                   adjusted: contentInsetAdjustmentBehavior.edges(for: scrollAxes))
        let next = headerSpec.flatMap {
            $0.resolve(width: m.viewportSize.width, natural: headerNatural, vertical: scrollAxes.contains(.vertical),
                       containerHeight: container)
        }
        guard next != m.header else { return }
        setHeaderMetrics(next)
    }

    /// `.fit`: the header's measured ideal height at the viewport width (`HeaderMeasure`); a change is a discrete inset
    /// change, never per frame.
    func setHeaderNatural(_ height: CGFloat) {
        #if DEBUG
        ZTronRenderCounters.event(String(format: "nat %.1f open:%d", height, isResizeInFlight ? 1 : 0))
        #endif
        guard height.isFinite, abs(height - (headerNatural ?? -1)) > 0.5 else { return }
        headerNatural = height
        headerNaturalLive = nil   // an older layout record must not override this value
        headerMeasurements += 1
        #if DEBUG
        ZTronRenderCounters.increment("header.measure")
        #endif
        headerSpecChanged()
    }
}
