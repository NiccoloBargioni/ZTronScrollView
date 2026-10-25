import SwiftUI

/// The header's hot leaf (design M8b §2.3, the `TransformHost` pattern of D10): its OWN body reads the target offset and
/// the metrics and frames its `content` placeholder at the live height. SwiftUI does not re-evaluate the placeholder (the
/// user's header) when this body re-runs; it lays it out again at the new proposal, a layout pass over the header subtree
/// only. It wakes on `.target` (presentation writes never wake it), so under a transaction (`withAnimation { scrollTo }`,
/// an inset change) it runs once inside the transaction and SwiftUI interpolates the animatable frame in lockstep with
/// the content's `GeometryEffect`; finger and clock motion write the target every frame, so it then runs per frame.
struct HeaderFrameModifier: ViewModifier {
    let state: ZTronScrollState
    let fade: ZTronHeaderFade?
    @Environment(\.displayScale) private var displayScale
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage {
            relay.subscribe(to: [.target, .metrics], of: storage)
        }
        #if DEBUG
        ZTronRenderCounters.increment("header.frame")
        #endif
        let storage = state.storage
        let metrics = storage.metrics
        var offset = storage.targetOffset
        // The same pixel snap as the transform host, so the header's bottom meets the content's top on the same pixel. The
        // phase is read untracked: this leaf never wakes on a phase edge (a settled motion has already written a snapped
        // target).
        if storage.snapshot().phase == .idle, !metrics.resize.isOpen {
            offset.y = ContentGeometry.snap(offset.y, scale: displayScale)
        }
        // The zoom matters only without the vertical axis (D15); a vertical view never wakes on it.
        let zoom = metrics.header?.vertical == false ? storage.targetZoom : 1
        let h = HeaderMath.geometry(offset: offset, zoom: zoom, metrics: metrics)?.height ?? 0
        let visible = h > 0.5
        return content
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: h, maxHeight: h, alignment: .top)
            .overlay(HeaderFade(fade: fade))
            .clipped()
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .padding(.top, HeaderMath.top0(metrics))
    }
}

/// The content's hit-testing gate (D11) for the header, in its own leaf on `.phase` (so the frame leaf never wakes on a
/// phase edge): no press while the content moves without a finger or while a drag is recognized; a drag that starts on
/// a header button scrolls.
struct HeaderInteractionGate: ViewModifier {
    let state: ZTronScrollState
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.phase], of: storage) }
        let storage = state.storage
        let blocked = (storage.phase == .decelerating || storage.phase == .animating) && !storage.isTracking || storage.isDragging
        return content
            .allowsHitTesting(!blocked)
            .disabled(blocked)
    }
}

/// `fade:`: a gradient from clear (at `start · h`) to the color (at the bottom edge), laid out against the live frame:
/// it follows the frame by layout and reads nothing.
struct HeaderFade: View {
    let fade: ZTronHeaderFade?

    var body: some View {
        if let fade {
            LinearGradient(colors: [fade.color.opacity(0), fade.color],
                           startPoint: UnitPoint(x: 0.5, y: min(max(fade.start, 0), 1)), endPoint: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
