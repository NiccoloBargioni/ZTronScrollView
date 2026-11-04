import SwiftUI

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

    @ViewBuilder
    func body(content: Content) -> some View {
        if state.usesLayoutProtocol, #available(iOS 16, *) {
            content.modifier(HeaderFrameModifier(state: state, size: size, overflow: overflow, fade: fade))
        } else {
            let state = state, size = size, overflow = overflow, fade = fade
            GeometryReader { proxy in
                content.modifier(HeaderFrameModifier(state: state, size: size, overflow: overflow, fade: fade,
                                                     slot: Self.noted(proxy.size)))
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
    /// 15 / forced: the slot's size (`HeaderSlotReader`); `nil` on 16+ (the layout's proposal) and without a reader.
    var slot: CGSize? = nil
    @StateObject private var relay = ChannelRelay()
    @StateObject private var reporter = HeaderNaturalReporter()

    @ViewBuilder
    func body(content: Content) -> some View {
        let live = wake()
        // The geometry's input (no fade pull): the slot, the frames and the effects never re-lay out for the fade.
        let shape = live.geometry
        let visible = shape.visibleHeight > 0.5
        let group = state.usesGeometryGroup
        let fade = fade
        // The layout half: 16+ `HeaderSlotLayout` (fills the overlay, places the header at its live frame), 15 / forced
        // `HeaderFallbackFrame`. The branch is a `let` flag fixed at state creation (R6): the identity never changes.
        if state.usesLayoutProtocol, #available(iOS 16, *) {
            HeaderSlotLayout(live: shape, reporter: reporter) {
                Self.chrome(content, live: live, fade: fade, visible: visible, group: group)
            }
        } else {
            Self.chrome(content.modifier(HeaderFallbackFrame(live: shape, state: state, slot: slot, reporter: reporter)),
                        live: live, fade: fade, visible: visible, group: group)
                .modifier(HeaderTranslation(live: shape))
                // The slot: the header at the top of the whole overlay. Without it a header exactly as tall as the
                // region between the safe areas was placed against the bottom safe area (34 pt low; measured).
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Subscribes (15–16 channels; 17+ tracks the reads below), counts the run and reads the state's half of the frame.
    private func wake() -> HeaderLiveInput {
        if let storage = state.storage as? ChannelStorage {
            relay.subscribe(to: [.target, .metrics], of: storage)
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
        // D79: after a drawn catch every effect that interpolates `o′` draws the model's until its interpolation reaches it.
        if live.followsOffset, let ref = state.catchPinRef { live.catchPin = HeaderCatchPin(ref: ref, model: live.offset) }
        return live
    }

    /// What the framed header carries on every path: the fade (D70, inside the scaled stack: it stretches with the
    /// header), the `.stretch` scale (D69), its own clip, its layer group and the gates. The `.preserve` translation is the
    /// layout's (16+ placement, 15 `HeaderTranslation`), animated with the header offset, and moves the fade with the
    /// header. The fade, the scale and the clip read the same `live` the leaf hands the slot in the same body (no frame
    /// lag) and interpolate `o′` in a transaction-driven scroll exactly as the slot does.
    static func chrome<V: View>(_ framed: V, live: HeaderLiveInput, fade: ZTronHeaderFade?, visible: Bool,
                                group: Bool) -> some View {
        framed
            .modifier(HeaderFadeOverlay(live: live, fade: fade))
            .modifier(HeaderStretchEffect(live: live.geometry))
            // The scaled stack (wider than W, taller by g) clipped to `W × h_L · s` in the unscaled frame: sides cut, the
            // bottom edge on the content's top; the frame itself when nothing stretches (`.clipped()` before D69).
            .clipShape(HeaderStretchClip(live: live.geometry))
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

/// D69: the `.stretch` growth as a render-time scale of the framed stack, anchored at its top centre: `s = (h + g) / h`
/// with `h` the stack's own LAYOUT height (`size`: the slot's `h_L(W, H)` on 16+, `HeaderFallbackFrame`'s on 15 / forced)
/// and `g = live.stretch`, so the scaled stack's bottom edge is `top + h + g`, the content's top, and an aspect-fit image
/// grows with the pull. Identity without a stretch. `size` is the layout's, not the state's: across an open resize `g` is
/// the intent's anchor and `h` the layout's own `R(W, H)`, so the unanimated commit changes nothing drawn; an app-animated
/// resize interpolates `h` with the drawn size. Its animatable data is the header offset `o′`, like `HeaderSlotLayout` /
/// `HeaderFallbackFrame`: a transaction-driven scroll re-derives `g` per frame in the same transaction.
nonisolated struct HeaderStretchEffect: GeometryEffect {
    var live: HeaderLiveInput

    var animatableData: CGFloat {
        get { live.offset }
        set { live = live.at(offset: newValue) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(Self.transform(size: size, stretch: live.pinned(.headerStretch).stretch))
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
nonisolated struct HeaderStretchClip: Shape {
    var live: HeaderLiveInput

    var animatableData: CGFloat {
        get { live.offset }
        set { live = live.at(offset: newValue) }
    }

    func path(in rect: CGRect) -> Path {
        Path(Self.rect(in: rect, stretch: live.pinned(.headerClip).stretch))
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

    var animatableData: CGFloat {
        get { live.offset }
        set { live = live.at(offset: newValue) }
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
/// layout has no area of its own). Its animatable data is the header offset `o′` (`HeaderLiveInput.offset`).
@available(iOS 16, *)
struct HeaderSlotLayout: Layout {
    var live: HeaderLiveInput
    let reporter: HeaderNaturalReporter

    var animatableData: CGFloat {
        get { live.offset }
        set { live = live.at(offset: newValue) }
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
        // The slot's size (C16: the 15 path's `HeaderSlotReader` notes the same key).
        if Thread.isMainThread {
            let note = "\(bounds.width)x\(bounds.height)"
            MainActor.assumeIsolated { ZTronRenderCounters.notes["header.slot.size"] = note }
        }
        #endif
        let h = height(at: bounds.width, slot: bounds.height, subviews)
        // `.slideBehind` (D68): up by `k · p · h` of this pass's own `h` (`R(W, H)`), as the 15 path's `HeaderTranslation`.
        let y = bounds.minY + HeaderTranslation.translation(live, layoutHeight: h)
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top,
                              proposal: ProposedViewSize(width: bounds.width, height: h))
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
/// - `.fit`: the ideal-ratio box (`HeaderFallbackPlan.fitBox`): the stack framed at `W` (its ideal height is `N(W)`), less
///   `m′` (`innerPad`), clamped to `[ε, L − m′]` and given the ideal width `W / (1 − q)`, so `aspectRatio(nil)` takes the
///   box's ideal ratio `(W / (1 − q)) : (R − m′)` with `R = clamp(N(W), m′, L)`. In a resize's layout pass (the slot is
///   not the committed viewport) it is fitted to the slot WIDTH: the stack is `(1 − q) · R + q · m′`, 16+'s live height
///   from the content's fresh ideal height in the same pass. At the committed viewport (`HeaderMath.isCommittedViewport`,
///   16+'s `layoutResting` rule) it is fitted to the live HEIGHT of the committed `R` (`fixedSize(horizontal:)` drops the
///   width proposal): the stack is laid out at 16+'s rect, a header content change does not move it until the state
///   commits the new `R` in the content's own transaction, and the box's width carries the measurement. Both fits report
///   `R` through the leaf's reporter (`noteBox`), as 16+ does.
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

    /// The header offset `o′` (see `HeaderLiveInput.offset`): a transaction-driven scroll re-runs this body per frame.
    var animatableData: CGFloat {
        get { live.offset }
        set { live = live.at(offset: newValue) }
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
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: plan.minHeight, maxHeight: plan.maxHeight, alignment: .top)
            // D78, the `.fit` box: the stack laid out (and asked for its ideal height) at the slot width.
            .frame(width: plan.boxWidth)
            .padding(.bottom, plan.innerPad)
            .frame(minWidth: 0, idealWidth: plan.boxIdealWidth, maxWidth: .infinity, minHeight: plan.boxFloor,
                   maxHeight: plan.boxLimit, alignment: .topLeading)
            .aspectRatio(plan.ratio, contentMode: .fit)
            .background(Group {
                // The box's own size, while there is a box: per frame while a `.fit` header collapses (the leaf's
                // per-frame layout, the cost class of 16+'s `HeaderSlotLayout`); it reports only a change of `R`.
                if plan.fitBox {
                    GeometryReader { g in
                        let _ = HeaderFallbackFrame.noteBox(g.size, plan: plan, reporter: reporter)
                        Color.clear
                    }
                }
            })
            // At the committed viewport the box takes its ideal ratio at the live height (no width proposal), re-framed at
            // the slot width; otherwise both are neutral.
            .fixedSize(horizontal: plan.boxFitsHeight, vertical: false)
            .frame(width: plan.boxFitsHeight ? plan.boxWidth : nil, height: plan.boxHeight, alignment: .topLeading)
            .padding(.bottom, plan.outerPad)
            .frame(minHeight: plan.floor, alignment: .top)
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

    /// D78: the `.fit` box's laid-out size reports `R`. Whichever side the box was fitted to, it keeps its child's ideal
    /// ratio `(W / (1 − q)) : (R − m′)`, so `R = (W / (1 − q)) · height / width + m′` (the width fit: `height / (1 − q) +
    /// m′`; the height fit: `1 − q` cancels). Reported like 16+ (`HeaderNaturalReporter.measured(_:width:)` at the slot
    /// width: recorded synchronously for the viewport commit of the same update, delivered at the next run-loop turn in
    /// the content's captured transaction otherwise; dedupes at 0.5 pt). Main thread only (SwiftUI also lays out on its
    /// asynchronous renderer, as for `HeaderSlotLayout`). `true` when it reported.
    @discardableResult
    static func noteBox(_ size: CGSize, plan: HeaderFallbackPlan, reporter: HeaderNaturalReporter?) -> Bool {
        guard plan.fitBox, let reporter, let ideal = plan.boxIdealWidth, size.width > 0, size.width.isFinite,
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
    /// D78, `.fit`'s ideal-ratio box (`HeaderFallbackFrame`): the stack framed at the slot width `boxWidth` (its ideal
    /// height is `N(W)`), less `m′` (`innerPad = −m′`, `boxMin = m′`), its height clamped to `[boxFloor, boxLimit]` =
    /// `[ε, L − m′]`, its ideal width `boxIdealWidth = W / (1 − q)` (`q`: `boxProgress`), fitted by `aspectRatio(nil)`:
    /// to the slot width in a resize's pass (the stack is proposed `(1 − q) · R + q · m′`), to the live height of the
    /// committed `R` at the committed viewport (`boxFitsHeight`, the box `boxHeight = h_L − m′` tall). `nil` / `false`
    /// / 0 for every other plan (neutral modifiers).
    var fitBox = false
    var boxWidth: CGFloat?
    var boxIdealWidth: CGFloat?
    var boxFloor: CGFloat?
    var boxLimit: CGFloat?
    var boxProgress: CGFloat = 0
    var boxMin: CGFloat = 0
    var boxFitsHeight = false
    var boxHeight: CGFloat?
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
        // D78: `R(W, H)` from the slot of this layout pass, as on 16+ (`HeaderSlotLayout`).
        if let slot, slot.width > 0, slot.width.isFinite {
            let H: CGFloat? = slot.height.isFinite && slot.height > 0 ? slot.height : nil
            if size.isFit {
                self = HeaderFallbackPlan(box: live, m: m, size: size, width: slot.width, height: H)
                return
            }
            let lh = Swift.max(HeaderMath.liveHeight(width: slot.width, containerHeight: H, natural: live.natural, live),
                               Self.minimumHeight)
            minHeight = lh; maxHeight = lh
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
        minHeight = 0; maxHeight = .infinity
        innerPad = -mm
        boxFloor = Self.boxFloorHeight
        boxLimit = limit.isFinite ? Swift.max(limit - mm, Self.boxFloorHeight) : nil
        boxIdealWidth = width / (1 - q)
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
        }
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

    var animatableData: CGFloat {
        get { live.offset }
        set { live = live.at(offset: newValue) }
    }

    @MainActor func body(content: Content) -> some View {
        let live = live.pinned(.headerFade), fade = fade
        return content.overlay(Group {
            if HeaderFadeMath.draws(fade) {
                GeometryReader { g in
                    HeaderFadeGradient(live: live, fade: fade, layoutHeight: g.size.height)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        })
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
