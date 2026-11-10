import SwiftUI
import ZTronScrollPhysics

/// D78 (open item 15 (b)): the header's frame leaf with the slot's size on the 15 path. 16+: `HeaderFrameModifier` itself
/// (its `HeaderSlotLayout` is proposed `W × H`). 15 / forced: a `GeometryReader` around it, the header slot (the overlay /
/// background of the viewport after `.ignoresSafeArea`, so `H` is the container height `HeaderMath.containerHeight`
/// resolves the overflow limit against), whose `W × H` reaches `HeaderFallbackFrame` in the same layout pass as the
/// container: an app-animated resize resolves `R(W, H)` in its animated pass (U0) and the unanimated viewport commit
/// (U1) changes nothing in the header's layout (D51 / D62), as on 16+. Before D78 the 15 path read `R` from the
/// committed metrics, so a limited `R`, `.fixed` under a limit and `.fit` in the band landed at U1 (forced lane: up to
/// 115 pt in one frame, 159 pt lateral).
///
/// Cold: the closure runs when the slot's size changes (a resize, once, in U0) or the host's body runs (a parent
/// rebuild, R7); the leaf inside wakes on its own channels without it, so scrolling, collapse, a pull, a refresh and a
/// header content change never run it (S4; DEBUG counter `header.slot`, event `slot W×H`). The branch is a `let` flag
/// fixed at state creation (R6): the identity never changes.
struct HeaderSlotReader: ViewModifier {
    let state: ZTronScrollState
    let size: ZTronHeaderSize
    let overflow: ZTronHeaderOverflow
    let fade: ZTronHeaderFade?
    /// D76 (`stretchContent:`), handed to the leaf.
    var stretchContent: ZTronHeaderStretchContent = .keepTextMagnified

    @ViewBuilder
    func body(content: Content) -> some View {
        if state.usesLayoutProtocol, #available(iOS 16, *) {
            content.modifier(HeaderFrameModifier(state: state, size: size, overflow: overflow, fade: fade,
                                                 stretchContent: stretchContent))
        } else {
            let state = state, size = size, overflow = overflow, fade = fade, stretchContent = stretchContent
            GeometryReader { proxy in
                content.modifier(HeaderFrameModifier(state: state, size: size, overflow: overflow, fade: fade,
                                                     stretchContent: stretchContent, slot: Self.noted(proxy.size)))
            }
        }
    }

    /// The slot's size, counted (DEBUG; main thread only; the note `header.slot.size` is `HeaderSlotLayout`'s on 16+).
    nonisolated static func noted(_ size: CGSize) -> CGSize {
        #if DEBUG
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                ZTronRenderCounters.increment("header.slot")
                ZTronRenderCounters.event(String(format: "slot %.2fx%.2f", size.width, size.height))
                ZTronRenderCounters.notes["header.slot.size"] = "\(size.width)x\(size.height)"
            }
        }
        #endif
        return size
    }
}

/// The header's hot leaf (design M8b §2.3, the `TransformHost` pattern of D10): its OWN body reads the target offset and
/// the metrics and frames its `content` placeholder (the cold header stack: the user's header and its background, built
/// by `HeaderHost`) at the live frame, and draws the `fade:` over it (D70, `HeaderFadeOverlay`). SwiftUI does not re-evaluate the placeholder when this body re-runs; it lays
/// it out again at the new proposal, a layout pass over the header subtree only. It wakes on `.target` (presentation
/// writes never wake it): under a transaction it runs once inside the transaction, and finger and clock motion write the
/// target every frame, so it then runs per frame.
///
/// The geometry comes from LAYOUT (M8b-3 seamless header, seam spike A), so the header moves with the content in every
/// animation: its slot's top edge is placed by SwiftUI (the overlay is attached after the container's `.ignoresSafeArea`,
/// so it starts at the safe-area top), its height is `(1 − p) · R(W, H) + p · min` with `W × H` the proposed size and
/// `R(W, H)` resolved in the same layout pass as the container (size and overflow policy, exactly as the state resolves
/// it; 16+: `HeaderSlotLayout`, 15 / forced: `HeaderFallbackFrame`), and `p`, the stretch and the `.preserve`
/// translation come from the state (the translation is the pull with `ZTronHeaderPullBehavior.followContent`, D61, and
/// always 0 with the default `.openGap`, D65: that header stays still and the gap opens below it, by the content's own
/// transform; the background and the fade are inside the framed stack, so they follow the frame in both modes). The
/// `.stretch` growth is a render-time scale of the framed stack (D69, `HeaderStretchEffect` + `HeaderStretchClip`): a
/// pull lays nothing out. `.slideBehind` (D68) keeps the height at `R(W, H)` and moves the header up by `k · p · R(W, H)`
/// (the layout's own `R`: 16+ placement, 15 `HeaderTranslation`); its slot is the container's `.background`, behind the
/// content. An animated resize then interpolates the header with the content; the unanimated resize commit changes
/// nothing in the header while the progress is kept (D51). The fade's crossfade (D70) reads the same live input (plus the
/// pull, which only it reads), so it never lags the geometry.
///
/// 15 / forced (D78): `slot` is the header slot's `W × H` from `HeaderSlotReader`'s cold `GeometryReader`, the size
/// 16+'s `HeaderSlotLayout` is proposed; `HeaderFallbackFrame` resolves `R(W, H)` from it in the same layout pass.
struct HeaderFrameModifier: ViewModifier {
    let state: ZTronScrollState
    let size: ZTronHeaderSize
    let overflow: ZTronHeaderOverflow
    let fade: ZTronHeaderFade?
    /// D76: what a `.stretch` pull does to the content (`HeaderLiveInput.layoutShare`, set in `wake()`).
    var stretchContent: ZTronHeaderStretchContent = .keepTextMagnified
    /// 15 / forced: the slot's size (`HeaderSlotReader`); `nil` on 16+ (the layout's proposal) and without a reader.
    var slot: CGSize? = nil
    @StateObject private var relay = ChannelRelay()
    @StateObject private var reporter = HeaderNaturalReporter()
    @State private var liftMemo = HeaderStretchLiftMemo()
    /// D76: the clip snaps a grown frame's side inset to the pixel grid (`HeaderMath.stretchClip`).
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        // D75 `.headerFollows` + `.stretch` (`HeaderStretchLift`): the lift's two attributes evaluated per frame around the
        // chain, handed to it as a plain input. Real zoom, insets and shape on every vertical `.stretch` header (an option
        // change into or out of `.headerFollows` then animates from real values, as `HeaderLiftHost`'s; the lift is 0 while
        // both lift alignments are); while it lifts (`lifting`) the offset too, read and snapped exactly as `HeaderLiftHost`
        // reads it, so the carrier's transform vector takes the same writes as the lift's and the content's (on 27.0 an
        // unanimated write cancels an inset animation in flight: the three must cancel together). Constants (the identity,
        // never animated) on every other header.
        let storage = state.storage
        let metrics = storage.metrics
        let stretch = HeaderStretchLift.applies(metrics)
        let lifting = stretch && (metrics.alignment.liftY != 0 || state.headerSpec?.fitting == .headerFollows)
        let live = wake(phase: lifting)
        let chain = HeaderFrameChain(live: live, state: state, fade: fade, slot: slot, reporter: reporter,
                                     displayScale: displayScale, liftMemo: lifting ? liftMemo : nil)
        let viewport = HeaderStretchLift.viewport(metrics)
        let base: ContentTransform, shape: ContentShape
        if stretch {
            var offset = CGPoint.zero
            if lifting {
                offset = storage.targetOffset
                if storage.phase == .idle, !metrics.resize.isOpen {
                    offset = CGPoint(x: ContentGeometry.snap(offset.x, scale: displayScale),
                                     y: ContentGeometry.snap(offset.y, scale: displayScale))
                }
            }
            base = HeaderLift.transform(offset: offset, scale: storage.targetZoom, metrics: metrics,
                                        limits: state.zoomLimits, paging: state.isPagingEnabled ? state.scrollAxes : [])
            shape = metrics.shapeModel   // R1-RC1-1: a resize's reflow in `shapeBase`, as the content's
        } else {
            base = HeaderLift.transform(offset: .zero, scale: 1, metrics: ScrollMetrics(), limits: ZoomLimits(), paging: [])
            shape = ContentShape()
        }
        let shift = HeaderStretchLiftShift(shift: ContentShapeShift(shape: shape, committed: shape, scale: base.scale,
                                                                    insets: base.insets, commit: base.commit,
                                                                    base: stretch ? metrics.shapeBase : ContentShape()),
                                           viewport: viewport, stretch: stretch, chain: chain)
        return content.modifier(HeaderStretchLiftBase(base: base, viewport: viewport, stretch: stretch, shift: shift)
                                    .pinned(stretch ? state.catchPinRef : nil))
            .background(HeaderWarmLeaf(state: state, reporter: reporter))   // FirstUseWarm (cost3-O): a leaf of its own
    }

    /// Subscribes (15–16 channels; 17+ tracks the reads below), counts the run and reads the state's half of the frame.
    private func wake(phase: Bool = false) -> HeaderLiveInput {
        if let storage = state.storage as? ChannelStorage {
            relay.subscribe(to: phase ? [.target, .metrics, .phase] : [.target, .metrics], of: storage)
        }
        #if DEBUG
        ZTronRenderCounters.increment("header.frame")
        #endif
        reporter.attach(state)
        let storage = state.storage
        let metrics = storage.metrics
        // The zoom matters only without the vertical axis (D15); a vertical view never wakes on it.
        let zoom = metrics.header?.vertical == false ? storage.targetZoom : 1
        var live = Self.liveInput(size: size, overflow: overflow, metrics: metrics,
                                  edges: state.contentInsetAdjustmentBehavior.edges(for: state.scrollAxes),
                                  target: storage.targetOffset, zoom: zoom, held: reporter.heldOffset,
                                  tracksPull: HeaderFadeMath.tracksPull(fade))
        if live.followsOffset { reporter.heldOffset = live.offset }
        live.natural = state.headerNatural
        live.layoutShare = Self.layoutShare(stretchContent, metrics: metrics.header)
        // D79: after a drawn catch every effect that interpolates `o′` draws the model's until its interpolation reaches it.
        if live.followsOffset, let ref = state.catchPinRef { live.catchPin = HeaderCatchPin(ref: ref, model: live.offset) }
        return live
    }

    /// D76, `m` for `stretchContent`: 1 for `.keepTextSize`, 0 for `.keepTextMagnified` and for a banner (no vertical
    /// axis: `stretchContent:` does not apply). Both paths: 16+'s `HeaderSlotLayout` proposes the grown size, the 15
    /// path's `HeaderFallbackFrame` lays the stack out at it (`HeaderFallbackPlan`).
    static func layoutShare(_ content: ZTronHeaderStretchContent, metrics: HeaderMetrics?) -> CGFloat {
        guard content == .keepTextSize, metrics?.vertical != false else { return 0 }
        return 1
    }

    /// What the framed header carries on every path: the fade (D70, inside the scaled stack: it stretches with the
    /// header), the `.stretch` scale (D69), its own clip, its layer group and the gates. The `.preserve` translation is the
    /// layout's (16+ placement, 15 `HeaderTranslation`), animated with the header offset, and moves the fade with the
    /// header. The fade, the scale and the clip read the same `live` the leaf hands the slot in the same body (no frame
    /// lag) and interpolate `o′` in a transaction-driven scroll exactly as the slot does. D76: the effect magnifies the
    /// share `g_s`, the clip and the fade take the laid-out share `g_l` out of the frame (`grownFrame`: 16+, whose
    /// stack is proposed the grown size; the 15 path's frame is the slot's `W`).
    static func chrome<V: View>(_ framed: V, live: HeaderLiveInput, fade: ZTronHeaderFade?, visible: Bool,
                                group: Bool, grownFrame: Bool, displayScale: CGFloat = 0) -> some View {
        framed
            .modifier(HeaderFadeOverlay(live: live, fade: fade))
            .modifier(HeaderStretchEffect(live: live.geometry))
            // The scaled stack (wider than W, taller by g) clipped to `W × h_L · s` in the unscaled frame: sides cut, the
            // bottom edge on the content's top; the frame itself when nothing stretches (`.clipped()` before D69).
            .clipShape(HeaderStretchClip(live: live.geometry, grown: grownFrame, displayScale: displayScale))
            // The header's own clip in its own layer group: Core Animation then interpolates it as the header's frame, not
            // pre-intersected with the container's clip (an uncapped header taller than the landscape viewport drew its
            // bottom edge at the container's clip, 40 pt above the content's top, all through a rotation).
            .modifier(HeaderLayerGroup(useGeometryGroup: group))
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }

    /// The state's half of the live frame. Bit-stability is the point: the animated layout pass of an app-driven resize lays
    /// the header out with the values of the last render, then the unanimated commit re-renders this leaf; any change in
    /// the layout's result there, even an ulp, re-sets the header's frame WITHOUT animation (the whole in-flight width /
    /// height change jumps to its end). So:
    /// - while a resize is open, the progress, stretch and translation are the resize intent's anchor (captured from the
    ///   same target offset), not re-derived from the realised target (ulps apart);
    /// - no pixel snap of the offset here (the intent is captured unsnapped): at rest the header's edge and the content's
    ///   snapped top can differ by a sub-pixel amount instead.
    /// - otherwise they follow the header offset `o′` (`HeaderLiveInput.offset`, the layout's animatable data), so a
    ///   transaction-driven scroll re-derives them per frame from the interpolated `o′`; `held` is the last followed `o′`,
    ///   kept as the animatable data while a resize is open.
    /// - `tracksPull` (D70): the fade's pull weight reads `pull` (`HeaderFadeMath.tracksPull`); otherwise it stays 0.
    static func liveInput(size: ZTronHeaderSize, overflow: ZTronHeaderOverflow, metrics m: ScrollMetrics, edges: Edge.Set,
                          target: CGPoint, zoom: CGFloat, held: CGFloat = 0, tracksPull: Bool = false) -> HeaderLiveInput {
        guard let header = m.header else {
            return HeaderLiveInput(size: size, overflow: overflow, metrics: nil, tracksPull: tracksPull)
        }
        var p: CGFloat = 0, stretch: CGFloat = 0, translation: CGFloat = 0, pull: CGFloat = 0
        var offset = held, follows = false
        if header.vertical, m.resize.isOpen, let anchor = m.resize.intent?.header {
            switch anchor {
            case let .top(x):
                if header.behavior == .stretch { stretch = max(0, -x) }
                translation = HeaderMath.translation(o: x, m: header)     // 0 with `.openGap` (D65)
                pull = HeaderMath.pullDistance(o: x)
            case let .progress(q): p = q
            case .collapsed: p = header.band > 0 ? 1 : 0
            }
        } else {
            let o = HeaderMath.headerOffset(offset: target, zoom: zoom, metrics: m)
            let g = HeaderMath.geometry(o: o, m: header)
            p = g.progress
            stretch = g.stretch
            translation = HeaderMath.translation(o: o, m: header)
            pull = HeaderMath.pullDistance(o: o)
            offset = o
            follows = true
        }
        let h = HeaderLiveInput.layoutHeight(header, progress: p)
        return HeaderLiveInput(size: size, overflow: overflow, metrics: header, progress: p, stretch: stretch,
                               translation: translation, stateHeight: h,
                               committedContainer: HeaderMath.containerHeight(viewport: m.viewportSize, safe: m.safeAreaInsets,
                                                                              adjusted: edges, keyboard: m.keyboardExtension),
                               offset: offset, followsOffset: follows, pull: tracksPull ? pull : 0, tracksPull: tracksPull)
    }
}

/// The header's frame chain (`HeaderFrameModifier`'s, built per run of the leaf or of the lift carriers around it): the
/// layout half (16+ `HeaderSlotLayout`, which fills the overlay and places the header at its live frame; 15 / forced
/// `HeaderFallbackFrame` + `HeaderTranslation`) and the chrome. The branch is a `let` flag fixed at state creation (R6):
/// the identity never changes. `lift`: D75 `.headerFollows` + `.stretch` (`HeaderLiveInput.lifted(_:)`), 0 otherwise.
struct HeaderFrameChain {
    let live: HeaderLiveInput
    let state: ZTronScrollState
    let fade: ZTronHeaderFade?
    let slot: CGSize?
    let reporter: HeaderNaturalReporter
    let displayScale: CGFloat
    var liftMemo: HeaderStretchLiftMemo? = nil

    @MainActor @ViewBuilder
    func build<V: View>(_ content: V, lift: CGFloat) -> some View {
        let live = self.live.lifted(lift)
        let scale = displayScale
        // The geometry's input (no fade pull): the slot, the frames and the effects never re-lay out for the fade.
        let shape = live.geometry
        let visible = shape.visibleHeight > 0.5
        let group = state.usesGeometryGroup
        let fade = fade
        if state.usesLayoutProtocol, #available(iOS 16, *) {
            HeaderSlotLayout(live: shape, reporter: reporter) {
                HeaderFrameModifier.chrome(content, live: live, fade: fade, visible: visible, group: group, grownFrame: true,
                                           displayScale: scale)
            }
        } else {
            HeaderFrameModifier.chrome(content.modifier(HeaderFallbackFrame(live: shape, state: state, slot: slot,
                                                                            reporter: reporter)),
                                       live: live, fade: fade, visible: visible, group: group, grownFrame: false,
                                       displayScale: scale)
                .modifier(HeaderTranslation(live: shape))
                // The slot: the header at the top of the whole overlay. Without it a header exactly as tall as the
                // region between the safe areas was placed against the bottom safe area (34 pt low; measured).
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// D69: the `.stretch` growth as a render-time scale of the framed stack, anchored at its top centre: `s = (h + g) / h`
/// with `h` the stack's own LAYOUT height (`size`: the slot's `h_L(W, H)` on 16+, `HeaderFallbackFrame`'s on 15 / forced)
/// and `g = live.stretch`, so the scaled stack's bottom edge is `top + h + g`, the content's top, and an aspect-fit image
/// grows with the pull. Identity without a stretch. `size` is the layout's, not the state's: across an open resize `g` is
/// the intent's anchor and `h` the layout's own `R(W, H)`, so the unanimated commit changes nothing drawn; an app-animated
/// resize interpolates `h` with the drawn size. Its animatable data is the header offset `o′` and the laid-out share `m`
/// (D76), like `HeaderSlotLayout` / `HeaderFallbackFrame`: a transaction-driven scroll re-derives `g` per frame in the
/// same transaction, and an animated `stretchContent:` change interpolates `m` with the layout.
///
/// D76: it magnifies the share `g_s = g − g_l` (`HeaderLiveInput.scaleStretch`): all of `g` for `.keepTextMagnified`
/// (D69 bit for bit), nothing for `.keepTextSize` (the stack is laid out grown, `size` is `(W · s_l, h + g)`), and
/// `s_eff = (h + g) / (h + g_l)` inside an animated switch. The crisp `.keepTextMagnified` path (M8b-s9) attaches here,
/// to `g_s`.
///
/// D75 `.headerFollows` + `.stretch` (M8b-s8 s10): `g` includes the lift `L` (`HeaderLiveInput.lifted(_:)`), so the scale
/// is `(h + g + L) / h` and a header on content that fits is magnified AT REST (C13). M8b-s9's crisp path must therefore
/// gate on `g_s > 0` (`(1 − m) · (g + L) > 0`), not on a pull, and cover `0 < m < 1` (an animated `stretchContent:`
/// switch) as well as an `L` that changes while nothing is pulled (rows, the option, a pinch, a hold).
nonisolated struct HeaderStretchEffect: GeometryEffect {
    var live: HeaderLiveInput

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { live.effectData }
        set { live.effectData = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(Self.transform(size: size, stretch: live.pinned(.headerStretch).scaleStretch))
    }

    /// `translate(W/2, 0) · scale(s) · translate(−W/2, 0)`: x ↦ W/2 + s · (x − W/2), y ↦ s · y.
    static func transform(size: CGSize, stretch: CGFloat) -> CGAffineTransform {
        let s = HeaderMath.stretchScale(layoutHeight: size.height, stretch: stretch)
        guard s != 1 else { return .identity }
        let w = size.width.isFinite ? size.width : 0
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: w / 2 * (1 - s), ty: 0)
    }
}

/// D69: the framed header's clip, `W × h · s` in the stack's UNSCALED frame (`h` its layout height, `s` the
/// `HeaderStretchEffect` scale from the same `live`): the scaled stack's sides (it is `s · W` wide) are cut at the slot's
/// width and its bottom edge, `h + g`, is kept. Exactly the frame (`.clipped()`) without a stretch. Same animatable data.
/// D76: path-aware (`HeaderMath.stretchClip`): on 16+ (`grown`) a laid-out share `g_l` grows the frame to `W · s_l`
/// and the clip keeps its centred `W`; the 15 path's frame stays the slot's `W`. With `g_l = 0` it is D69's `rect`.
nonisolated struct HeaderStretchClip: Shape {
    var live: HeaderLiveInput
    /// D76: the stack's frame is the grown one (16+, `HeaderSlotLayout` proposes `grownSize`); `false` on the 15 path.
    var grown = true
    /// The pixel grid the grown frame's side inset snaps to (0: none).
    var displayScale: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { live.effectData }
        set { live.effectData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let l = live.pinned(.headerClip)
        return Path(HeaderMath.stretchClip(in: rect, layoutStretch: l.layoutStretch, scaleStretch: l.scaleStretch,
                                           grownFrame: grown, displayScale: displayScale))
    }

    static func rect(in rect: CGRect, stretch: CGFloat) -> CGRect {
        let s = HeaderMath.stretchScale(layoutHeight: rect.height, stretch: stretch)
        return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * s)
    }
}

/// 15 / forced: the header's translation, animated with the header offset like `HeaderFallbackFrame` (both interpolate the
/// same `o′` in the same transaction): the `.preserve` `.followContent` pull translation (0 with `.openGap`, D65) plus the
/// `.slideBehind` collapse translation `−k · p · h` (D68) with `h` the framed stack's own LAYOUT height (`size`: the
/// fallback frame's `R(W)`), as `HeaderSlotLayout` places it on 16+: an app-animated width change interpolates it with
/// the drawn size and the resize commit re-sets nothing. A geometry effect (hit-testing and accessibility frames follow it,
/// as they followed `.offset(y:)`).
nonisolated struct HeaderTranslation: GeometryEffect {
    var live: HeaderLiveInput

    /// `o′`, the share `m` (`FirstUseWarm` warms it; read only clamped) and the lift `L`
    /// (`HeaderLiveInput.effectData`: an animated resize moves `L` on the layout's curve).
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { live.effectData }
        set { live.effectData = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 0, y: Self.translation(live.pinned(.headerTranslation),
                                                                                     layoutHeight: size.height)))
    }

    /// `t_g + t_c`: the pull translation and the collapse translation of a stack laid out at `layoutHeight`.
    static func translation(_ live: HeaderLiveInput, layoutHeight h: CGFloat) -> CGFloat {
        live.translation + HeaderMath.collapseTranslation(progress: live.progress, parallax: live.parallax, layoutHeight: h)
    }
}

/// 16+: the header's SLOT, the overlay between the safe areas the content adjusts for (`W × H`). It takes the whole
/// proposal (so its size never depends on its own result: a parent that proposes a child its own size again gets the same
/// answer) and places the header at its top (moved down by the `.preserve` `.followContent` translation; `.openGap` keeps
/// it at the top, D65; moved up by the `.slideBehind` parallax `k · p · h`, D68) with the live frame `(W, h(W, H))`
/// (`HeaderMath.liveHeight`; `H` IS the overflow container, the state's `HeaderMath.containerHeight`, from the same layout
/// pass: no committed inset enters it, so a resize that changes the bottom safe area resolves the limit in its animated
/// pass, M8b-s6). The header stack is proposed the live frame (sticky overlays, the background). `.fit` measures the ideal height at `W` here
/// and records it synchronously, so the viewport commit of the same update adopts it. Only the header is hit-tested (a
/// layout has no area of its own). Its animatable data is the header offset `o′` (`HeaderLiveInput.offset`) and the
/// laid-out share `m` (D76): the stack is proposed `HeaderMath.grownSize(W, h, g_l)`, `(W, h)` for `.keepTextMagnified`,
/// `(W · s, h + g)` for `.keepTextSize`, placed at its top centre (the clip keeps the centred `W`).
@available(iOS 16, *)
struct HeaderSlotLayout: Layout {
    var live: HeaderLiveInput
    let reporter: HeaderNaturalReporter

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(live.offset, live.layoutShare) }
        set { live = live.at(offset: newValue.first); live.layoutShare = newValue.second }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = width(proposal)
        if let h = proposal.height, h.isFinite { return CGSize(width: w, height: max(0, h)) }
        // An ideal-size query: the header's own height against the committed container.
        return CGSize(width: w, height: height(at: w, slot: nil, subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if live.catchPin != nil {
            // D79: placed at the model `o′` while the pin holds (`HeaderLiveInput.pinned(_:)`).
            var me = self
            me.live = live.pinned(.headerSlot)
            me.live.catchPin = nil
            return me.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
        }
        #if DEBUG
        // The slot's size (C16: the 15 path's `HeaderSlotReader` notes the same key). Not `HeaderWarmLeaf`'s slot (no
        // metrics: it is never a header's).
        if Thread.isMainThread, live.metrics != nil {
            let note = "\(bounds.width)x\(bounds.height)"
            MainActor.assumeIsolated { ZTronRenderCounters.notes["header.slot.size"] = note }
        }
        #endif
        let h = height(at: bounds.width, slot: bounds.height, subviews)
        // `.slideBehind` (D68): up by `k · p · h` of this pass's own `h` (`R(W, H)`), as the 15 path's `HeaderTranslation`.
        let y = bounds.minY + HeaderTranslation.translation(live, layoutHeight: h)
        // D76: grown by the laid-out share (`(W, h)` exactly without one).
        let grown = HeaderMath.grownSize(width: bounds.width, layoutHeight: h, stretch: live.layoutStretch)
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top,
                              proposal: ProposedViewSize(width: grown.width, height: grown.height))
    }

    private func width(_ p: ProposedViewSize) -> CGFloat {
        if let w = p.width, w.isFinite { return max(0, w) }
        return live.metrics?.width ?? 0
    }

    private func height(at w: CGFloat, slot: CGFloat?, _ subviews: Subviews) -> CGFloat {
        var natural: CGFloat?
        if live.size?.isFit == true, w > 0, let first = subviews.first {
            let n = first.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
            natural = n
            // Only the main thread's layout reports. SwiftUI also lays this out on its async render thread
            // (`com.apple.SwiftUI.AsyncRenderer`, animation frames): `assumeIsolated` trapped there (seam lab, a `.fit`
            // header's animated content change in the band, 27.0), and those frames lay out the presented state, while
            // the main thread's layout of the same update measures the model one.
            if Thread.isMainThread { MainActor.assumeIsolated { reporter.measured(n, width: w) } }
        }
        let container = slot.flatMap { $0.isFinite ? max(0, $0) : nil }
        return HeaderMath.liveHeight(width: w, containerHeight: container, natural: natural, live)
    }
}

/// 15 / forced: the same height from iOS 13 layout modifiers (no Layout protocol), one fixed structure for every size.
/// With the slot's `W × H` (`slot`, `HeaderSlotReader`, D78; every 15-path header has one):
/// - `.fixed`, `.aspectRatio` and a limited `R` (`.capped` / `.refit`, `min ≥ R`): the frame is `h_L(W, H)`
///   (`HeaderMath.liveHeight`, the formula of 16+'s `HeaderSlotLayout`) from the slot of this layout pass, so an
///   app-animated resize lays the header out at its final `R(W, H)` in the animated pass and the unanimated viewport
///   commit changes nothing in it (D51 / D62);
/// - `.fit`: two ideal-ratio boxes (`HeaderFallbackPlan.fitBox`) around the stack framed at `W` (its ideal height is
///   `N(W)`), less `m′` (`innerPad`), floored at `ε`, both with the ideal width `W / (1 − q)`, so each `aspectRatio(nil)`
///   takes its child's ideal ratio. The inner one, the measuring box, has the ratio `(W / (1 − q)) : (N(W) − m′)`; the
///   outer one, the layout box, clamps that ideal height at `L − m′` (the overflow limit; at the committed viewport never
///   below the committed `R − m′`: a runtime overflow change keeps the old `R` until the state commits the new one, as
///   16+), so its ratio is `(W / (1 − q)) : (R − m′)` with `R = min(N(W), L)` and it is `W` wide in both fits. In a resize's layout pass (the
///   slot is not the committed viewport) the layout box is fitted to the slot WIDTH: the stack is `(1 − q) · R + q · m′`,
///   16+'s live height from the content's fresh ideal height in the same pass. At the committed viewport
///   (`HeaderMath.isCommittedViewport`, 16+'s `layoutResting` rule) it is fitted to the live HEIGHT of the committed `R`
///   (`fixedSize(horizontal:)` drops the width proposal): the stack is laid out at 16+'s rect, a header content change
///   does not move it until the state commits the new `R` in the content's own transaction, and the boxes' widths carry
///   the measurement. The measuring box, proposed the layout box's size, keeps the unlimited ratio (a limited one is
///   narrower than `W`, the stack overflows it to the right) and reports the natural height `N(W)` through the leaf's
///   reporter (`noteBox`), unlimited, as 16+ does (the state applies the limit), so a later limit change resolves from the
///   same stored value on both paths. The limit is a clamp of the layout box's ratio, never a height proposal: a
///   `frame(idealHeight: (1 − q)(L − m′))` offering it to a single box (d89c745) drew an animated narrowing that left the
///   limit (402 → 241 pt, `.capped(0.25)`, half collapsed) at its final size in the first frame (hosted presentation
///   tree and seam lab: 29 pt seam, 160 pt lateral), though its layout was the same.
/// Without a slot (no reader above it, the plan's own tests), the committed plan of before D78:
/// - `.aspectRatio(r)` inside the band, its overflow limit inactive: the header stack fills a box proposed by
///   `.aspectRatio(r / (1 − p), .fit)` at the proposed width, extended by `p · min` (a negative inner padding gives the
///   stack the full live height, a positive outer one gives it to the frame), floored at `min`.
/// - `.fit` at rest (`p = 0`, its limit inactive; a `.stretch` pull too, D69: the stretch is the scale effect's): the
///   stack at its ideal height (`fixedSize(vertical:)`): the live height IS the ideal height there; reported
///   (preference, same update) so the state commits the same `R`.
/// - otherwise (`.fixed`, a band position of `.fit`, collapsed, an active overflow limit, the banner): the state's height.
/// The box's modifiers are neutral for every other plan (nil width, nil ideal width, nil limits, no fixed size, the
/// neutral ratio): only values change, never the structure, so the header keeps its identity. The final
/// `fixedSize(vertical:)` frees the box from the overlay's height (a landscape 16:9 header is taller than it).
nonisolated struct HeaderFallbackFrame: ViewModifier, Animatable {
    var live: HeaderLiveInput
    let state: ZTronScrollState
    /// D78: the header slot's `W × H` (`HeaderSlotReader`); `nil` without a reader (the committed plan).
    var slot: CGSize? = nil
    /// D78: the leaf's reporter (`HeaderFrameModifier`'s, the one 16+'s `HeaderSlotLayout` reports through): the `.fit`
    /// box reports `R` through it.
    var reporter: HeaderNaturalReporter? = nil

    /// The header offset `o′` (see `HeaderLiveInput.offset`): a transaction-driven scroll re-runs this body per frame. With
    /// the laid-out share `m` (D76), interpolated with the other four consumers in an animated `stretchContent:` change.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(live.offset, live.layoutShare) }
        set { live = live.at(offset: newValue.first); live.layoutShare = newValue.second }
    }

    @MainActor func body(content: Content) -> some View {
        let plan = HeaderFallbackPlan(live.pinned(.headerFallback), slot: slot)
        let state = state, reporter = reporter
        return content
            .fixedSize(horizontal: false, vertical: plan.fitRest)
            .background(Group {
                // Only at rest (no per-frame reader while the header collapses).
                if plan.fitRest {
                    GeometryReader { g in
                        Color.clear.preference(key: HeaderRestNaturalKey.self, value: HeaderRestNatural(size: g.size))
                    }
                }
            })
            // D76 (`.keepTextSize` pulled `.fit`): the stack's ideal width is the slot's `W` (`stackIdealWidth`), so the
            // boxes' ideal query measures `N(W)` while the stack is laid out at the grown width; `nil` otherwise.
            .frame(minWidth: 0, idealWidth: plan.stackIdealWidth, maxWidth: .infinity, minHeight: plan.minHeight,
                   maxHeight: plan.maxHeight, alignment: .top)
            // D78, the `.fit` box: the stack laid out (and asked for its ideal height) at the slot width.
            .frame(width: plan.stackWidth)
            // D76 pulled `.fit`, a resize's layout pass: the stack proposed the grown rect around the rest box's.
            .padding(.horizontal, -plan.growPadH)
            .padding(.bottom, -plan.growPadBottom)
            .padding(.bottom, plan.innerPad)
            // The measuring box (the content's own ratio, unlimited; neutral for every other plan). D76 pulled `.fit`: its
            // width clamped to the grown `W · s_l` (`boxMinWidth` = `boxMaxWidth`; an ideal query passes through it
            // unclamped), so the stack is laid out at exactly the grown width whatever the content's ratio.
            .frame(minWidth: plan.boxMinWidth, idealWidth: plan.boxIdealWidth, maxWidth: plan.boxMaxWidth,
                   minHeight: plan.boxFloor, maxHeight: plan.fitBox ? .infinity : nil, alignment: .topLeading)
            .aspectRatio(plan.ratio, contentMode: .fit)
            .background(Group {
                // The box's own size, while there is a box: per frame while a `.fit` header collapses (the leaf's
                // per-frame layout, the cost class of 16+'s `HeaderSlotLayout`); it reports only a change of `R`.
                if plan.fitBox && !plan.measuresLayoutBox {
                    GeometryReader { g in
                        let _ = HeaderFallbackFrame.noteBox(g.size, plan: plan, reporter: reporter)
                        Color.clear
                    }
                }
            })
            // The layout box: the same ideal width, its ideal height clamped at `L − m′` (the overflow limit), so it is `W`
            // wide at `R = min(N, L)` and proposes the measuring box its size (top leading: a limited measuring box is
            // narrower). Neutral for every other plan (the plan's ratio again: the aspect plan's box fits it exactly, the
            // neutral ratio keeps the child's size). D76 pulled `.fit`: centred (the clamped measuring box is centred in it,
            // on the slot's centre), and it carries the measurement (`measuresLayoutBox`).
            .frame(minWidth: 0, idealWidth: plan.boxIdealWidth, maxWidth: .infinity, minHeight: plan.boxFloor,
                   maxHeight: plan.fitBox ? (plan.boxLimit ?? .infinity) : nil, alignment: plan.boxAlignment)
            .background(Group {
                if plan.measuresLayoutBox {
                    GeometryReader { g in
                        let _ = HeaderFallbackFrame.noteBox(g.size, plan: plan, reporter: reporter)
                        Color.clear
                    }
                }
            })
            .aspectRatio(plan.ratio, contentMode: .fit)
            // At the committed viewport the layout box takes its ideal ratio at the live height (no width proposal). Both
            // fits are re-framed at the slot width, top leading (D76 pulled `.fit`: centred); neutral otherwise.
            .fixedSize(horizontal: plan.boxFitsHeight, vertical: false)
            .frame(width: plan.boxWidth, height: plan.boxHeight, alignment: plan.boxAlignment)
            .padding(.bottom, plan.outerPad)
            .frame(minHeight: plan.floor, alignment: .top)
            // D76 (`.keepTextSize`, non-`.fit`): the stack is proposed the grown `W · s_l` and overflows the slot-wide
            // frame by `sidePad` on each side, centred (the chrome's frame stays `W`; its clip cuts the sides).
            .padding(.horizontal, -plan.sidePad)
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(HeaderRestNaturalKey.self) { r in
                guard let r, r.size.width > 0 else { return }
                // The same update: the state's `R` follows the layout's (a rotation's commit then holds both, the content's
                // inset moves with the header). A header content change animated by the app: in its own transaction (the
                // frame IS the stack's ideal height here, so it already follows that animation; review d16: the inset
                // landed at once, unanimated, 150 pt).
                MainActor.assumeIsolated {
                    state.adoptHeaderNatural(r.size.height, measuredInTurn: state.headerTurn, unanimated: true)
                }
            }
    }

    /// D78: the `.fit` measuring box's laid-out size reports the natural height `N`. Whichever side the layout box was
    /// fitted to (and whether the limit clamped it), the measuring box keeps its child's ideal ratio
    /// `(W / (1 − q)) : (N − m′)`, so `N = (W / (1 − q)) · height / width + m′` (unlimited: `height / (1 − q) + m′`; a
    /// limited one is narrower than `W`). Reported like 16+ (`HeaderNaturalReporter.measured(_:width:)` at the slot
    /// width: recorded synchronously for the viewport commit of the same update, delivered at the next run-loop turn in
    /// the content's captured transaction otherwise; dedupes at 0.5 pt). Main thread only (SwiftUI also lays out on its
    /// asynchronous renderer, as for `HeaderSlotLayout`). `true` when it reported.
    @discardableResult
    static func noteBox(_ size: CGSize, plan: HeaderFallbackPlan, reporter: HeaderNaturalReporter?) -> Bool {
        guard plan.fitBox, let reporter, let ideal = plan.measureWidth, size.width > 0, size.width.isFinite,
              size.height >= 0, size.height.isFinite, Thread.isMainThread else { return false }
        let r = ideal * size.height / size.width + plan.boxMin
        guard r.isFinite else { return false }
        let width = plan.boxWidth ?? size.width
        MainActor.assumeIsolated {
            #if DEBUG
            ZTronRenderCounters.event("box fit \(plan.boxFitsHeight ? "h" : "w") "
                                      + String(format: "%.6fx%.9f q %.6f R %.4f", size.width, size.height, plan.boxProgress, r))
            #endif
            reporter.measured(r, width: width)
        }
        return true
    }
}

/// The values `HeaderFallbackFrame` applies (pure, testable).
struct HeaderFallbackPlan: Equatable {
    var fitRest = false
    var minHeight: CGFloat?
    var maxHeight: CGFloat?
    /// Bottom padding inside the aspect box (negative: the content is proposed more than the box) and outside it.
    var innerPad: CGFloat = 0
    var outerPad: CGFloat = 0
    /// The aspect box's ratio. Outside the aspect case it must stay harmless: SwiftUI fits the ratio into the box it is
    /// placed in, so a ratio of 1 in a box of height 0 (a hidden header, or `.fit` before its first measurement) proposed
    /// the header content a width of 0 (`.fit` then measured nothing). A huge ratio keeps the full width as long as the
    /// box is at least `W / ratio` tall, hence also the floor on the fixed height. `nil` (D78's `.fit` box): the child's
    /// ideal ratio.
    static let neutralRatio: CGFloat = 1_000_000
    static let minimumHeight: CGFloat = 0.01
    var ratio: CGFloat? = neutralRatio
    var floor: CGFloat = 0
    /// D78, `.fit`'s ideal-ratio boxes (`HeaderFallbackFrame`): the stack framed at the slot width `boxWidth` (its ideal
    /// height is `N(W)`), less `m′` (`innerPad = −m′`, `boxMin = m′`), floored at `boxFloor = ε`, both boxes with the
    /// ideal width `boxIdealWidth = W / (1 − q)` (`q`: `boxProgress`); the layout box clamps the ideal height at
    /// `boxLimit = L − m′` (`nil`: no limit) and is fitted by `aspectRatio(nil)`: to the slot width in a resize's pass
    /// (the stack is proposed `(1 − q) · R + q · m′`), to the live height of the committed `R` at the committed viewport
    /// (`boxFitsHeight`, the box `boxHeight = h_L − m′` tall). `nil` / `false` / 0 for every other plan (neutral
    /// modifiers).
    var fitBox = false
    var boxWidth: CGFloat?
    var boxIdealWidth: CGFloat?
    var boxFloor: CGFloat?
    var boxLimit: CGFloat?
    var boxProgress: CGFloat = 0
    var boxMin: CGFloat = 0
    var boxFitsHeight = false
    var boxHeight: CGFloat?
    /// D78: the inner `frame(width:)` (the stack laid out, and asked, at the slot width): `boxWidth` at rest, `nil` for a
    /// D76 pulled `.fit` (see `init(grownBox:…)`).
    var stackWidth: CGFloat?
    /// D76, a pulled `.keepTextSize` `.fit` box (`init(grownBox:…)`): the stack's ideal width `W` (the boxes measure
    /// `N(W)`), the measuring box clamped to the grown width `W · s_l` (`boxMinWidth` = `boxMaxWidth`), the layout box
    /// centred and carrying the measurement (`measuresLayoutBox`; `measureWidth` = `W · s_l` is its ideal width). At rest
    /// and for every other plan: `nil`, 0 / ∞, `boxIdealWidth`, top leading, `false` (today's values).
    var stackIdealWidth: CGFloat?
    var boxMinWidth: CGFloat = 0
    var boxMaxWidth: CGFloat = .infinity
    var measureWidth: CGFloat?
    var boxAlignment: Alignment = .topLeading
    var measuresLayoutBox = false
    /// D76 (`.keepTextSize`, a non-`.fit` size): half the width the laid-out share adds (`HeaderMath.grownSidePad`), the
    /// stack's overflow on each side of the slot-wide frame (`.padding(.horizontal, −sidePad)`). 0 otherwise.
    var sidePad: CGFloat = 0
    /// D76 pulled `.fit` in a resize's layout pass (M8b-s8 s7): the stack's proposal grows by `2 · growPadH × growPadBottom`
    /// over the D78 rest box's (negative paddings between the stack and the box; 0 otherwise).
    var growPadH: CGFloat = 0
    var growPadBottom: CGFloat = 0
    /// `q ≤ 1 − boxEpsilon` (the ideal width stays finite at full collapse); `ε = boxFloorHeight` (a larger floor
    /// mis-measures `R − m′ < 100` at full collapse: the box is `(1 − q)(R − m′)` tall there).
    static let boxEpsilon: CGFloat = 1e-6
    static let boxFloorHeight: CGFloat = 1e-9

    /// `slot`: the header slot's `W × H` (`HeaderSlotReader`, D78); `nil`: the committed plan.
    init(_ live: HeaderLiveInput, slot: CGSize? = nil) {
        let h = max(live.stateHeight, Self.minimumHeight)
        // A banner (no vertical axis) too: its `p` and stretch are the state's, 0 unless zoomed content pans (D15).
        guard let m = live.metrics, let size = live.size else {
            minHeight = h; maxHeight = h
            return
        }
        // D76: the laid-out share of a `.stretch` pull (`.keepTextSize`; exactly 0 for `.keepTextMagnified`, whose plans
        // are D69 + D78 bit for bit).
        let gl = live.layoutStretch
        // D78: `R(W, H)` from the slot of this layout pass, as on 16+ (`HeaderSlotLayout`).
        if let slot, slot.width > 0, slot.width.isFinite {
            let H: CGFloat? = slot.height.isFinite && slot.height > 0 ? slot.height : nil
            if size.isFit {
                if gl > 0, let grown = HeaderFallbackPlan(grownBox: live, m: m, size: size, width: slot.width, height: H,
                                                          stretch: gl) {
                    self = grown
                    return
                }
                self = HeaderFallbackPlan(box: live, m: m, size: size, width: slot.width, height: H)
                return
            }
            let lh = Swift.max(HeaderMath.liveHeight(width: slot.width, containerHeight: H, natural: live.natural, live),
                               Self.minimumHeight)
            // D76: laid out at `h + g_l`, `W · s_l` wide (16+'s `HeaderMath.grownSize`), the overflow centred.
            minHeight = lh + gl; maxHeight = lh + gl
            sidePad = HeaderMath.grownSidePad(width: slot.width, layoutHeight: lh, stretch: gl)
            return
        }
        // Without a slot (the plan's own tests), a laid-out share grows the state's height at the committed width.
        if gl > 0 {
            minHeight = h + gl; maxHeight = h + gl
            sidePad = HeaderMath.grownSidePad(width: m.width, layoutHeight: h, stretch: gl)
            return
        }
        // `.slideBehind` (D68) lays the stack out at `R` whatever the progress (its translation is `HeaderTranslation`'s):
        // the plan of rest.
        let p = m.collapse.isSlideBehind ? 0 : min(max(live.progress, 0), 1)
        let c = p * m.band
        // The committed `R` is the size's own (no overflow limit, no `min ≥ R`): only then does `R` follow the width alone.
        let unlimited: Bool
        switch size {
        case let .aspectRatio(r, _): unlimited = r > 0 && r.isFinite && abs(m.resting - m.width / r) < 0.01
        case .fit: unlimited = live.natural.map { abs(m.resting - $0) < 0.01 } ?? false
        case .fixed: unlimited = true
        }
        switch size {
        case let .aspectRatio(r, _) where unlimited && m.band > 0 && p < 1:
            // (1 − p) · W / r from the aspect box, + p · min around it (D69: no stretch, it is drawn by the scale).
            let extra = p * m.min
            minHeight = 0; maxHeight = .infinity
            innerPad = -extra; outerPad = extra
            ratio = r / (1 - p)
            floor = (1 - p) * m.min + extra
        case .fit where unlimited && m.band > 0 && c < 0.5:
            // At rest (within the sub-point snap of the offset) or under a `.stretch` pull: the ideal height, trimmed by
            // that sub-point remainder; only when the overflow limit is not what sets `R` (the ideal height is the
            // committed one).
            fitRest = true
            outerPad = -c
            floor = m.min
        default:
            minHeight = h; maxHeight = h
        }
    }
}

extension HeaderFallbackPlan {
    /// D78, `.fit` with the slot `W × H`: the ideal-ratio box (see `HeaderFallbackFrame`). The overflow limit `L` is
    /// `HeaderMath.overflowLimit` at the slot's `H` (the committed container for a banner, whose limit is the committed
    /// one, D15), `m′ = min(min, L)` (0 under `.slideBehind`, which ignores `min`, D68), `q` the progress (0 under
    /// `.slideBehind`: the stack keeps `R`, `HeaderTranslation` moves it), below 1 so the ideal width stays finite. At the
    /// committed viewport the box is fitted to the live height of the committed `R`, `(1 − q)(R − m′)`: the same `q` as the
    /// width fit, so the resize's animated pass (width fit at the measured `R`) and the viewport commit (height fit at
    /// the committed `R`, the same value) lay the stack out at the same height, at full collapse too.
    fileprivate init(box live: HeaderLiveInput, m: HeaderMetrics, size: ZTronHeaderSize, width: CGFloat, height: CGFloat?) {
        let container = live.layoutDriven ? (height ?? live.committedContainer) : live.committedContainer
        let limit = HeaderMath.overflowLimit(live.overflow, containerHeight: container)
        let slide = m.collapse.isSlideBehind
        let spec = size.minimum
        let mm = slide ? 0 : Swift.min(Swift.max(0, spec.isFinite ? spec : 0), limit)
        let q = slide ? 0 : Swift.min(Swift.max(live.progress, 0), 1 - Self.boxEpsilon)
        fitBox = true
        boxWidth = width
        stackWidth = width
        minHeight = 0; maxHeight = .infinity
        innerPad = -mm
        boxFloor = Self.boxFloorHeight
        boxLimit = limit.isFinite ? Swift.max(limit - mm, Self.boxFloorHeight) : nil
        boxIdealWidth = width / (1 - q)
        measureWidth = boxIdealWidth
        ratio = nil
        outerPad = mm
        boxProgress = q
        boxMin = mm
        // 16+'s rule (`HeaderMath.layoutResting`): the committed viewport keeps the committed `R`; a resize's layout pass
        // follows the content's ideal height at the slot's width.
        if HeaderMath.isCommittedViewport(width: width, container: container, live) {
            let committed = HeaderMath.layoutResting(width: width, containerHeight: live.layoutDriven ? height : nil,
                                                     natural: live.natural, live)
            boxFitsHeight = true
            boxHeight = Swift.max((1 - q) * (committed.resting - mm), Self.boxFloorHeight)
            // The committed `R` stays the layout's until the state commits another, as 16+'s `layoutResting`: a runtime
            // overflow change lays the header out once with the old `R` above the new limit (the spec change commits
            // after that pass), so the clamp never cuts below it (it cut the stack to the new limit before the commit).
            if let l = boxLimit { boxLimit = Swift.max(l, committed.resting - mm) }
        }
    }
}

extension HeaderFallbackPlan {
    /// D76, a pulled `.keepTextSize` `.fit` header (`g_l > 0`, so `q = 0`): 16+'s grown rect, `W · s_l × (R + g_l)` with
    /// `R = HeaderMath.liveHeight(W, H)` (the committed `R` at the committed viewport, as 16+'s `layoutResting`: a header
    /// content change moves the header with the content's inset, in the state's commit, as at rest), measured in layout:
    /// - the stack's ideal width is `W` (`stackIdealWidth`) and nothing between it and the boxes fixes a width, so the
    ///   boxes' ideal query asks for `N(W)` (a flexible frame proposes its ideal width to an ideal query; i28 §2.5);
    /// - the measuring box is clamped to `W · s_l` wide (its min = max width; an ideal query passes through it
    ///   unclamped, its ideal size is `(W · s_l, N)`): the stack is laid out at exactly `W · s_l × (R + g_l)` whatever
    ///   the content's ratio;
    /// - the layout box is fitted to the height `R + g_l` (`boxFitsHeight`), so it is `(R + g_l) · W · s_l / N` wide; it
    ///   is centred in the slot-wide frame and the measuring box in it, so the stack overflows the frame by
    ///   `(s_l − 1) · W / 2` on each side, centred; the frame (what the chrome scales, clips and fades) is
    ///   `W × (R + g_l)`;
    /// - the layout box's size reports `N = W · s_l · height / width` (`measureWidth`), floored at `m′` by the measuring
    ///   box's floor, unlimited above: the rest box's report (`max(N, m′)`).
    /// At `g_l → 0` the stack's rect is the rest plan's (`W × R`). `nil` for a zero or non-finite height (the rest plan).
    fileprivate init?(grownBox live: HeaderLiveInput, m: HeaderMetrics, size: ZTronHeaderSize, width: CGFloat,
                      height: CGFloat?, stretch gl: CGFloat) {
        let h = HeaderMath.liveHeight(width: width, containerHeight: height, natural: live.natural, live)
        guard h > 0, h.isFinite, gl.isFinite else { return nil }
        let grown = HeaderMath.grownSize(width: width, layoutHeight: h, stretch: gl)
        let container = live.layoutDriven ? (height ?? live.committedContainer) : live.committedContainer
        // A resize's layout pass (M8b-s8 s7): the D78 rest box, width-fit, so the header follows the animated proposal
        // with the content (the height-fit below sized the header from the plan's constants, which SwiftUI draws final
        // from the first frame: the seam lab's forced `fit-rest-stretch-width-hold-ksize` drew a 90 pt seam and a 159 pt
        // lateral step). The stack is proposed `g_l` taller and `g_l · W / (N′ − m′)` wider than the rest box's child
        // (negative paddings), which keeps that child's ideal ratio `W : (N − m′)`, so `N` is measured as at rest; `N′`
        // is the natural height predicted at this width from the committed pair (exact for an aspect content). The frame
        // is `g_l` taller (`outerPad`).
        if !HeaderMath.isCommittedViewport(width: width, container: container, live) {
            var p = HeaderFallbackPlan(box: live, m: m, size: size, width: width, height: height)
            let n0 = live.natural ?? m.resting
            let predicted = m.width > 0 ? n0 * width / m.width : n0
            let core = Swift.max(predicted - p.boxMin, Self.boxFloorHeight)
            p.stackWidth = nil
            p.stackIdealWidth = width
            // No ideal width on the boxes: their ideal query reaches the stack's own (`W`), so `N(W)` is measured, not
            // the height at the grown width a concrete ideal width would propose through the paddings.
            p.boxIdealWidth = nil
            p.measureWidth = width
            p.growPadH = gl * width / (2 * core)
            p.growPadBottom = gl
            p.outerPad += gl
            self = p
            return
        }
        let limit = HeaderMath.overflowLimit(live.overflow, containerHeight: container)
        let spec = size.minimum
        let mm = m.collapse.isSlideBehind ? 0 : Swift.min(Swift.max(0, spec.isFinite ? spec : 0), limit)
        fitBox = true
        minHeight = 0; maxHeight = .infinity
        stackIdealWidth = width
        boxMinWidth = grown.width; boxMaxWidth = grown.width
        boxFloor = Swift.max(mm, Self.boxFloorHeight)
        ratio = nil
        measureWidth = grown.width
        measuresLayoutBox = true
        boxAlignment = .top
        boxFitsHeight = true
        boxWidth = width
        boxHeight = grown.height
    }
}

private struct HeaderRestNatural: Equatable {
    var size: CGSize
}

private struct HeaderRestNaturalKey: PreferenceKey {
    static let defaultValue: HeaderRestNatural? = nil
    static func reduce(value: inout HeaderRestNatural?, nextValue: () -> HeaderRestNatural?) { value = nextValue() ?? value }
}

/// The header's own layer group (17+ `geometryGroup()`, 15–16 `compositingGroup()`): its clip and frame are one layer
/// subtree that Core Animation interpolates by itself in a system rotation, inside the container's clip. A `let` flag fixed
/// at state creation (R6).
///
/// Decision 2026-10-27 (15–16: `compositingGroup()` over nothing, as for the content, `ContentLayerGroup`): the seam lab's
/// control without this group (17.5, an uncapped `.aspectRatio` header at rest, taller than the landscape viewport, rotation)
/// opened a 36.9 pt gap between the header and the content mid-rotation, 0.1 pt with it; the forced 15–16 lane with
/// `compositingGroup()` for both groups rotates rigidly (27.0 forced: `.aspectRatio` at rest |seam| ≤ 0.1 pt, `.fixed` half
/// collapsed ≤ 0.1 pt, lateral ≤ 0.3 pt). The same cost argument as the content's applies (offscreen only under an
/// ancestor's compositing effect); the header is small next to the content. Like the content's, the 15–16 group isolates
/// blend modes: a header child's `.blendMode` composites within the header and does not reach the content scrolled under
/// it (17+ `geometryGroup()` does not isolate). SPEC S10 "15–16 layer groups".
struct HeaderLayerGroup: ViewModifier {
    let useGeometryGroup: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useGeometryGroup, #available(iOS 17, *) {
            content.geometryGroup()
        } else {
            content.compositingGroup()
        }
    }
}

/// The content's interaction gate (D11) for the header, in its own leaf on `.phase` (so the frame leaf never wakes on a
/// phase edge): no press while the content moves without a finger or while a drag is recognized; a drag that starts on
/// a header button scrolls. This leaf holds the `.disabled` half (on the header content only), applied only while a drag
/// is recognized (D11 narrowed 2026-11-09: no disabled state during a deceleration or an app animation, as native); the
/// hit-testing half is `HeaderHitGate`, outside the header's layer group.
struct HeaderInteractionGate: ViewModifier {
    let state: ZTronScrollState
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.phase], of: storage) }
        return content.disabled(state.storage.isDragging)   // D11 narrowed (ruling 16.11.1)
    }
}

/// The hit-testing half of the header's gate (D11), in its own leaf on `.phase`, applied OUTSIDE the header's layer
/// group (`HeaderSlotReader`). Inside it, the flip at every motion's start and end made SwiftUI re-configure the header's
/// drawn layers (27.0: every header text's drawing layer re-displayed, twice per motion: on the first frame of a pull
/// and of its release, cost3-O; cost2-F with the engine). Above the group only the group changes. Same hit area:
/// everything it adds (background, fade) is never hit-testable.
struct HeaderHitGate: ViewModifier {
    let state: ZTronScrollState
    @StateObject private var relay = ChannelRelay()

    @MainActor static func blocked(_ storage: any StateStorage) -> Bool {
        (storage.phase == .decelerating || storage.phase == .animating) && !storage.isTracking || storage.isDragging
    }

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.phase], of: storage) }
        return content.allowsHitTesting(!Self.blocked(state.storage))
    }
}

/// D70, `fade:`: the header's fade, drawn per frame over the framed stack (in the chrome, inside the `.stretch` scale and
/// moved with the header) from the leaf's live input: the rest gradient crossfaded with the collapse one by the progress
/// (the covered fraction under `.slideBehind`) or with the pull one by `min(1, g / (R / 2))` (`HeaderFadeMath`). Its
/// animatable data is the header offset `o′`, like the slot's, so a transaction-driven scroll re-derives the crossfade
/// per frame in the same transaction and while a resize is open it is the intent's anchor (bit-stable across the
/// unanimated commit). The `content` placeholder (the user's header) is never re-evaluated: only the gradient leaf is.
/// The band ends at the frame's bottom (`.compress`) or at the content's top edge (`.slideBehind`, `R − (1 − k)·c` in
/// the stack's frame: a fraction `1 − (1 − k)·p` of it, whatever `R`).
///
/// The pull weight's `R` is the stack's own LAYOUT height (a pull means `p = 0`, so the frame is `R(W, H)` on every path
/// and in both modes; the `.stretch` scale comes after), read by a `GeometryReader` and animated by the gradient leaf
/// (`HeaderFadeGradient.layoutHeight`): an app-animated resize during a pull or a refresh hold interpolates it with the
/// drawn frame in the same transaction, and the unanimated commit changes nothing (the committed `R` stepped the weight
/// to the new size's in one frame, seam lab b4). A fade that draws nothing has no reader.
nonisolated struct HeaderFadeOverlay: ViewModifier, Animatable {
    var live: HeaderLiveInput
    let fade: ZTronHeaderFade?

    /// `o′` and the laid-out share `m` (D76).
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { live.effectData }
        set { live.effectData = newValue }
    }

    @MainActor func body(content: Content) -> some View {
        let live = live.pinned(.headerFade), fade = fade
        return content.overlay(Group {
            if HeaderFadeMath.draws(fade) {
                GeometryReader { g in
                    // D76: the resting `R` = the frame's height less the laid-out share (constant through a pull at a
                    // fixed width; `g.size.height` itself with `.keepTextMagnified`).
                    HeaderFadeGradient(live: live, fade: fade, layoutHeight: Self.restingHeight(g.size.height, live))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        })
    }

    /// D76: the pull weight's `R` from the stack's laid-out height (`h + g_l`): `max(0, h + g_l − g_l)`.
    static func restingHeight(_ layoutHeight: CGFloat, _ live: HeaderLiveInput) -> CGFloat {
        let l = live.layoutStretch
        return l == 0 ? layoutHeight : Swift.max(0, layoutHeight - l)
    }

    /// What the gradient leaf draws at `live` with the pull weight's `R` = `resting` (pure). `nil` exactly when the fade
    /// draws nothing in any state (no fade, or every state nil): the drawn structure is fixed per fade value, never by the
    /// scroll position or the metrics.
    static func drawing(_ live: HeaderLiveInput, _ fade: ZTronHeaderFade?, resting: CGFloat) -> HeaderFadeDrawing? {
        guard let layers = HeaderFadeMath.layers(fade: fade, progress: live.progress, pull: live.pull, resting: resting)
        else { return nil }
        let end = HeaderFadeMath.bandEnd(collapse: live.metrics?.collapse ?? .compress, progress: live.progress, layoutHeight: 1)
        return HeaderFadeDrawing(layers: layers, end: HeaderFadeMath.endPoint(bandEnd: end, frameHeight: 1))
    }

    /// `drawing(_:_:resting:)` with the committed `R` (what the layout height is at rest).
    static func drawing(_ live: HeaderLiveInput, _ fade: ZTronHeaderFade?) -> HeaderFadeDrawing? {
        drawing(live, fade, resting: live.metrics?.resting ?? 0)
    }
}

/// The fade's layers and the gradient's end point (its start is the frame's top centre).
struct HeaderFadeDrawing: Equatable {
    var layers: HeaderFadeLayers
    var end: UnitPoint
}

/// The fade's gradient leaf: the bottom layer and, for a fade whose states have different colors, the top one over it.
/// Animatable on the stack's layout height (the pull weight's `R`, see `HeaderFadeOverlay`): a size change in an animated
/// transaction interpolates it with the frame.
nonisolated struct HeaderFadeGradient: View, Animatable {
    let live: HeaderLiveInput
    let fade: ZTronHeaderFade?
    var layoutHeight: CGFloat

    var animatableData: CGFloat {
        get { layoutHeight }
        set { layoutHeight = newValue }
    }

    @MainActor var body: some View {
        let d = HeaderFadeOverlay.drawing(live, fade, resting: layoutHeight)
        let bottom = d?.layers.bottom.gradientStops ?? [], top = d?.layers.top?.gradientStops
        let end = d?.end ?? UnitPoint(x: 0.5, y: 1)
        return LinearGradient(stops: bottom, startPoint: UnitPoint(x: 0.5, y: 0), endPoint: end)
            .overlay(Group {
                if let top {
                    LinearGradient(stops: top, startPoint: UnitPoint(x: 0.5, y: 0), endPoint: end)
                }
            })
    }
}

/// `background:` (``ZTronHeaderBackground``, user decision 2026-10-26): fills the live frame behind the header content.
/// Built in the cold host body (never per frame), laid out by the live frame (it is the `.background` of the header
/// stack's filler, which the frame leaf proposes the live frame), hidden from accessibility and hit-testing.
struct HeaderBackgroundView: View {
    let background: ZTronHeaderBackground?
    /// The header content, for `.ambientBlur`: the same builder result, instantiated a second time here.
    let copy: AnyView

    var body: some View {
        Group {
            switch background?.kind {
            case let .ambientBlur(radius)?:
                // Filled with the content's own aspect ratio (its ideal size), centred, cropped to the frame, then blurred
                // with opaque edges (no clear halo at the frame's edges).
                // Its readers are cold (`ztronColdReaders`): a snapshot per cold change, never per frame.
                Color.clear
                    .overlay(copy.environment(\.ztronColdReaders, true).scaledToFill())
                    .clipped()
                    .blur(radius: ZTronHeaderBackground.blurRadius(radius), opaque: true)
            case let .frostedGlass(radius)?:
                Rectangle().fill(ZTronHeaderBackground.material(radius: radius))
            case let .color(color)?:
                color
            case let .view(view)?:
                view
            case nil:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
        // The whole subtree's accessibility is replaced by nothing (iOS 15): `accessibilityHidden` alone, even on an
        // ignoring element, left the ambient copy's own elements (a `.contain` container inside the header content)
        // exposed (measured in HeaderUITests: two header buttons).
        .accessibilityRepresentation { Color.clear.accessibilityHidden(true) }
        .accessibilityHidden(true)
    }
}
