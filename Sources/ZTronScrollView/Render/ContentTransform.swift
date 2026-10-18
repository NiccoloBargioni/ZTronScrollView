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

    private static func near(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01
    }

    /// (offset, scale, pad) drawn at `size`.
    func resolved(size: CGSize) -> (offset: CGPoint, scale: CGFloat, pad: CGPoint) {
        let cur = commit.current
        if cur.viewport.width <= 0 || cur.viewport.height <= 0 || (!commit.isOpen && Self.near(size, cur.viewport) && insets == cur.insets) {
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
/// DEBUG `resize.jumpFrames` (design M5 section 10): a drawn frame during a viewport resize (size changed since the
/// previous evaluation, or the resize commit is open) whose visible-centre content point, normalized to the content
/// size drawn in that frame (D16: reflowing content keeps its normalized centre), moved by more than 1 viewport point.
/// Content clamped at an edge legitimately counts.
@MainActor
enum ResizeJumpMonitor {
    private static var last: (size: CGSize, n: CGPoint, desc: String)?
    static func record(size: CGSize, normalized n: CGPoint, content: CGSize, scale: CGFloat, resizing: Bool) {
        let desc = String(format: "size=%.0fx%.0f k=%.0fx%.0f n=%.4f,%.4f s=%.3f open=%d",
                          size.width, size.height, content.width, content.height, n.x, n.y, scale, resizing ? 1 : 0)
        defer { last = (size, n, desc) }
        guard let l = last else { return }
        let sizeChanged = abs(l.size.width - size.width) > 0.01 || abs(l.size.height - size.height) > 0.01
        guard sizeChanged || resizing else { return }
        if hypot((n.x - l.n.x) * content.width, (n.y - l.n.y) * content.height) * scale > 1 {
            ZTronRenderCounters.increment("resize.jumpFrames")
            ZTronRenderCounters.notes["resize.jump"] = "[\(l.desc)] -> [\(desc)]"
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
        // A leaf modifier change on the placeholder: content bodies are not re-evaluated.
        let blocked = (storage.phase == .decelerating || storage.phase == .animating) && !storage.isTracking || storage.isDragging
        return content
            .allowsHitTesting(!blocked)
            .disabled(blocked)
            .modifier(ContentTransform(offset: offset, scale: scale, insets: metrics.adjustedContentInset,
                                       commit: metrics.resize, limits: state.zoomLimits, alignment: state.contentAlignment,
                                       paging: state.isPagingEnabled ? axes : [], probe: state.probe))
            .modifier(CompletionObserver(state: state))
    }
}

/// Transaction completion -> `finishTransactionMotion` (17+). 15-16 rely on the 2-frame settle detector.
struct CompletionObserver: ViewModifier {
    let state: ZTronScrollState

    @ViewBuilder
    func body(content: Content) -> some View {
        if ZTronAvailability.isAvailable(.animationCompletion), #available(iOS 17, *) {
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
