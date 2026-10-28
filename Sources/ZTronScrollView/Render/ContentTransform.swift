import SwiftUI
import ZTronScrollPhysics

/// Pixel snapping (the alignment padding and visible center live in `ResizeMath`).
enum ContentGeometry {
    static func snap(_ v: CGFloat, scale: CGFloat) -> CGFloat {
        scale > 0 ? (v * scale).rounded() / scale : v
    }
}

/// The seven animatable scalars of `ContentTransform`.
struct TransformVector: VectorArithmetic {
    var ox: CGFloat = 0, oy: CGFloat = 0, s: CGFloat = 0
    var top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0

    static var zero: TransformVector { TransformVector() }
    static func + (l: Self, r: Self) -> Self {
        Self(ox: l.ox + r.ox, oy: l.oy + r.oy, s: l.s + r.s, top: l.top + r.top, leading: l.leading + r.leading,
             bottom: l.bottom + r.bottom, trailing: l.trailing + r.trailing)
    }
    static func - (l: Self, r: Self) -> Self {
        Self(ox: l.ox - r.ox, oy: l.oy - r.oy, s: l.s - r.s, top: l.top - r.top, leading: l.leading - r.leading,
             bottom: l.bottom - r.bottom, trailing: l.trailing - r.trailing)
    }
    mutating func scale(by rhs: Double) {
        let k = CGFloat(rhs)
        ox *= k; oy *= k; s *= k; top *= k; leading *= k; bottom *= k; trailing *= k
    }
    var magnitudeSquared: Double {
        Double(ox * ox + oy * oy + s * s + top * top + leading * leading + bottom * bottom + trailing * trailing)
    }
}

/// One effect: x_v = s * x_c + pad - o. A pure function of its animatable data (offset, scale, insets), the viewport
/// `size` it is asked about, and the committed resize data, so it interpolates under any transaction and doubles as the
/// presentation probe (design M2 section 6, M5 section 3). `pad` is derived from the drawn geometry, never animated.
/// Fast path (no resize in flight, `size` is the committed viewport): the plain matrix of the target values.
struct ContentTransform: GeometryEffect {
    var offset: CGPoint
    var scale: CGFloat
    var insets: EdgeInsets
    let commit: ResizeCommit
    let limits: ZoomLimits
    let alignment: UnitPoint
    let paging: Axis.Set
    let probe: PresentationBox?

    var animatableData: TransformVector {
        get { TransformVector(ox: offset.x, oy: offset.y, s: scale, top: insets.top, leading: insets.leading,
                              bottom: insets.bottom, trailing: insets.trailing) }
        set {
            offset = CGPoint(x: newValue.ox, y: newValue.oy)
            scale = newValue.s
            insets = EdgeInsets(top: newValue.top, leading: newValue.leading, bottom: newValue.bottom, trailing: newValue.trailing)
        }
    }

    static func matrix(offset: CGPoint, scale: CGFloat, pad: CGPoint) -> CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: pad.x - offset.x, ty: pad.y - offset.y)
    }

    /// Same geometry within a pixel. SwiftUI hands the effect a pixel-rounded `size` while the committed viewport is the
    /// unrounded layout size (a 16:9 box of 288.125 pt draws at 288.0), so an exact comparison would send every frame
    /// at rest down the resize path, whose result is clamped: no rubber band or bounce could ever be drawn and the
    /// presentation probe would never settle a transaction (D21). A real resize moves by far more than a point.
    static let pixelTolerance: CGFloat = 1
    private static func near(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) <= pixelTolerance && abs(a.height - b.height) <= pixelTolerance
    }
    private static func near(_ a: EdgeInsets, _ b: EdgeInsets) -> Bool {
        abs(a.top - b.top) <= pixelTolerance && abs(a.leading - b.leading) <= pixelTolerance
            && abs(a.bottom - b.bottom) <= pixelTolerance && abs(a.trailing - b.trailing) <= pixelTolerance
    }

    /// Fast path: the viewport is not known yet, or no resize is in flight and `size`/`insets` are the committed
    /// geometry (within a pixel). Then the target is drawn as is, overscroll included.
    func isPlainFrame(size: CGSize) -> Bool {
        let cur = commit.current
        return cur.viewport.width <= 0 || cur.viewport.height <= 0
            || (!commit.isOpen && Self.near(size, cur.viewport) && Self.near(insets, cur.insets))
    }

    /// (offset, scale, pad) drawn at `size`.
    func resolved(size: CGSize) -> (offset: CGPoint, scale: CGFloat, pad: CGPoint) {
        let cur = commit.current
        if isPlainFrame(size: size) {
            let v = cur.viewport.width <= 0 || cur.viewport.height <= 0 ? size : cur.viewport
            let g = ResizeMath.geometry(viewport: v, content: cur.contentSize, insets: insets, alignment: alignment)
            return (offset, scale, g.alignmentPadding(at: scale))
        }
        return ResizeMath.resolve(size: size, offset: offset, scale: scale, insetsAnimated: insets, commit: commit,
                                  limits: limits, alignment: alignment, paging: paging)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let r = resolved(size: size)
        probe?.record(r.offset, r.scale, size: size)
        #if DEBUG
        if Thread.isMainThread {
            let open = commit.isOpen
            // Draw-path probe: which path drew this frame, and whether a closed commit still clamped the target away
            // (an overscroll or bounce the user never sees).
            let cur = commit.current
            let fast = isPlainFrame(size: size)
            let clampedAway = !open && hypot(r.offset.x - offset.x, r.offset.y - offset.y) > 0.5
            MainActor.assumeIsolated {
                ZTronRenderCounters.increment(fast ? "transform.fast" : "transform.slow")
                if !fast, !open {
                    ZTronRenderCounters.increment("transform.slowClosed")
                    ZTronRenderCounters.notes["transform.slow"] =
                        "size=\(size) vp=\(cur.viewport) insets=\(insets) cur=\(cur.insets)"
                }
                if clampedAway {
                    ZTronRenderCounters.increment("transform.clampedAtRest")
                    ZTronRenderCounters.notes["transform.clampedAtRest"] =
                        "target=\(offset) drawn=\(r.offset) size=\(size) vp=\(cur.viewport) insets=\(insets) cur=\(cur.insets)"
                }
            }
            let p = open ? ResizeMath.presented(commit, size: size) : commit.current
            let snap = ResizeCommit.Snapshot(viewport: size, contentSize: p.contentSize, insets: insets)
            let n = ResizeMath.intent(offset: r.offset, scale: r.scale, in: snap, header: commit.header, focus: commit.focus,
                                      alignment: alignment).normalizedCenter
            MainActor.assumeIsolated {
                ZTronRenderCounters.increment("transform.effect")
                ResizeJumpMonitor.record(size: size, normalized: n, content: p.contentSize, scale: r.scale, resizing: open)
            }
        }
        #endif
        return ProjectionTransform(Self.matrix(offset: r.offset, scale: r.scale, pad: r.pad))
    }
}

#if DEBUG
/// DEBUG `resize.jumpFrames` (design M5 section 10): a DRAWN frame during a viewport resize (size changed since the
/// previous drawn frame, or the resize commit is open) whose visible-centre content point, normalized to the content
/// size drawn in that frame (D16: reflowing content keeps its normalized centre), moved by more than 1 viewport point.
/// Only the last effect evaluation of a run-loop turn reaches the screen (Core Animation commits once per turn), so an
/// evaluation superseded in the same turn — the new viewport size evaluated before the same turn's reflowed content
/// size lands (iOS 17.5) — is not a frame and is not counted. Content clamped at an edge legitimately counts.
@MainActor
enum ResizeJumpMonitor {
    private struct Eval { var size: CGSize; var n: CGPoint; var content: CGSize; var scale: CGFloat; var resizing: Bool; var desc: String }
    /// The last evaluation of the previous turn (what is on screen) and the latest one of this turn.
    private static var drawn: Eval?
    private static var current: Eval?
    private static var hopPending = false

    static func record(size: CGSize, normalized n: CGPoint, content: CGSize, scale: CGFloat, resizing: Bool) {
        let desc = String(format: "size=%.0fx%.0f k=%.0fx%.0f n=%.4f,%.4f s=%.3f open=%d",
                          size.width, size.height, content.width, content.height, n.x, n.y, scale, resizing ? 1 : 0)
        current = Eval(size: size, n: n, content: content, scale: scale, resizing: resizing, desc: desc)
        guard !hopPending else { return }
        hopPending = true
        DispatchQueue.main.async { MainActor.assumeIsolated { endOfTurn() } }
    }

    /// The turn ended: `current` is the drawn frame; compare it with the previous one.
    private static func endOfTurn() {
        hopPending = false
        guard let c = current else { return }
        defer { drawn = c; current = nil }
        guard let d = drawn else { return }
        let sizeChanged = abs(d.size.width - c.size.width) > 0.01 || abs(d.size.height - c.size.height) > 0.01
        guard sizeChanged || c.resizing else { return }
        if hypot((c.n.x - d.n.x) * c.content.width, (c.n.y - d.n.y) * c.content.height) * c.scale > 1 {
            ZTronRenderCounters.increment("resize.jumpFrames")
            ZTronRenderCounters.notes["resize.jump"] = "[\(d.desc)] -> [\(c.desc)]"
        }
    }
}
#endif

/// Reads the TARGET values (its own body only); `content` is the placeholder, so the wrapped content is not
/// re-evaluated when this body re-runs (S4.3). Sits above the layout host so the effect's `size` is the (animated)
/// viewport (M5 C1).
struct TransformHost: ViewModifier {
    let state: ZTronScrollState
    let axes: Axis.Set
    /// The view has a scaling header (`withScalingHeader`): the 15–16 content group is only for it (`ContentLayerGroup`).
    var hasHeader = false
    @Environment(\.displayScale) private var displayScale
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage {
            relay.subscribe(to: [.target, .metrics, .phase], of: storage)
        }
        #if DEBUG
        ZTronRenderCounters.increment("transformHost.body")
        #endif
        let storage = state.storage
        let scale = storage.targetZoom
        var offset = storage.targetOffset
        let metrics = storage.metrics
        // No pixel snap while a resize is in flight: the effect maps the unclamped target exactly.
        if storage.phase == .idle, !metrics.resize.isOpen {
            offset = CGPoint(x: ContentGeometry.snap(offset.x, scale: displayScale),
                             y: ContentGeometry.snap(offset.y, scale: displayScale))
        }
        // Content is not hit-testable while it moves without a finger (a catching touch must not fire a Button) or
        // while a drag is recognized (a Button under the finger is cancelled instead of firing on lift).
        let blocked = (storage.phase == .decelerating || storage.phase == .animating) && !storage.isTracking || storage.isDragging
        return content
            .modifier(ContentLayerGroup(useGeometryGroup: state.usesGeometryGroup, hasHeader: hasHeader))
            .modifier(ContentInteractionGate(blocked: blocked))
            .modifier(ContentTransform(offset: offset, scale: scale, insets: metrics.adjustedContentInset,
                                       commit: metrics.resize, limits: state.zoomLimits, alignment: state.contentAlignment,
                                       paging: state.isPagingEnabled ? axes : [], probe: state.probe))
            .modifier(CompletionObserver(state: state))
    }
}

/// The content's hit-testing gate (D11), in a leaf of its own: its only input is `blocked`, so its body (and with it the
/// `.disabled` environment transform it applies) runs when `blocked` flips (motion start and end), never on the transform
/// host's per-frame evaluations. Applied inline in that body, `.disabled(blocked)` was a new environment transform on
/// every frame of a scroll or zoom: every control in the content was laid out again on every frame, and a control in a
/// content-integral overlay placed the overlay `Layout` (and measured its `.ideal` overlays) on every frame (27.0 under
/// host load: 42–67 placements in a pinch, bound 2; hosted on 27.0: one per frame; 17.5: none; open item 17). One `Bool`, no
/// padding: equal and byte-identical while unchanged (D43). The header's controls have their own gate on `.phase`
/// (`HeaderInteractionGate`).
struct ContentInteractionGate: ViewModifier {
    let blocked: Bool

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!blocked)
            .disabled(blocked)
    }
}

/// The scrolled content as ONE layer group under the content transform (M8b-3 seamless header, seam spike C). Without it
/// SwiftUI pushes the transform down to the content's leaf layers; in a system rotation Core Animation interpolates every
/// layer-geometry change made inside UIKit's rotation block, so the leaves that stay visible interpolate while the ones
/// that enter or leave the viewport (culled) or are rebuilt land at once: the content tears and never moves with the
/// header. With the group the transform is the group's and Core Animation moves the content rigidly, in lockstep with the
/// header's frame (also a group, `HeaderLayerGroup`). No content body runs; the branch is a `let` flag fixed at state
/// creation (R6), so the identity never changes.
///
/// 17+: `geometryGroup()`, which isolates geometry only (no compositing semantics, no offscreen pass).
/// 15–16 (decision 2026-10-27, also for the header's group, `HeaderLayerGroup`): `compositingGroup()`, the only iOS 13
/// modifier that ends the push-down at a layer boundary (measured on the forced lane: the same rigid rotation; without a
/// group the baseline content tore, up to 94 pt off the header). Chosen over nothing, given the open question of its cost: a compositing group
/// renders offscreen only for a compositing effect applied ABOVE it (an ancestor's opacity < 1 or blend mode), exactly
/// when UIKit's default group opacity (`allowsGroupOpacity`) renders a `UIScrollView`'s subtree offscreen too; with none,
/// it is a plain container layer (no rasterization, filter or mask: checked on the forced path's layer tree). Under such
/// an ancestor effect the content then fades as one image, as a `UIScrollView`'s does, instead of leaf by leaf. Without the
/// group the 15–16 content would tear in every rotation, which the seamless-header requirement rules out. Device check on
/// a real 15/16 (Instruments, offscreen passes while scrolling under an opacity transition) remains open.
///
/// A compositing group also changes what is drawn (review d16): blend modes inside the content composite inside the group
/// and no longer reach what is behind the scroll view (a `.blendMode(.multiply)` row over the scroll view's background
/// draws unblended), and an opacity applied above it fades the content as one image. So on 15–16 the group is applied
/// only to a view that has a scaling header at its first render (the seam requirement is the header's); a view without
/// one draws exactly as before (and as a native `ScrollView`), its rotation unchanged. The choice is latched at the first
/// render (`GroupLatch`): installing or removing the header later never changes the content's identity (a 15–16 header
/// installed later rotates with the pre-group tearing; one removed later keeps the group). SPEC S10 "15–16 layer groups".
struct ContentLayerGroup: ViewModifier {
    let useGeometryGroup: Bool
    let hasHeader: Bool
    @StateObject private var latch = GroupLatch()

    @ViewBuilder
    func body(content: Content) -> some View {
        if useGeometryGroup, #available(iOS 17, *) {
            content.geometryGroup()
        } else if latch.grouped(hasHeader) {
            content.compositingGroup()
        } else {
            content
        }
    }
}

/// A 15–16 group's first-render decision (never published: it never changes after the first body): the content's
/// (`ContentLayerGroup`) and the refresh indicator box's (`RefreshIndicatorGroup`). DEBUG: the decision in the render
/// counters' notes under `note`.
final class GroupLatch: ObservableObject {
    private var value: Bool?
    private let note: String

    init(note: String = "content.group") { self.note = note }

    func grouped(_ hasHeader: Bool) -> Bool {
        if let value { return value }
        value = hasHeader
        #if DEBUG
        let note = note
        MainActor.assumeIsolated { ZTronRenderCounters.notes[note] = hasHeader ? "compositing" : "none" }
        #endif
        return hasHeader
    }
}

/// Transaction completion -> `finishTransactionMotion` (17+). 15-16 rely on the 2-frame settle detector.
struct CompletionObserver: ViewModifier {
    let state: ZTronScrollState

    @ViewBuilder
    func body(content: Content) -> some View {
        if state.usesAnimationCompletion, #available(iOS 17, *) {
            content.transaction { t in
                guard t.animation != nil, !t.disablesAnimations, let token = MainActor.assumeIsolated({ state.activeTransactionToken })
                else { return }
                t.addAnimationCompletion(criteria: .removed) {
                    MainActor.assumeIsolated { state.finishTransactionMotion(token: token) }
                }
            }
        } else {
            content
        }
    }
}
