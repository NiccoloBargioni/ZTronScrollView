import SwiftUI

/// The header's hot leaf (design M8b §2.3, the `TransformHost` pattern of D10): its OWN body reads the target offset and
/// the metrics and frames its `content` placeholder (the cold header stack: the user's header, its background and fade,
/// built by `HeaderHost`) at the live frame. SwiftUI does not re-evaluate the placeholder when this body re-runs; it lays
/// it out again at the new proposal, a layout pass over the header subtree only. It wakes on `.target` (presentation
/// writes never wake it): under a transaction it runs once inside the transaction, and finger and clock motion write the
/// target every frame, so it then runs per frame.
///
/// The geometry comes from LAYOUT (M8b-3 seamless header, seam spike A), so the header moves with the content in every
/// animation: its slot's top edge is placed by SwiftUI (the overlay is attached after the container's `.ignoresSafeArea`,
/// so it starts at the safe-area top), its height is `(1 − p) · R(W, H) + p · min + stretch` with `W × H` the proposed
/// size and `R(W, H)` resolved in the same layout pass as the container (size and overflow policy, exactly as the state
/// resolves it; 16+: `HeaderFrameLayout`, 15 / forced: `HeaderFallbackFrame`), and `p`, the stretch and the `.preserve`
/// translation come from the state. An animated resize then interpolates the header with the content; the unanimated
/// resize commit changes nothing in the header while the progress is kept (D51).
struct HeaderFrameModifier: ViewModifier {
    let state: ZTronScrollState
    let size: ZTronHeaderSize
    let overflow: ZTronHeaderOverflow
    @StateObject private var relay = ChannelRelay()
    @StateObject private var reporter = HeaderNaturalReporter()

    @ViewBuilder
    func body(content: Content) -> some View {
        let live = wake()
        let visible = live.stateHeight > 0.5
        let group = state.usesGeometryGroup
        // The layout half: 16+ `HeaderSlotLayout` (fills the overlay, places the header at its live frame), 15 / forced
        // `HeaderFallbackFrame`. The branch is a `let` flag fixed at state creation (R6): the identity never changes.
        if state.usesLayoutProtocol, #available(iOS 16, *) {
            HeaderSlotLayout(live: live, reporter: reporter) {
                Self.chrome(content, live: live, visible: visible, group: group)
            }
        } else {
            Self.chrome(content.modifier(HeaderFallbackFrame(live: live, state: state)), live: live, visible: visible,
                        group: group)
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
                                  target: storage.targetOffset, zoom: zoom)
        live.natural = state.headerNatural
        return live
    }

    /// What the framed header carries on every path: its own clip, its layer group, the gates and the translation.
    static func chrome<V: View>(_ framed: V, live: HeaderLiveInput, visible: Bool, group: Bool) -> some View {
        framed
            .clipped()
            // The header's own clip in its own layer group: Core Animation then interpolates it as the header's frame, not
            // pre-intersected with the container's clip (an uncapped header taller than the landscape viewport drew its
            // bottom edge at the container's clip, 40 pt above the content's top, all through a rotation).
            .modifier(HeaderLayerGroup(useGeometryGroup: group))
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            // `.preserve` under a pull: the header moves down with the content (render-time; the gap opens above it).
            .offset(y: live.translation)
    }

    /// The state's half of the live frame. Bit-stability is the point: the animated layout pass of an app-driven resize lays
    /// the header out with the values of the last render, then the unanimated commit re-renders this leaf; any change in
    /// the layout's result there, even an ulp, re-sets the header's frame WITHOUT animation (the whole in-flight width /
    /// height change jumps to its end). So:
    /// - while a resize is open, the progress, stretch and translation are the resize intent's anchor (captured from the
    ///   same target offset), not re-derived from the realised target (ulps apart);
    /// - no pixel snap of the offset here (the intent is captured unsnapped): at rest the header's edge and the content's
    ///   snapped top can differ by a sub-pixel amount instead.
    static func liveInput(size: ZTronHeaderSize, overflow: ZTronHeaderOverflow, metrics m: ScrollMetrics, edges: Edge.Set,
                          target: CGPoint, zoom: CGFloat) -> HeaderLiveInput {
        guard let header = m.header else { return HeaderLiveInput(size: size, overflow: overflow, metrics: nil) }
        var p: CGFloat = 0, stretch: CGFloat = 0, translation: CGFloat = 0
        if header.vertical, m.resize.isOpen, let anchor = m.resize.intent?.header {
            switch anchor {
            case let .top(x):
                let g = max(0, -x)
                if header.behavior == .stretch { stretch = g } else { translation = g }
            case let .progress(q): p = q
            case .collapsed: p = header.band > 0 ? 1 : 0
            }
        } else {
            let o = HeaderMath.headerOffset(offset: target, zoom: zoom, metrics: m)
            let g = HeaderMath.geometry(o: o, m: header)
            p = g.progress
            stretch = g.stretch
            translation = HeaderMath.translation(o: o, m: header)
        }
        let h = max(0, header.resting - p * header.band + stretch)
        return HeaderLiveInput(size: size, overflow: overflow, metrics: header, progress: p, stretch: stretch,
                               translation: translation, stateHeight: h,
                               bottomInset: edges.contains(.bottom) ? max(0, m.safeAreaInsets.bottom) : 0,
                               committedContainer: HeaderMath.containerHeight(viewport: m.viewportSize, safe: m.safeAreaInsets,
                                                                              adjusted: edges))
    }
}

/// 16+: the header's SLOT, the overlay below the safe-area top (`W × H`). It takes the whole proposal (so its size never
/// depends on its own result: a parent that proposes a child its own size again gets the same answer) and places the
/// header at its top with the live frame `(W, h(W, H))` (`HeaderMath.liveHeight`; `H` minus the adjusted safe-area bottom
/// is the overflow container, exactly the state's). The header stack is proposed the live frame (sticky overlays, the
/// background). `.fit` measures the ideal height at `W` here and records it synchronously, so the viewport commit of the
/// same update adopts it. Only the header is hit-tested (a layout has no area of its own).
@available(iOS 16, *)
struct HeaderSlotLayout: Layout {
    let live: HeaderLiveInput
    let reporter: HeaderNaturalReporter

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = width(proposal)
        if let h = proposal.height, h.isFinite { return CGSize(width: w, height: max(0, h)) }
        // An ideal-size query: the header's own height against the committed container.
        return CGSize(width: w, height: height(at: w, slot: nil, subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let h = height(at: bounds.width, slot: bounds.height, subviews)
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
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
            MainActor.assumeIsolated { reporter.measured(n, width: w) }
        }
        let container = slot.flatMap { $0.isFinite ? max(0, $0 - live.bottomInset) : nil }
        return HeaderMath.liveHeight(width: w, containerHeight: container, natural: natural, live)
    }
}

/// 15 / forced: the same height from iOS 13 layout modifiers (no Layout protocol), one fixed structure for every size:
/// - `.aspectRatio(r)` inside the band, its overflow limit inactive: the header stack fills a box proposed by
///   `.aspectRatio(r / (1 − p), .fit)` at the proposed width, extended by `p · min + stretch` (a negative inner padding
///   gives the stack the full live height, a positive outer one gives it to the frame), floored at `min + stretch`.
/// - `.fit` at rest (`p = 0`, no stretch, its limit inactive): the stack at its ideal height (`fixedSize(vertical:)`): the
///   live height IS the ideal height there; reported (preference, same update) so the state commits the same `R`.
/// - otherwise (`.fixed`, a band position of `.fit`, collapsed, stretched `.fit`, an active overflow limit, the banner):
///   the state's height (`.fixed` and a limited `R` do not depend on the width; documented: a `.fit` inside the band keeps
///   a commit-time step on an app-driven resize on this path).
/// The final `fixedSize(vertical:)` frees the box from the overlay's height (a landscape 16:9 header is taller than it).
struct HeaderFallbackFrame: ViewModifier {
    let live: HeaderLiveInput
    let state: ZTronScrollState

    func body(content: Content) -> some View {
        let plan = HeaderFallbackPlan(live)
        let state = state
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
            .padding(.bottom, plan.innerPad)
            .aspectRatio(plan.ratio, contentMode: .fit)
            .padding(.bottom, plan.outerPad)
            .frame(minHeight: plan.floor, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .onPreferenceChange(HeaderRestNaturalKey.self) { r in
                guard let r, r.size.width > 0 else { return }
                // The same update: the state's `R` follows the layout's (a rotation's commit then holds both, the
                // content's inset moves with the header).
                MainActor.assumeIsolated { state.unanimated { state.setHeaderNatural(r.size.height) } }
            }
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
    /// box is at least `W / ratio` tall, hence also the floor on the fixed height.
    static let neutralRatio: CGFloat = 1_000_000
    static let minimumHeight: CGFloat = 0.01
    var ratio: CGFloat = neutralRatio
    var floor: CGFloat = 0

    init(_ live: HeaderLiveInput) {
        let h = max(live.stateHeight, Self.minimumHeight)
        guard let m = live.metrics, live.layoutDriven, let size = live.size else {
            minHeight = h; maxHeight = h
            return
        }
        let p = min(max(live.progress, 0), 1)
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
            // (1 − p) · W / r from the aspect box, + p · min + stretch around it.
            let extra = p * m.min + live.stretch
            minHeight = 0; maxHeight = .infinity
            innerPad = -extra; outerPad = extra
            ratio = r / (1 - p)
            floor = (1 - p) * m.min + extra
        case .fit where unlimited && m.band > 0 && c < 0.5 && live.stretch < 0.5:
            // At rest (within the sub-point snap of the offset): the ideal height, trimmed by that sub-point remainder;
            // only when the overflow limit is not what sets `R` (the ideal height is the committed one).
            fitRest = true
            outerPad = live.stretch - c
            floor = m.min
        default:
            minHeight = h; maxHeight = h
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

/// The header's own layer group (17+ `geometryGroup()`, 15–16 `compositingGroup()`; see `ContentLayerGroup` for the
/// choice): its clip and frame are one layer subtree that Core Animation interpolates by itself in a system rotation,
/// inside the container's clip. A `let` flag fixed at state creation (R6).
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
                Color.clear
                    .overlay(copy.scaledToFill())
                    .clipped()
                    .blur(radius: max(0, radius.isFinite ? radius : 0), opaque: true)
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
