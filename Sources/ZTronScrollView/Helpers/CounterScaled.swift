import Combine
import SwiftUI

// Counter-scaled views (SPEC S6 helper, design M8-chrome §6; built by M6b L1 for `.counterScaled` content overlays,
// design M6b §1 "Scaling" and §5): the view keeps its layout frame and its anchor point in the content, and draws scaled
// by 1 / zoom around that point, so its on-screen size stays constant while the content zooms. One implementation:
// the public `ztronScrollCounterScaled(anchor:)` and the overlay host both apply `CounterScaleLeaf`.

extension View {
    /// Keeps this view at a constant on-screen size inside a ``ZTronScrollView``: it is drawn scaled by
    /// `1 / zoomScale` around `anchor` (a point of this view), so a map pin keeps its size and its anchor point stays on
    /// the content point it marks while the content zooms.
    ///
    /// The view's layout frame is unchanged: it still takes its unscaled size in the content. The scale follows every
    /// zoom of the nearest enclosing `ZTronScrollView` (pinch, zoom bounce, animated and programmatic zooms, with the
    /// content's own curve); hit-testing follows the drawn geometry. Scrolling never re-evaluates anything here, and a
    /// zoom re-evaluates a small leaf only, never this view's body. During a rotation at the fitting scale the drawn
    /// scale may differ slightly mid-rotation and lands exact. Outside a `ZTronScrollView` the view draws unchanged.
    ///
    /// - Parameter anchor: The point of this view that stays fixed (default `.center`; a pin's tip is `.bottom`).
    public func ztronScrollCounterScaled(anchor: UnitPoint = .center) -> some View {
        modifier(CounterScaledModifier(anchor: anchor))
    }
}

/// The public helper: the nearest `ZTronScrollView`'s state from the environment (constant per container), then the leaf.
/// Not a bare-`content` modifier: it always applies the leaf, so its body runs.
struct CounterScaledModifier: ViewModifier {
    let anchor: UnitPoint
    @Environment(\.ztronScrollState) private var state

    func body(content: Content) -> some View {
        content.modifier(CounterScaleLeaf(state: state, anchor: anchor, isActive: state != nil))
    }
}

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
        #if DEBUG
        if Thread.isMainThread {
            let value = CounterScaleProbe.Value(zoom: zoom, anchor: anchor, size: size)
            MainActor.assumeIsolated { CounterScaleProbe.last = value }
        }
        #endif
        return ProjectionTransform(Self.transform(zoom: zoom, anchor: anchor, size: size))
    }
}

#if DEBUG
/// The inputs of the last `CounterScaleEffect` drawn (tests read the effect's value through it).
@MainActor
enum CounterScaleProbe {
    struct Value: Equatable, Sendable { var zoom: CGFloat; var anchor: UnitPoint; var size: CGSize }
    static var last: Value?
}
#endif

/// The leaf that feeds `CounterScaleEffect` the committed zoom. Active: it reads `targetZoom` alone — tracked on that
/// key path on the Observation path, woken by `ChannelStorage.targetZoomChannel` (target-zoom writes only) on 15–16 —
/// so its body runs when the target zoom changes and never on panning, on presentation-only zoom writes (the
/// transaction probe, the resize tick of a rotation) or on metrics. A clock-driven zoom (pinch, zoom bounce,
/// `setZoomScale(_:animated: true)`, `zoom(to:animated: true)`) writes the target every frame, so the leaf runs every
/// frame of it; a transaction zoom writes it once and the effect interpolates. Inactive (a `.withContent` overlay, or no
/// enclosing scroll view): it reads nothing and never wakes; the overlay host applies it to every overlay so that
/// switching `scaling` keeps the overlay's identity. It must not return its bare `content` (a `ViewModifier` whose body
/// only returns `content` is never evaluated).
///
/// Limitation: during a rotation at the fitting scale the content's drawn scale is resolved per frame by the resize
/// commit while `targetZoom` holds the committed value, so a counter-scaled view may differ slightly in size
/// mid-rotation; it lands exact.
struct CounterScaleLeaf: ViewModifier {
    let state: ZTronScrollState?
    let anchor: UnitPoint
    let isActive: Bool
    @StateObject private var relay = TargetZoomRelay()

    func body(content: Content) -> some View {
        var zoom: CGFloat = 1
        if isActive, let state {
            relay.subscribe(to: (state.storage as? ChannelStorage)?.targetZoomChannel)
            #if DEBUG
            ZTronRenderCounters.increment("contentOverlay.counterScale.body")
            #endif
            zoom = state.storage.targetZoom
        } else {
            relay.subscribe(to: nil)
        }
        return content.modifier(CounterScaleEffect(zoom: zoom, anchor: anchor))
    }
}

/// One `objectWillChange` per target-zoom change (fallback path). Never subscribes on the Observation path, so the leaf
/// type is the same on both paths.
final class TargetZoomRelay: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var source: ObjectIdentifier?
    private var cancellable: AnyCancellable?

    @MainActor func subscribe(to publisher: ObservableObjectPublisher?) {
        let id = publisher.map(ObjectIdentifier.init)
        guard id != source else { return }
        source = id
        cancellable = publisher?.sink { [weak self] in self?.objectWillChange.send() }
    }
}
