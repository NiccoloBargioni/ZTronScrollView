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

/// R2 (M8b-s8 s9): the viewport height the content's transform is drawn at, from the drawn slot height, along the
/// content's own track. `(v0, v1)` is the resize commit's track (`ResizeCommit.previous` / `current` viewport heights, the
/// span `ContentTransform` maps its drawn size on), `(h0, h1)` the slot heights at its ends: SwiftUI draws the viewport and
/// the slot along the same curve in one transaction, so the viewport moves with the slot's progress (extrapolated past
/// either end as `ResizeMath.progress` is: a spring's overshoot, a retarget). A safe-area step committed during the
/// resize shifts the content's track by the step (`ResizeMath.shifted`) and the slot's by the slot's own step (a
/// bottom-pinned height change: the viewport's top leaves the status bar one turn after the animated commit, 62 pt off
/// the viewport and 0 off the slot; measured before with the last two commits as the pair: the lift 34 · a = 16 pt above
/// the content until it overflowed). A track that does not change the viewport (an inset-only change: an app-animated
/// `.safeAreaInset`, a keyboard) draws at `v1`; a slot that does not move while the viewport does keeps `v1 − h1`.
/// `LiftSpan()` is the identity (a viewport-sized slot).
struct LiftSpan: Equatable, Sendable {
    var v0: CGFloat = 0, h0: CGFloat = 0, v1: CGFloat = 0, h1: CGFloat = 0

    func viewport(slot h: CGFloat) -> CGFloat {
        guard v1 > 0 else { return h }   // `LiftSpan()`: the slot is the viewport (the refresh indicator), or no layout yet
        let tol = ContentTransform.pixelTolerance
        guard abs(v1 - v0) > tol else { return v1 }
        let dh = h1 - h0
        guard abs(dh) > tol else { return h + (v1 - h1) }
        return v0 + (h - h0) / dh * (v1 - v0)
    }
}

/// The host's record of the content's track and the slot heights at its ends (`LiftSpan`). A new track starts at the
/// last committed slot height; a safe-area step (the track's start moved by the same amount as its end) shifts the slot's
/// start by the slot's step. Written by the host's body, read nowhere else (not observed).
final class LiftTrack {
    private var track: LiftSpan?

    /// `start`: the commit's track start (`ResizeCommit.previous` viewport height); `v`, `h`: the committed viewport and
    /// slot heights.
    func span(start: CGFloat, v: CGFloat, h: CGFloat) -> LiftSpan {
        guard v > 0, start > 0 else { return LiftSpan(v0: v, h0: h, v1: v, h1: h) }   // before the first layout
        let tol: CGFloat = 0.01
        guard let t = track else {
            let s = LiftSpan(v0: v, h0: h, v1: v, h1: h)
            track = s
            return s
        }
        if abs(t.v0 - start) <= tol, abs(t.v1 - v) <= tol, abs(t.h1 - h) <= tol { return t }
        var s = LiftSpan(v0: start, h0: t.h1, v1: v, h1: h)
        if abs(start - t.v1) > tol, abs((start - t.v0) - (v - t.v1)) <= tol {
            s.h0 = t.h0 + (h - t.h1)   // a step: both tracks shifted by their own step
        }
        track = s
        return s
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
        ProjectionTransform(CGAffineTransform(translationX: 0, y: lift(size: size)))
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
            let start = metrics.resize.previous.viewport.height > 0 ? metrics.resize.previous.viewport.height : v.height
            let h = HeaderMath.containerHeight(viewport: v, safe: metrics.safeAreaInsets,
                                               adjusted: state.contentInsetAdjustmentBehavior.edges(for: axes),
                                               keyboard: metrics.keyboardExtension)
            span = track.span(start: start, v: v.height, h: h)
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

/// D75 `.headerFollows` + `.stretch` (M8b-s8 s10, design M8b-s8-d75 §2.2 item 5): the header grows by the lift `L` instead
/// of riding down on it, in both `stretchContent:` cases (`.keepTextMagnified` scales by `(h + g + L)/h`,
/// `.keepTextSize` lays the stack out at `grownSize(…, stretch: g + L)`), and compresses only once the content has moved
/// up by `L` (`HeaderLiveInput.lifted(_:)`: the geometry at `o″ = o′ − L`).
///
/// `L` is not linear in a content-size change's progress (`max(0, ·)` at the fit / overflow kink: a layout-interpolated
/// `L` was 25 pt off mid-transition for 300 → 600 pt), so the five consumers of the header's live input cannot
/// interpolate it; and it must not share their attribute (`o′`, `m`): on 27.0 an unanimated write cancels the in-flight
/// animation of the attribute it lands on, and the finger and the clock write `o′` every frame (rows inserted while a
/// hold retracts is the common case). So `L` is evaluated per frame by two animatable carriers around the header's
/// frame chain, the lift's own two attributes (`HeaderLiftBase` / `HeaderLiftShift`) at the committed viewport, and
/// handed to the chain as a PLAIN input (`HeaderFrameChain.build(_:lift:)`): an animation of the consumers' `o′` / `m`
/// is untouched by it (their animatable data does not change), and the shape carrier's animation is untouched by
/// finger writes of `o′`. The transform carrier takes the offset only while the header lifts (it mirrors the lift's
/// and the content's cancellations there); elsewhere a transaction-driven scroll never re-runs its body per frame.
///
/// The bottom edge is exact by construction (the chain moves the stack up by the carriers' `L`, `HeaderLiftHost` moves
/// the slot down by the exact per-frame lift: bottom `= L_exact + R + g`); the carriers' `L` places the top edge, at the
/// slot's top whenever it equals the lift host's (at rest, under content-size, option, inset and zoom changes and
/// rotations).
enum HeaderStretchLift {
    /// The committed viewport the carriers evaluate the lift at (`HeaderMath.lift`'s).
    static func viewport(_ m: ScrollMetrics) -> CGSize {
        m.resize.current.viewport.height > 0 ? m.resize.current.viewport : m.viewportSize
    }

    /// The carriers compute: a vertical `.stretch` header (the lift is 0 there while the committed and the drawn lift
    /// alignments are 0, i.e. outside `.headerFollows` and its animated way in or out).
    static func applies(_ m: ScrollMetrics) -> Bool {
        guard let h = m.header else { return false }
        return h.vertical && h.behavior == .stretch
    }
}

/// `L(TV, S_committed)` at the committed viewport (`HeaderLiftBase`'s value at rest): the transform vector animatable (an
/// inset, zoom or hold animation moves it with the content; while the header lifts the offset is in it too, so the
/// writes that cancel the content's and the lift's animations on 27.0 cancel this one alike). Takes the catch pin as
/// `HeaderLiftBase` does. Hands the value on to `HeaderStretchLiftShift`.
nonisolated struct HeaderStretchLiftBase: ViewModifier, Animatable {
    var base: ContentTransform
    let viewport: CGSize
    /// Compute the lift (a `.stretch` vertical header with live lift inputs); 0 otherwise.
    let stretch: Bool
    var pin: CatchPin.Ref?
    var pinModel = TransformVector()
    let shift: HeaderStretchLiftShift

    /// `HeaderLiftBase`'s transform vector (the host passes a zero offset while the header does not lift: a
    /// transaction-driven scroll then never re-runs this body per frame).
    var animatableData: TransformVector {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }

    func lift() -> CGFloat {
        guard stretch else { return 0 }
        var t = base
        if let pin, pin.pins(.headerLift, converged: t.animatableData.within(pinModel)) { t.animatableData = pinModel }
        return HeaderLift.value(t, viewport: viewport)
    }

    @MainActor func body(content: Content) -> some View {
        var next = shift
        next.base = lift()
        return content.modifier(next)
    }

    /// This carrier with the pin of the last drawn catch and its host's target values as the pin's model.
    func pinned(_ ref: CatchPin.Ref?) -> HeaderStretchLiftBase {
        guard let ref else { return self }
        var c = self
        c.pin = ref
        c.pinModel = animatableData
        return c
    }
}

/// `L(TV, S_drawn) − L(TV, S_committed)` at the committed viewport (`HeaderLiftShift`'s value at rest), the shape
/// animatable (a content-size or `fittingContent:` change), zoom and insets plain, not pinned (C10). Builds the header's
/// frame chain with `L = base + shift` as a plain input.
nonisolated struct HeaderStretchLiftShift: ViewModifier, Animatable {
    var shift: ContentShapeShift
    let viewport: CGSize
    let stretch: Bool
    /// `HeaderStretchLiftBase`'s value this frame.
    var base: CGFloat = 0
    let chain: HeaderFrameChain

    var animatableData: ContentShape {
        get { shift.shape }
        set { shift.shape = newValue }
    }

    func lift() -> CGFloat {
        guard stretch else { return 0 }
        let lifted = ContentShapeShift(shape: shift.shape.lift, committed: shift.committed.lift, scale: shift.scale,
                                       insets: shift.insets, commit: shift.commit)
        let l = base + lifted.delta(size: viewport).y
        return l.isFinite ? max(0, l) : 0
    }

    @MainActor func body(content: Content) -> some View {
        let l = lift()
        let memo = chain.liftMemo
        let vp = viewport
        let jumped = memo.map { m in
            defer { m.last = l; m.viewport = vp }
            // Not across a resize (the committed viewport changed: a rotation, a width or height change): the slot's
            // size is animated in that update and the stack's frame must follow it (17.5 rotate: the stack took the new
            // width in one frame, 341 pt lateral, with the transaction removed); the lift's step there is the commit's.
            guard m.viewport == nil || m.viewport == vp else { return false }
            return m.last.map { abs($0 - l) > 0.001 } ?? false
        } ?? false
        // A lift that changed in this update is applied as it is, never layout-animated: the carriers already give it
        // per frame, and a lift that steps inside an animated update (a refresh hold's release re-splits the lift's two
        // attributes: 94 + 0 -> 0 + 119 in one frame, the content and `HeaderLiftHost` step with it) was otherwise
        // interpolated by the layout over the update's curve (16+'s slot placement and the `.keepTextSize` growth, 15's
        // grown frame): 25 pt top edge, 30 pt seam (hosted, 27.0). The chain's own animatable data is untouched in every
        // other update (the first update of an animated change evaluates the carriers at their old values).
        return chain.build(content, lift: l).transaction { t in if jumped { t.animation = nil } }
    }
}

/// The last lift `HeaderStretchLiftShift` handed to the chain (one per header, `HeaderFrameModifier`'s state).
final class HeaderStretchLiftMemo: @unchecked Sendable {
    var last: CGFloat?
    var viewport: CGSize?
}
