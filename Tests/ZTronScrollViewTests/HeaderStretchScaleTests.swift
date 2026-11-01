import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// D69: `pull: .stretch` is a render-time scale of the header stack laid out at its resting height, anchored at the
/// top centre (`HeaderStretchEffect`), clipped to `W × (R + g)` in the unscaled frame (`HeaderStretchClip`). A pull lays
/// nothing out: the stack keeps `(W, R)`, its drawn frame is `(W/2 − s·W/2, top0, s·W, R + g)` with `s = (R + g)/R`, its
/// bottom edge on the content's top; an aspect-fit image grows with the pull. Both OS paths (16+ `HeaderSlotLayout`, 15 /
/// forced `HeaderFallbackFrame`). The drawn frames are read from the hosted layer tree (marker colours), the layout
/// from a `GeometryReader` inside the header (its proposal is the layout's).
///
/// Hosting: these tests host `UIHostingController(rootView:)` directly; the iOS 26+ hosting rule of main (INTEG-s1,
/// `HostingViews.track`) has no helper on this branch yet (merge note).
@MainActor
@Suite(.serialized)
struct HeaderStretchScaleTests {
    static let headerMarker = (r: 0.13, g: 0.26, b: 0.39)
    static let contentMarker = (r: 0.41, g: 0.17, b: 0.29)
    static func color(_ m: (r: Double, g: Double, b: Double)) -> Color { Color(red: m.r, green: m.g, blue: m.b) }

    final class Box {
        var size: CGSize = .zero
        var sizes: [CGSize] = []
        var global: CGRect = .null
    }

    /// Fills the proposal it gets (the layout frame), records it, and draws the header marker.
    struct SizeProbe: View {
        let box: Box
        var body: some View {
            GeometryReader { g in
                let _ = record(g)
                HeaderStretchScaleTests.color(HeaderStretchScaleTests.headerMarker)
            }
        }
        func record(_ g: GeometryProxy) {
            box.size = g.size
            box.sizes.append(g.size)
            box.global = g.frame(in: .global)
        }
    }

    /// The header for a size: `.fit` gets a 16:9 ideal height at any width (`HeaderLayoutFrameTests.FitProbe`).
    struct Header: View {
        let size: ZTronHeaderSize
        let box: Box
        var body: some View {
            if size.isFit {
                Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(SizeProbe(box: box))
            } else {
                SizeProbe(box: box)
            }
        }
    }

    /// The content: a marker strip on top (its drawn top is the content's), then a tall filler.
    struct Content: View {
        let counts: BodyCount
        var body: some View {
            counts.bodies += 1
            return VStack(spacing: 0) {
                HeaderStretchScaleTests.color(HeaderStretchScaleTests.contentMarker).frame(height: 8)
                Color.green.frame(height: 3000)
            }
        }
    }

    struct Host: View {
        let state: ZTronScrollState
        let size: ZTronHeaderSize
        let box: Box
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Content(counts: counts) }
                .withScalingHeader(size: size, pull: .stretch) { _ in Header(size: size, box: box) }
        }
    }

    func window<V: View>(_ view: V, size: CGSize = CGSize(width: 402, height: 874)) -> UIWindow {
        let w = UIWindow(frame: CGRect(origin: .zero, size: size))
        w.rootViewController = UIHostingController(rootView: view)
        w.makeKeyAndVisible()
        pump(0.4)
        return w
    }

    func resolve(_ s: ZTronScrollState) {
        var n = 0
        while s.peek.metrics.header == nil, n < 60 { pump(0.1); n += 1 }
        pump(0.3)
    }

    /// The window frames of the layers filled with `marker`; `presented`: as drawn now (the presentation tree).
    static func frames(of marker: (r: Double, g: Double, b: Double), in window: UIWindow, presented: Bool = false) -> [CGRect] {
        var out: [CGRect] = []
        let root = presented ? (window.layer.presentation() ?? window.layer) : window.layer
        func visit(_ layer: CALayer) {
            if let c = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - marker.r) < 0.02, abs(g - marker.g) < 0.02, abs(b - marker.b) < 0.02 {
                    out.append(layer.convert(layer.bounds, to: root))
                }
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root)
        return out
    }

    /// Layers that would make an offscreen pass (a mask, a filter, rasterization) anywhere in the window.
    static func offscreenOffenders(in window: UIWindow) -> [String] {
        var out: [String] = []
        func walk(_ layer: CALayer, _ depth: Int) {
            if layer.shouldRasterize { out.append("rasterized \(type(of: layer)) at \(depth)") }
            if let f = layer.filters, !f.isEmpty { out.append("filters \(f) on \(type(of: layer)) at \(depth)") }
            if layer.mask != nil { out.append("mask on \(type(of: layer)) at \(depth)") }
            for sub in layer.sublayers ?? [] { walk(sub, depth + 1) }
        }
        walk(window.layer, 0)
        return out
    }

    nonisolated static let sizes: [ZTronHeaderSize] = [.fixed(min: 64, max: 240), .aspectRatio(16.0 / 9.0, min: 64), .fit(min: 64)]

    /// A pull: the stack stays laid out at `(W, R)`; it is drawn scaled by `(R + g)/R` from its top centre (top pinned at
    /// `top0`, bottom edge `top0 + R + g` on the content's drawn top, `s·W` wide and centred, cut at the sides by the
    /// clip); the state's geometry is the drawn one. No content body, no header builder run, no offscreen pass.
    @Test(arguments: OSPath.allCases, Self.sizes)
    func aPullIsARenderTimeScaleOfTheRestingLayout(path: OSPath, size: ZTronHeaderSize) {
        let box = Box(), counts = BodyCount()
        let s = makeState(path)
        let w = withOSPath(path) { window(Host(state: s, size: size, box: box, counts: counts)) }
        defer { unhost(w) }
        resolve(s)
        guard let resting = s.peek.metrics.header?.resting else { Issue.record("\(path) \(size): unresolved"); return }
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        let bodies = counts.bodies
        for g in [30, 90, 0] as [CGFloat] {
            s.track(offset: CGPoint(x: 0, y: -g - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.1)
            let m = s.peek.metrics
            let top0 = HeaderMath.top0(m)
            let tag = "\(path) \(size) g \(g)"
            #expect(abs(box.size.height - resting) < 0.5 && abs(box.size.width - 402) < 0.5,
                    "\(tag): laid out at the resting size (\(box.size), R \(resting))")
            let header = Self.frames(of: Self.headerMarker, in: w), content = Self.frames(of: Self.contentMarker, in: w)
            guard let f = header.first, let c = content.first, header.count == 1 else {
                Issue.record("\(tag): marker layers header \(header) content \(content)"); continue
            }
            let scale = (resting + g) / resting
            #expect(abs(f.minY - top0) < 0.5, "\(tag): top pinned at top0 \(top0) (\(f))")
            #expect(abs(f.maxY - (top0 + resting + g)) < 0.5, "\(tag): bottom edge grown by the pull (\(f))")
            #expect(abs(f.width - 402 * scale) < 0.5 && abs(f.midX - 201) < 0.5, "\(tag): uniform scale, centred (\(f), s \(scale))")
            #expect(abs(f.maxY - c.minY) < 0.5, "\(tag): seam: header bottom \(f.maxY) vs content top \(c.minY)")
            #expect(abs((s.headerGeometry?.height ?? -1) - (resting + g)) < 0.01 && s.headerGeometry?.stretch == g,
                    "\(tag): the geometry is the drawn one (\(String(describing: s.headerGeometry)))")
            print("STRETCH \(tag): reader global \(box.global) drawn \(f)")
            let offenders = Self.offscreenOffenders(in: w)
            #expect(offenders.isEmpty, "\(tag): \(offenders)")
        }
        #expect(counts.bodies == bodies, "\(path) \(size): no content body (\(counts.bodies - bodies))")
        #if DEBUG
        #expect(ZTronRenderCounters.value("header.builder") == 0, "\(path) \(size): the builder never ran for a pull")
        #expect(ZTronRenderCounters.value("header.frame") >= 3, "\(path) \(size): the leaf ran per pull step")
        #endif
    }

    final class Width: ObservableObject { @Published var narrow = false }

    /// A refreshing `.stretch` header (the hold scales it) whose width the app animates.
    struct HoldHost: View {
        let state: ZTronScrollState
        @ObservedObject var width: Width
        let box: Box
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Content(counts: counts) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), pull: .stretch) { _ in SizeProbe(box: box) }
                .refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20) }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
                .frame(width: width.narrow ? 241 : 402)
                .frame(maxWidth: .infinity)
        }
    }

    /// A stretch hold across an app-animated width change (402 → 241, R 226 → 136): every layout the header gets is the
    /// aspect height at its width (the stretch never enters the layout, so the animated pass is final and the unanimated
    /// commit re-sets nothing), the hold's stretch is kept, every sampled frame keeps the drawn header's bottom edge on the
    /// drawn content's top, and the end state is the scale of the new resting height. No content body, no builder run.
    @Test(arguments: OSPath.allCases)
    func aStretchHoldKeepsTheScaleAcrossAnAnimatedWidthChange(path: OSPath) {
        let box = Box(), counts = BodyCount(), width = Width()
        let s = makeState(path)
        let w = withOSPath(path) { window(HoldHost(state: s, width: width, box: box, counts: counts)) }
        defer { unhost(w) }
        resolve(s)
        s.beginRefreshing()
        pump(0.6)
        let hold = s.headerGeometry?.stretch ?? 0
        #expect(hold > 30, "\(path): the hold stretches the header (\(String(describing: s.headerGeometry)))")
        s.endOfTurn()
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        let bodies = counts.bodies
        box.sizes.removeAll()
        withAnimation(.linear(duration: 0.5)) { width.narrow = true }
        var worst: CGFloat = 0, samples = 0, lateral: CGFloat = 0
        for _ in 0..<40 {
            pump(1.0 / 60)
            let header = Self.frames(of: Self.headerMarker, in: w, presented: true)
            let content = Self.frames(of: Self.contentMarker, in: w, presented: true)
            guard let f = header.first, let c = content.first else { continue }
            worst = max(worst, abs(f.maxY - c.minY))
            lateral = max(lateral, abs(f.midX - c.midX))
            samples += 1
        }
        pump(0.5)
        let tag = "\(path)"
        let stale = box.sizes.filter { abs($0.height - $0.width * 9 / 16) > 0.5 }
        #expect(stale.isEmpty, "\(tag): layouts off the aspect height (stretch in the layout?) \(stale) of \(box.sizes)")
        #expect(samples >= 10 && worst < 1, "\(tag): header bottom vs content top, worst \(worst) over \(samples) frames")
        #expect(lateral < 1, "\(tag): lateral offset between header and content centres, worst \(lateral)")
        let r = s.peek.metrics.header?.resting ?? -1
        #expect(abs(r - 241 * 9 / 16) < 0.5, "\(tag): R at 241 (\(r))")
        #expect(abs((s.headerGeometry?.stretch ?? -1) - hold) < 0.5, "\(tag): the hold's stretch kept (\(String(describing: s.headerGeometry)))")
        if let f = Self.frames(of: Self.headerMarker, in: w).first, let c = Self.frames(of: Self.contentMarker, in: w).first {
            let top0 = HeaderMath.top0(s.peek.metrics)
            #expect(abs(f.minY - top0) < 0.5 && abs(f.maxY - (top0 + r + hold)) < 0.5 && abs(f.maxY - c.minY) < 0.5,
                    "\(tag): end: drawn \(f), content top \(c.minY), top0 \(top0) R \(r) hold \(hold)")
            #expect(abs(f.width - 241 * (r + hold) / r) < 0.5, "\(tag): end: scaled width \(f.width)")
        } else {
            Issue.record("\(tag): no marker layers at the end")
        }
        #expect(counts.bodies == bodies, "\(tag): no content body (\(counts.bodies - bodies))")
        #if DEBUG
        // The host's body re-runs once for the width toggle (a parent rebuild applies the new builder closure, R7): one
        // builder run, never one per frame.
        #expect(ZTronRenderCounters.value("header.builder") <= 1,
                "\(tag): the builder ran \(ZTronRenderCounters.value("header.builder")) times (the parent rebuild: 1)")
        #endif
    }

    /// The effect and the clip (pure): the top centre is fixed, the bottom edge moves down by the stretch, the width scales
    /// with it; identity / the frame itself without a stretch, for a zero height or non-finite input. Their animatable
    /// data is `o′`: an interpolated `o′` re-derives the stretch while following, and changes nothing while held (a resize).
    @Test func theEffectAndTheClipAreTheScaleOfTheLayoutFrame() {
        let size = CGSize(width: 402, height: 240)
        let t = HeaderStretchEffect.transform(size: size, stretch: 60)
        let topCentre = CGPoint(x: 201, y: 0).applying(t), bottomLeft = CGPoint(x: 0, y: 240).applying(t)
        #expect(abs(topCentre.x - 201) < 1e-9 && abs(topCentre.y) < 1e-9, "top centre fixed: \(topCentre)")
        #expect(abs(bottomLeft.x - (201 - 201 * 1.25)) < 1e-9 && abs(bottomLeft.y - 300) < 1e-9, "bottom left: \(bottomLeft)")
        #expect(HeaderStretchEffect.transform(size: size, stretch: 0) == .identity)
        #expect(HeaderStretchEffect.transform(size: CGSize(width: 402, height: 0), stretch: 60) == .identity)
        #expect(HeaderStretchEffect.transform(size: size, stretch: .nan) == .identity)
        #expect(HeaderStretchEffect.transform(size: size, stretch: .infinity) == .identity)
        let rect = CGRect(origin: .zero, size: size)
        #expect(HeaderStretchClip.rect(in: rect, stretch: 60) == CGRect(x: 0, y: 0, width: 402, height: 300))
        #expect(HeaderStretchClip.rect(in: rect, stretch: 0) == rect)
        #expect(HeaderStretchClip.rect(in: CGRect(x: 0, y: 0, width: 402, height: 0), stretch: 60).height == 0)

        let m = HeaderMetrics(min: 64, resting: 240, behavior: .stretch, width: 402)
        var live = HeaderLiveInput(size: .fixed(min: 64, max: 240), metrics: m, stateHeight: 240, followsOffset: true)
        var effect = HeaderStretchEffect(live: live), clip = HeaderStretchClip(live: live)
        effect.animatableData = -50
        clip.animatableData = -50
        #expect(effect.live.stretch == 50 && clip.live.stretch == 50 && effect.live.stateHeight == 240,
                "following: the stretch re-derived, the layout height not (\(effect.live))")
        live.followsOffset = false
        live.stretch = 60
        effect = HeaderStretchEffect(live: live)
        effect.animatableData = -10
        #expect(effect.live.stretch == 60, "held: only o′ moves")
    }

    /// Bit-stability (D62, design §5 item 4): while a resize is open the leaf's stretch is the intent's anchor `.top(x)`,
    /// not re-derived from the realised target (ulps apart), and the layout height has no stretch; so the effect's
    /// transform at the layout's size is bit-identical before and after the unanimated commit.
    @Test func aStretchHoldIsBitStableAcrossTheUnanimatedCommit() {
        var m = ScrollMetrics()
        m.viewportSize = CGSize(width: 402, height: 874)
        m.safeAreaInsets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        m.header = HeaderMetrics(min: 64, resting: 226.125, behavior: .stretch, width: 402)
        m.refreshHold = EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0)
        m.adjustedContentInset = EdgeInsets(top: 62 + 226.125 + 60, leading: 0, bottom: 34, trailing: 0)
        m.resize.isOpen = true
        m.resize.intent = ResizeIntent(normalizedCenter: CGPoint(x: 0.5, y: 0.5), scale: 1, atFit: true, header: .top(-60))
        let base = HeaderMath.base(m)
        let before = HeaderFrameModifier.liveInput(size: .aspectRatio(16.0 / 9.0, min: 64), overflow: .uncapped, metrics: m,
                                                   edges: .vertical, target: CGPoint(x: 0, y: -60 - base), zoom: 1, held: -60)
        // The commit: the new width's metrics, the target realised ulps away from the anchor.
        var n = m
        n.viewportSize = CGSize(width: 241, height: 874)
        n.header = HeaderMetrics(min: 64, resting: 241 * 9 / 16, behavior: .stretch, width: 241)
        n.adjustedContentInset.top = 62 + 241 * 9 / 16 + 60
        let after = HeaderFrameModifier.liveInput(size: .aspectRatio(16.0 / 9.0, min: 64), overflow: .uncapped, metrics: n,
                                                  edges: .vertical, target: CGPoint(x: 0, y: (-60).nextUp - HeaderMath.base(n)),
                                                  zoom: 1, held: before.offset)
        #expect(!before.followsOffset && !after.followsOffset)
        #expect(before.stretch == 60 && after.stretch == 60 && before.offset == after.offset
                    && before.progress == after.progress && before.translation == after.translation,
                "held: \(before) vs \(after)")
        let resting: CGFloat = 241.0 * 9 / 16
        #expect(after.stateHeight == resting, "the layout height has no stretch (\(after.stateHeight))")
        #expect(after.visibleHeight == resting + 60, "the visible height does (\(after.visibleHeight))")
        let layout = CGSize(width: 241, height: resting)
        #expect(HeaderStretchEffect.transform(size: layout, stretch: before.stretch)
                    == HeaderStretchEffect.transform(size: layout, stretch: after.stretch))
    }
}
