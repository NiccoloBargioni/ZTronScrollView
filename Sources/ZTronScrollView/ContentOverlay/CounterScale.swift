import SwiftUI

// `.counterScaled` content overlays (design M6b §1 "Scaling", resolution R1; the M8-chrome §6 counter-scale helper):
// the overlay keeps its content-space frame and its anchor point, and draws scaled by 1 / zoom around that point.

/// Scale `1 / zoom` about `(anchor.x · width, anchor.y · height)` of the view it modifies. `zoom` is the animatable
/// datum: under a transaction it interpolates with the same curve as `ContentTransform`'s scale, so `1 / zoom` is the
/// exact inverse of the drawn content scale every frame. A non-positive or non-finite zoom draws the identity.
struct CounterScaleEffect: GeometryEffect {
    var zoom: CGFloat
    let anchor: UnitPoint

    var animatableData: CGFloat {
        get { zoom }
        set { zoom = newValue }
    }

    static func transform(zoom: CGFloat, anchor: UnitPoint, size: CGSize) -> CGAffineTransform {
        guard zoom > 0, zoom.isFinite else { return .identity }
        let k = 1 / zoom
        let ax = ContentOverlayMath.finite(anchor.x) * size.width
        let ay = ContentOverlayMath.finite(anchor.y) * size.height
        // translate(a) · scale(k) · translate(−a): the anchor point is fixed.
        return CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: ax - k * ax, ty: ay - k * ay)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(Self.transform(zoom: zoom, anchor: anchor, size: size))
    }
}

/// The leaf that feeds `CounterScaleEffect` the committed zoom. Active (a `.counterScaled` overlay): it reads
/// `targetZoom` — tracked on that key path alone on the Observation path, the `.zoom` channel alone on 15–16 — so its body
/// runs on zoom changes only, never on pure panning (a clock-driven zoom writes the target every frame; a transaction
/// zoom writes it once and the effect interpolates). Inactive (`.withContent`): it reads nothing and never wakes; it is
/// applied to every overlay so that switching `scaling` keeps the overlay's identity. It must not return its bare
/// `content` (a `ViewModifier` whose body only returns `content` is never evaluated).
///
/// Limitation: during a rotation at the fitting scale the content's drawn scale is resolved per frame by the resize
/// commit while `targetZoom` holds the committed value, so a counter-scaled overlay may differ slightly in size
/// mid-rotation; it lands exact.
struct CounterScaleLeaf: ViewModifier {
    let state: ZTronScrollState
    let anchor: UnitPoint
    let isActive: Bool
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        var zoom: CGFloat = 1
        if isActive {
            if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.zoom], of: storage) }
            #if DEBUG
            ZTronRenderCounters.increment("contentOverlay.counterScale.body")
            #endif
            zoom = state.storage.targetZoom
        } else if let storage = state.storage as? ChannelStorage {
            relay.subscribe(to: [], of: storage)
        }
        return content.modifier(CounterScaleEffect(zoom: zoom, anchor: anchor))
    }
}
