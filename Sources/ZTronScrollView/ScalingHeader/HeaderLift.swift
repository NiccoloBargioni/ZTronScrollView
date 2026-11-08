import SwiftUI
import ZTronScrollPhysics

/// D75 `.headerFollows` (design M8b-s8-d75 §2.2 item 4): the lift `L = slack · liftY` moves the header down onto the top
/// edge of content that fits, as if the header were the content's first row. The content is drawn with
/// `pad = slack · a` by two attributes (`ContentTransform` from the committed shape, `ContentShapeShift` for the drawn
/// shape's difference, `TransformHost`); the lift mirrors both, term for term, with the lift alignment in place of the
/// content's: `HeaderLiftBase` (animatable `TransformVector`, the committed shape) and `HeaderLiftShift` (animatable
/// `ContentShape`, plain zoom and insets). With `liftY = a` the header's expression is the content's, so header bottom and
/// content top stay together under any mix of animated, unanimated and cancelled writes (a pinch, a row change, an option
/// change, a refresh hold and its retraction, a catch).
///
/// Both evaluate `ContentTransform.resolved` (the very function the content's transform draws its padding with), so when
/// the slack's definition changes (D71: a refresh hold no longer narrows it) the header follows the content unchanged.
/// The header slot is the region between the safe areas, not the viewport the content's transform is sized to: the
/// effects reconstruct the viewport from the drawn slot height (`LiftSpan`: the committed viewport and slot heights
/// before and after their last change, the viewport interpolated with the slot's progress), so a resize that also moves
/// the safe insets (R2: a bottom-pinned height change) and an app-animated safe-area change at a fixed viewport (a
/// bottom `.safeAreaInset`) stay exact. The refresh indicator's slot is viewport-sized. 0 on every view that does not
/// lift (`liftY` 0 committed and drawn).
enum HeaderLift {
    /// Which effect instance pins after a catch (D79: one latch per effect and per slot, D80's two-slot rule).
    enum Slot: Hashable, Sendable {
        case headerFront, headerBehind, refresh, refreshBehind
    }

    /// The content transform the lift resolves: the content's own (`TransformHost`'s inputs) with the lift alignment
    /// (`x` unused: the lift is vertical).
    static func transform(offset: CGPoint, scale: CGFloat, metrics m: ScrollMetrics, limits: ZoomLimits,
                          paging: Axis.Set) -> ContentTransform {
        ContentTransform(offset: offset, scale: scale, insets: m.adjustedContentInset, commit: m.resize, limits: limits,
                         alignment: UnitPoint(x: 0, y: m.alignment.liftY), paging: paging, probe: nil)
    }

    /// The lift of a transform resolved at viewport size `v` (`HeaderMath.lift`'s pure core).
    static func value(_ t: ContentTransform, viewport v: CGSize) -> CGFloat {
        guard t.alignment.y != 0 else { return 0 }
        return t.resolved(size: v).pad.y
    }
}

/// R2 (M8b-s8 s9): the viewport height the content's transform is drawn at, from the drawn slot height. `(v0, h0)` and
/// `(v1, h1)` are the committed (viewport, slot) heights before and after their last change: SwiftUI draws both frames
/// along the same curve in one transaction, so the viewport moves with the slot's progress (extrapolated past either end
/// as `ResizeMath.progress` is: a spring's overshoot, a retarget). A slot that does not move (a pair closer than a pixel:
/// a keyboard, which the slot ignores; the first layout) keeps the committed difference `v1 − h1`. Measured before
/// (`slot + dv` with the committed `dv`): a 150 pt app-animated bottom `.safeAreaInset` drew the lift over the animation
/// while the content's pad had moved (75 pt overlap), and a bottom-pinned height change left 15.7 pt gaps (seam lab).
struct LiftSpan: Equatable, Sendable {
    var v0: CGFloat = 0, h0: CGFloat = 0, v1: CGFloat = 0, h1: CGFloat = 0

    func viewport(slot h: CGFloat) -> CGFloat {
        let dh = h1 - h0
        guard abs(dh) > ContentTransform.pixelTolerance else { return h + (v1 - h1) }
        return v0 + (h - h0) / dh * (v1 - v0)
    }
}

/// The host's record of the committed (viewport, slot) heights (`LiftSpan`): a change moves the current pair to the
/// previous one. Written by the host's body, read nowhere else (not observed).
final class LiftTrack {
    private var previous: (v: CGFloat, h: CGFloat)?
    private var current: (v: CGFloat, h: CGFloat)?

    func span(v: CGFloat, h: CGFloat) -> LiftSpan {
        guard v > 0 else { return LiftSpan(v0: v, h0: h, v1: v, h1: h) }   // before the first layout: nothing recorded
        if let c = current, c.v != v || c.h != h { previous = c }
        current = (v, h)
        let p = previous ?? (v, h)
        return LiftSpan(v0: p.v, h0: p.h, v1: v, h1: h)
    }
}

extension ContentShape {
    /// The shape with the lift alignment in the content alignment's place (`ContentShapeShift.delta` then gives the lift's
    /// difference).
    var lift: ContentShape { ContentShape(width: width, height: height, ax: 0, ay: liftY, liftY: liftY) }
}

/// `L(TV, S_committed)` at the reconstructed viewport (`LiftSpan`): the content transform's padding with the lift alignment, the transform vector
/// animatable (an inset, zoom or resize animation moves it with the content). Takes the catch pin as `ContentTransform`
/// does (else a catch during an inset animation would draw the model here and the interpolation there: a `Δslack · a`
/// seam).
struct HeaderLiftBase: GeometryEffect {
    var base: ContentTransform
    let span: LiftSpan
    let slot: HeaderLift.Slot
    var pin: CatchPin.Ref?
    var pinModel = TransformVector()

    var animatableData: TransformVector {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }

    func lift(size: CGSize) -> CGFloat {
        var t = base
        if let pin, pin.pins(.lift(slot), converged: t.animatableData.within(pinModel)) { t.animatableData = pinModel }
        return HeaderLift.value(t, viewport: CGSize(width: size.width, height: span.viewport(slot: size.height)))
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let l = lift(size: size)
        return ProjectionTransform(CGAffineTransform(translationX: 0, y: l))
    }

    /// This effect with the pin of the last drawn catch and its host's target values as the pin's model.
    func pinned(_ ref: CatchPin.Ref?) -> HeaderLiftBase {
        guard let ref else { return self }
        var c = self
        c.pin = ref
        c.pinModel = base.animatableData
        return c
    }
}

/// `L(TV, S_drawn) − L(TV, S_committed)` at the reconstructed viewport: `ContentShapeShift`'s difference with the lift alignment, the
/// shape animatable (a content-size or `fittingContent:` change adopted in an animated transaction), zoom and insets plain.
/// Not pinned (C10: the shape runs through a catch, as the content's does).
struct HeaderLiftShift: GeometryEffect {
    var shift: ContentShapeShift
    let span: LiftSpan

    var animatableData: ContentShape {
        get { shift.shape }
        set { shift.shape = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let lifted = ContentShapeShift(shape: shift.shape.lift, committed: shift.committed.lift, scale: shift.scale,
                                       insets: shift.insets, commit: shift.commit)
        let d = lifted.delta(size: CGSize(width: size.width, height: span.viewport(slot: size.height))).y
        return ProjectionTransform(CGAffineTransform(translationX: 0, y: d))
    }
}

/// The lift's hot leaf (S4: `content` is the placeholder, so no header or indicator body runs when it re-evaluates):
/// reads what `TransformHost` reads (`.target`, `.metrics`, `.phase`), snaps the offset at rest as it does, and applies
/// `HeaderLiftBase` and `HeaderLiftShift` in `TransformHost`'s order. On both header slots (overlay and `.slideBehind`'s
/// background) and on the top refresh indicator. `active`: this slot draws a lifting header or indicator (a vertical
/// header with `fittingContent: .headerFollows` installed in this slot); otherwise it reads only the metrics (an animated
/// change out of `.headerFollows` still lands its last frames) and on a view that never lifts it is the identity.
struct HeaderLiftHost: ViewModifier {
    let state: ZTronScrollState
    let axes: Axis.Set
    /// The slot is viewport-sized (the refresh overlay); otherwise it is the header slot (`LiftSpan`).
    let viewportSized: Bool
    let slot: HeaderLift.Slot
    let active: Bool
    @Environment(\.displayScale) private var displayScale
    @StateObject private var relay = ChannelRelay()
    @State private var track = LiftTrack()

    func body(content: Content) -> some View {
        let storage = state.storage
        var metrics = storage.metrics
        // Lifted only while a vertical header is resolved (before it resolves nothing is drawn to ride on the content).
        if metrics.header?.vertical != true { metrics.alignment.liftY = 0 }
        // Per frame only where the lift can be non-zero (the committed lift alignment, or an active `.headerFollows`
        // slot); elsewhere a metrics publish (an option change, a content-size change) is enough.
        let hot = active && (metrics.alignment.liftY != 0 || state.headerSpec?.fitting == .headerFollows)
        if let channels = storage as? ChannelStorage {
            relay.subscribe(to: hot ? [.target, .metrics, .phase] : [.metrics], of: channels)
        }
        #if DEBUG
        if hot { ZTronRenderCounters.increment("headerLift.body") }
        #endif
        let peek = hot ? nil : state.peek
        let scale = peek?.targetZoom ?? storage.targetZoom
        var offset = peek?.targetOffset ?? storage.targetOffset
        let phase = peek?.phase ?? storage.phase
        if phase == .idle, !metrics.resize.isOpen {
            offset = CGPoint(x: ContentGeometry.snap(offset.x, scale: displayScale),
                             y: ContentGeometry.snap(offset.y, scale: displayScale))
        }
        let span: LiftSpan
        if viewportSized {
            span = LiftSpan()
        } else {
            let v = metrics.resize.current.viewport.height > 0 ? metrics.resize.current.viewport : metrics.viewportSize
            span = track.span(v: v.height, h: HeaderMath.containerHeight(viewport: v, safe: metrics.safeAreaInsets,
                                                                         adjusted: state.contentInsetAdjustmentBehavior.edges(for: axes),
                                                                         keyboard: metrics.keyboardExtension))
        }
        let t = HeaderLift.transform(offset: offset, scale: scale, metrics: metrics, limits: state.zoomLimits,
                                     paging: state.isPagingEnabled ? axes : [])
        let shape = ContentShape(size: metrics.resize.current.contentSize, alignment: metrics.alignment)
        return content
            .modifier(HeaderLiftBase(base: t, span: span, slot: slot).pinned(state.catchPinRef))
            .modifier(HeaderLiftShift(shift: ContentShapeShift(shape: shape, committed: shape, scale: scale,
                                                               insets: metrics.adjustedContentInset, commit: metrics.resize),
                                      span: span))
    }
}
