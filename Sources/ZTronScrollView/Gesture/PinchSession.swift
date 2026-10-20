import SwiftUI
import ZTronScrollPhysics

// Pure pinch state machine (design M4 §2-4). No views, no state object, no clock: the coordinator feeds gesture
// samples and applies the returned effects.

enum PinchEvent: Equatable {
    /// First gesture value (magnification 1) or second finger down (18+). A nil centroid is estimated from the next sample.
    case began(centroid: CGPoint?, time: TimeInterval)
    /// `magnification` is the ratio versus the gesture start; a nil centroid keeps the estimate.
    case changed(magnification: CGFloat, centroid: CGPoint?, time: TimeInterval)
    /// Spatial observer (18+); a count of 1 is a one-finger lift.
    case fingerCountChanged(count: Int, remaining: CGPoint?, time: TimeInterval)
    /// 15-17: the pan `DragGesture` translation, which drives the centroid estimate.
    case panTranslation(CGSize, time: TimeInterval)
    case ended(time: TimeInterval)
    case frame(time: TimeInterval)
    case cancelled
}

/// Cold snapshot taken by the coordinator before each event.
struct PinchEnvironment: Equatable {
    var limits: ClosedRange<CGFloat> = 1...1
    var isZoomEnabled = false
    var bouncesZoom = true
    var presentationScale: CGFloat = 1
    var presentationOffset: CGPoint = .zero
    var geometry = ZoomGeometry(viewportSize: .zero, unscaledContentSize: .zero)
    var isMovingWithoutFinger = false
    var logDimension: CGFloat = 1
    var panDragActive = false
    /// Per-axis bounce (same resolution as the pan): an axis that bounces rubber-bands past its bounds under a pinch as
    /// under a one-finger drag, an axis that does not never leaves them.
    var bouncesX = true
    var bouncesY = true
    /// The pan's rubber band `c` (`PanSession.rubberBandCoefficient`); the hand-off inverts the same band.
    var rubberBandCoefficient: CGFloat = 0.55
}

struct ZoomBounceRequest: Equatable {
    var scale: CGFloat
    var offset: CGPoint
    var lastCentroid: CGPoint
    var time: TimeInterval
}

enum PinchEffect: Equatable {
    case catchMotion
    case beginZooming
    case setZoom(scale: CGFloat, offset: CGPoint)
    case bounce(ZoomBounceRequest)
    case endZooming(atScale: CGFloat)
    case handOffToPan(remaining: CGPoint?)
}

struct PinchSession: Equatable {
    struct Pinch: Equatable {
        var startScale: CGFloat
        /// Unscaled content point under the start centroid.
        var anchor: CGPoint
        var anchorPending: Bool
        var startCentroid: CGPoint
        var centroid: CGPoint
        var panTranslationAtStart: CGSize?
        var lastRaw: CGFloat
        var fingers: Int
        var hasZoomed: Bool
        /// Magnification at which `startScale` applies (re-anchoring resets it).
        var baseMagnification: CGFloat = 1
        /// The session was begun by the observer (fingers), not by the gesture's own `.began`: the gesture that will
        /// report next may be the OLD one, still running with its cumulative magnification (D29), so the first
        /// `.changed` sample defines the base instead of 1.
        var baseMagnificationPending = false
        var limits: ClosedRange<CGFloat>
        var geometry: ZoomGeometry
        var shown: CGFloat
        var offset: CGPoint
    }
    enum Phase: Equatable { case idle, armed(Pinch), pinching(Pinch), released }
    enum CentroidSource: Equatable { case spatial, startLocationPlusDrag, dragOnly }

    var phase: Phase = .idle
    var centroidSource: CentroidSource = .spatial
    /// The observer ended the pinch (a finger lifted) but the magnify gesture has not reported its end yet: its
    /// trailing `.changed` samples carry the OLD gesture's cumulative magnification and must not start a new session
    /// (D25: applied to the current scale with base 1 they multiplied it again — the one-frame snap at the lift).
    var gestureEndPending = false
    /// Two fingers down whose centroid moves this far before the magnify gesture recognizes start the pinch anyway
    /// (two-finger pan): UIScrollView moves the content under two still-unscaled fingers immediately.
    var centroidHysteresis: CGFloat = 10

    var isActive: Bool {
        switch phase {
        case .armed, .pinching: return true
        default: return false
        }
    }

    // MARK: Pure formulas (design §3)

    /// raw = startScale·magnification; log-space resistance with `bouncesZoom`, a clamp otherwise.
    static func shownScale(startScale: CGFloat, magnification: CGFloat, env: PinchEnvironment) -> CGFloat {
        let raw = startScale * magnification
        if env.bouncesZoom {
            return ZoomSolver.resisted(rawScale: raw, limits: env.limits, logDimension: env.logDimension)
        }
        return min(max(raw, env.limits.lowerBound), env.limits.upperBound)
    }

    /// pad(s) + s·u − centroid, then per axis (D24): past the bounds an axis that bounces is rubber-banded with the
    /// pan's `f(x) = x·c·d/(|x|·c + d)` (UIScrollView's pan recognizer handles one and two fingers alike, so a
    /// two-finger slide past an edge resists like a one-finger drag; docs/design/PHYSICS-calibration.md), an axis
    /// that does not bounce is clamped (D23). `bouncesZoom` concerns the scale only (``shownScale``).
    static func offset(anchor: CGPoint, centroid: CGPoint, scale: CGFloat, env: PinchEnvironment) -> CGPoint {
        let raw = ZoomSolver.offset(keeping: anchor, under: centroid, scale: scale, geometry: env.geometry, clamped: false)
        let b = env.geometry.bounds(at: scale)
        func axis(_ x: CGFloat, _ bounds: AxisBounds, bounces: Bool, viewport: CGFloat) -> CGFloat {
            guard bounces else { return bounds.clamped(x) }
            let band = RubberBand(dimension: viewport, coefficient: env.rubberBandCoefficient)
            return bounds.clamped(x) + band.displacement(forOverscroll: bounds.overscroll(of: x))
        }
        return CGPoint(x: axis(raw.x, b.x, bounces: env.bouncesX, viewport: env.geometry.x.viewportLength),
                       y: axis(raw.y, b.y, bounces: env.bouncesY, viewport: env.geometry.y.viewportLength))
    }

    static func estimatedCentroid(start: CGPoint, panAtStart: CGSize?, panNow: CGSize) -> CGPoint {
        let base = panAtStart ?? panNow
        return CGPoint(x: start.x + panNow.width - base.width, y: start.y + panNow.height - base.height)
    }

    // MARK: Events

    mutating func handle(_ event: PinchEvent, env: PinchEnvironment) -> [PinchEffect] {
        if case .released = phase { phase = .idle }
        // Zoom switched off mid-session (or never on): finish whatever runs, start nothing.
        if !env.isZoomEnabled {
            switch event {
            case .began, .changed, .panTranslation, .frame, .fingerCountChanged:
                return isActive ? finish(env: env, time: nil) : []
            default: break
            }
        }
        switch event {
        case let .began(centroid, _):
            gestureEndPending = false                       // a new gesture
            guard env.isZoomEnabled else { return [] }
            if isActive {
                // Already armed by the observer: the gesture now begins anew, so its samples are relative to 1.
                update { $0.baseMagnificationPending = false }
                return []
            }
            begin(centroid: centroid, env: env, fromGesture: true)
            return env.isMovingWithoutFinger ? [.catchMotion] : []

        case let .changed(m, centroid, _):
            guard m.isFinite, m > 0 else { return [] }
            if !isActive {
                // The ended gesture's trailing sample (D25): nothing to apply it to.
                if gestureEndPending { return [] }
                // A change without a began (observer missed it): the gesture start is this sample.
                begin(centroid: centroid, env: env, fromGesture: false)
            }
            var effects: [PinchEffect] = []
            if case var .armed(p) = phase {
                if p.anchorPending, let c = centroid {
                    p.startCentroid = c; p.centroid = c
                    p.anchor = ZoomSolver.contentPoint(under: c, offset: env.presentationOffset,
                                                       scale: env.presentationScale, geometry: env.geometry)
                    p.anchorPending = false
                }
                phase = .pinching(p)
                effects.append(.beginZooming)
            }
            guard case var .pinching(p) = phase else { return effects }
            if let c = centroid { p.centroid = c }
            if p.baseMagnificationPending {
                // First sample of an observer-begun session: whatever gesture reports (the old one, cumulative, or a
                // new one near 1), this sample is the base; the scale continues from the current one (D29).
                p.baseMagnification = m
                p.baseMagnificationPending = false
            }
            if p.limits != env.limits || p.geometry != env.geometry { reanchor(&p, magnification: m, env: env) }
            apply(&p, magnification: m, env: env)
            phase = .pinching(p)
            return effects + [.setZoom(scale: p.shown, offset: p.offset)]

        case let .fingerCountChanged(count, remaining, time):
            guard isActive else {
                if count >= 2, env.isZoomEnabled {
                    // Two fingers again (a second finger landing during the one-finger continuation, D29, or a pinch
                    // the gesture has not reported yet): begin from the current geometry; the magnification base is
                    // the next sample's.
                    gestureEndPending = false
                    begin(centroid: remaining, env: env, fromGesture: false)
                    return env.isMovingWithoutFinger ? [.catchMotion] : []
                }
                return []
            }
            if count >= 2 {
                update { $0.fingers = count }
                guard let r = remaining else { return [] }
                return follow(centroid: r, env: env)
            }
            gestureEndPending = true                        // until the magnify gesture reports `.ended`
            return finish(env: env, time: time, handingOff: count == 1)
                + [.handOffToPan(remaining: count == 1 ? remaining : nil)]

        case let .panTranslation(t, _):
            guard centroidSource != .spatial, isActive else { return [] }
            update {
                if $0.panTranslationAtStart == nil { $0.panTranslationAtStart = t }
                $0.centroid = Self.estimatedCentroid(start: $0.startCentroid, panAtStart: $0.panTranslationAtStart, panNow: t)
            }
            guard case var .pinching(p) = phase else { return [] }
            p.offset = Self.offset(anchor: p.anchor, centroid: p.centroid, scale: p.shown, env: env)
            phase = .pinching(p)
            return [.setZoom(scale: p.shown, offset: p.offset)]

        case let .ended(time):
            gestureEndPending = false
            return finish(env: env, time: time)
        case .cancelled:
            gestureEndPending = false
            return finish(env: env, time: nil)
        case .frame:
            return []
        }
    }

    // MARK: Internals

    /// The true centroid (18+) moved: the content point under it follows 1:1 at the current scale, whether or not the
    /// magnification changed (a two-finger pan while pinching, or before the magnify gesture recognizes).
    private mutating func follow(centroid c: CGPoint, env: PinchEnvironment) -> [PinchEffect] {
        switch phase {
        case var .pinching(p):
            guard c != p.centroid else { return [] }
            p.centroid = c
            p.offset = Self.offset(anchor: p.anchor, centroid: c, scale: p.shown, env: env)
            phase = .pinching(p)
            return [.setZoom(scale: p.shown, offset: p.offset)]
        case var .armed(p):
            if p.anchorPending {
                p.startCentroid = c
                p.anchor = ZoomSolver.contentPoint(under: c, offset: env.presentationOffset,
                                                   scale: env.presentationScale, geometry: env.geometry)
                p.anchorPending = false
            }
            p.centroid = c
            let moved = hypot(c.x - p.startCentroid.x, c.y - p.startCentroid.y)
            guard moved >= centroidHysteresis else { phase = .armed(p); return [] }
            p.offset = Self.offset(anchor: p.anchor, centroid: c, scale: p.shown, env: env)
            phase = .pinching(p)
            return [.beginZooming, .setZoom(scale: p.shown, offset: p.offset)]
        default:
            return []
        }
    }

    private mutating func update(_ body: (inout Pinch) -> Void) {
        switch phase {
        case var .armed(p): body(&p); phase = .armed(p)
        case var .pinching(p): body(&p); phase = .pinching(p)
        default: break
        }
    }

    private mutating func begin(centroid: CGPoint?, env: PinchEnvironment, fromGesture: Bool) {
        let start = centroid ?? env.geometry.visibleCenter
        let scale = env.presentationScale
        let startScale = ZoomSolver.unresisted(shownScale: scale, limits: env.limits, logDimension: env.logDimension)
        let anchor = ZoomSolver.contentPoint(under: start, offset: env.presentationOffset, scale: scale,
                                             geometry: env.geometry)
        phase = .armed(Pinch(startScale: startScale, anchor: anchor, anchorPending: centroid == nil,
                             startCentroid: start, centroid: start, panTranslationAtStart: nil,
                             lastRaw: startScale, fingers: 2, hasZoomed: false,
                             baseMagnificationPending: !fromGesture, limits: env.limits,
                             geometry: env.geometry, shown: scale, offset: env.presentationOffset))
    }

    /// Limits or geometry changed mid-pinch (resize, rotation): anchor again from what is on screen.
    private func reanchor(_ p: inout Pinch, magnification m: CGFloat, env: PinchEnvironment) {
        p.anchor = ZoomSolver.contentPoint(under: p.centroid, offset: env.presentationOffset,
                                           scale: env.presentationScale, geometry: env.geometry)
        p.startScale = ZoomSolver.unresisted(shownScale: env.presentationScale, limits: env.limits,
                                             logDimension: env.logDimension)
        p.baseMagnification = m
        p.baseMagnificationPending = false
        p.limits = env.limits
        p.geometry = env.geometry
    }

    private func apply(_ p: inout Pinch, magnification m: CGFloat, env: PinchEnvironment) {
        let ratio = m / p.baseMagnification
        p.lastRaw = p.startScale * ratio
        p.shown = Self.shownScale(startScale: p.startScale, magnification: ratio, env: env)
        p.offset = Self.offset(anchor: p.anchor, centroid: p.centroid, scale: p.shown, env: env)
        p.hasZoomed = true
    }

    /// Release: a bounce when the scale or the offset is out of range, else the end at once. Nothing when the
    /// pinch never produced a sample. `handingOff` (one finger stays down, 18+): the pan continues from that finger
    /// and holds an overscroll as its rubber band until the last finger lifts, as UIScrollView does; only a scale past
    /// its limit springs back now (D23: springing the offset back under a finger still on the glass is the snap).
    private mutating func finish(env: PinchEnvironment, time: TimeInterval?, handingOff: Bool = false) -> [PinchEffect] {
        guard case let .pinching(p) = phase else {
            phase = isActive ? .released : phase
            return []
        }
        phase = .released
        let b = env.geometry.bounds(at: p.shown)
        let offsetOut = b.x.clamped(p.offset.x) != p.offset.x || b.y.clamped(p.offset.y) != p.offset.y
        let scaleOut = !env.limits.contains(p.shown)
        guard scaleOut || (offsetOut && !handingOff) else { return [.endZooming(atScale: p.shown)] }
        guard env.bouncesZoom else {
            return [.setZoom(scale: p.shown, offset: env.geometry.clamped(p.offset, at: p.shown)),
                    .endZooming(atScale: p.shown)]
        }
        return [.bounce(ZoomBounceRequest(scale: p.shown, offset: p.offset, lastCentroid: p.centroid,
                                          time: time ?? .nan))]
    }
}
