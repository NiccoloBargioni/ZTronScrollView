import SwiftUI

/// Pure geometry helpers (S7 / design §5).
enum ContentGeometry {
    /// Center of the unobscured viewport (bounds inset by the safe area), in viewport coordinates.
    static func visibleCenter(_ viewport: CGSize, _ inset: EdgeInsets) -> CGPoint {
        CGPoint(x: (viewport.width + inset.leading - inset.trailing) / 2,
                y: (viewport.height + inset.top - inset.bottom) / 2)
    }

    /// Alignment padding, nonzero only on an axis where the scaled content is smaller than the viewport.
    static func pad(viewport: CGSize, content: CGSize, scale: CGFloat, alignment: UnitPoint) -> CGSize {
        guard content.width > 0, content.height > 0 else { return .zero }
        return CGSize(width: max(0, viewport.width - content.width * scale) * alignment.x,
                      height: max(0, viewport.height - content.height * scale) * alignment.y)
    }

    static func snap(_ v: CGFloat, scale: CGFloat) -> CGFloat {
        scale > 0 ? (v * scale).rounded() / scale : v
    }
}

/// One effect: x_v = s * x_c + pad - o. Pure function of its animatable data (and `size` is unused), so it
/// interpolates under any transaction and doubles as the presentation probe (design §6).
struct ContentTransform: GeometryEffect {
    var offset: CGPoint
    var scale: CGFloat
    var pad: CGSize
    let probe: PresentationBox?

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get {
            .init(.init(offset.x, offset.y), .init(scale, .init(pad.width, pad.height)))
        }
        set {
            offset = CGPoint(x: newValue.first.first, y: newValue.first.second)
            scale = newValue.second.first
            pad = CGSize(width: newValue.second.second.first, height: newValue.second.second.second)
        }
    }

    static func matrix(offset: CGPoint, scale: CGFloat, pad: CGSize) -> CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: pad.width - offset.x, ty: pad.height - offset.y)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        probe?.record(offset, scale)
        #if DEBUG
        if Thread.isMainThread { MainActor.assumeIsolated { ZTronRenderCounters.increment("transform.effect") } }
        #endif
        return ProjectionTransform(Self.matrix(offset: offset, scale: scale, pad: pad))
    }
}

/// Reads the TARGET values (its own body only); `content` is the placeholder, so the wrapped content is not
/// re-evaluated when this body re-runs (S4.3).
struct TransformHost: ViewModifier {
    let state: ZTronScrollState
    @Environment(\.displayScale) private var displayScale
    @StateObject private var relay = ChannelRelay()

    func body(content: Content) -> some View {
        if let storage = state.storage as? ChannelStorage {
            relay.subscribe(to: [.offset, .zoom, .metrics, .phase], of: storage)
        }
        #if DEBUG
        ZTronRenderCounters.increment("transformHost.body")
        #endif
        let storage = state.storage
        let scale = storage.targetZoom
        var offset = storage.targetOffset
        let metrics = storage.metrics
        if storage.phase == .idle {
            offset = CGPoint(x: ContentGeometry.snap(offset.x, scale: displayScale),
                             y: ContentGeometry.snap(offset.y, scale: displayScale))
        }
        let pad = ContentGeometry.pad(viewport: metrics.viewportSize, content: metrics.contentSize,
                                      scale: scale, alignment: state.contentAlignment)
        return content
            .modifier(ContentTransform(offset: offset, scale: scale, pad: pad, probe: state.probe))
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
