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
    /// D76: a fixed-size (60 × 20 pt) mark centred in the header, the stand-in for its text: magnified by `s` with
    /// `.keepTextMagnified`, its point size with `.keepTextSize`.
    static let textMarker = (r: 0.62, g: 0.71, b: 0.12)
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
            Group {
                if size.isFit {
                    Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(SizeProbe(box: box))
                } else {
                    SizeProbe(box: box)
                }
            }
            .overlay(HeaderStretchScaleTests.color(HeaderStretchScaleTests.textMarker).frame(width: 60, height: 20))
        }
    }

    /// D76: a test case's size and `stretchContent:`.
    struct StretchCase: Sendable, CustomTestStringConvertible {
        let size: ZTronHeaderSize
        let content: ZTronHeaderStretchContent
        var testDescription: String { "\(size) \(content)" }
    }

    nonisolated static let cases: [StretchCase] = sizes.flatMap {
        [StretchCase(size: $0, content: .keepTextMagnified), StretchCase(size: $0, content: .keepTextSize)]
    }

    /// Whether `.keepTextSize` lays the header out grown on this path: 16+ (`HeaderSlotLayout`); the 15 path draws both
    /// cases as D69 until M8b-s8 s7 (C14).
    static func grows(_ content: ZTronHeaderStretchContent, _ s: ZTronScrollState) -> Bool {
        content == .keepTextSize && s.usesLayoutProtocol
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
        var content: ZTronHeaderStretchContent = .keepTextMagnified
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Content(counts: counts) }
                .withScalingHeader(size: size, pull: .stretch, stretchContent: content) { _ in Header(size: size, box: box) }
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

    /// D76: the DRAWN rects of the layers filled with `marker`: each layer's window frame cut by every clipping
    /// (`masksToBounds`) ancestor's. With `.keepTextMagnified` the marker layer is the transformed (unclipped) stack; with
    /// `.keepTextSize` SwiftUI draws the fill already cut to the clip: their drawn rects are the same.
    static func drawnFrames(of marker: (r: Double, g: Double, b: Double), in window: UIWindow, presented: Bool = false) -> [CGRect] {
        var out: [CGRect] = []
        let root = presented ? (window.layer.presentation() ?? window.layer) : window.layer
        func visit(_ layer: CALayer, _ clip: CGRect) {
            var clip = clip
            let r = layer.convert(layer.bounds, to: root)
            if let c = layer.backgroundColor {
                var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&cr, green: &cg, blue: &cb, alpha: &a), a > 0.5,
                   abs(cr - marker.r) < 0.02, abs(cg - marker.g) < 0.02, abs(cb - marker.b) < 0.02 {
                    out.append(r.intersection(clip))
                }
            }
            if layer.masksToBounds { clip = clip.intersection(r) }
            layer.sublayers?.forEach { visit($0, clip) }
        }
        visit(root, .infinite)
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
    /// D76 `.keepTextSize` (16+): the same drawn frame, laid out at `(402 · s, R + g)` (the reader's box), the fixed-size
    /// text mark at its point size.
    @Test(arguments: OSPath.allCases, Self.cases)
    func aPullIsARenderTimeScaleOfTheRestingLayout(path: OSPath, c: StretchCase) {
        let box = Box(), counts = BodyCount(), size = c.size
        let s = makeState(path)
        let w = withOSPath(path) { window(Host(state: s, size: size, box: box, counts: counts, content: c.content)) }
        let grows = Self.grows(c.content, s)
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
            let tag = "\(path) \(size) \(c.content) g \(g)"
            let laid = grows ? CGSize(width: 402 * (resting + g) / resting, height: resting + g) : CGSize(width: 402, height: resting)
            #expect(abs(box.size.height - laid.height) < 0.5 && abs(box.size.width - laid.width) < 0.5,
                    "\(tag): laid out at \(laid) (\(box.size), R \(resting))")
            if let t = Self.frames(of: Self.textMarker, in: w).first {
                let k = grows ? 1 : (resting + g) / resting
                #expect(abs(t.width - 60 * k) < 0.5 && abs(t.height - 20 * k) < 0.5 && abs(t.midX - 201) < 0.5,
                        "\(tag): the text mark \(t) (\(grows ? "its point size" : "magnified by \(k)"))")
            } else {
                Issue.record("\(tag): no text mark")
            }
            let header = Self.frames(of: Self.headerMarker, in: w), content = Self.frames(of: Self.contentMarker, in: w)
            guard let f = header.first, let c = content.first, header.count == 1 else {
                Issue.record("\(tag): marker layers header \(header) content \(content)"); continue
            }
            let scale = (resting + g) / resting
            #expect(abs(f.minY - top0) < 0.5, "\(tag): top pinned at top0 \(top0) (\(f))")
            #expect(abs(f.maxY - (top0 + resting + g)) < 0.5, "\(tag): bottom edge grown by the pull (\(f))")
            if grows {
                #expect(abs(f.width - 402) < 0.5 && abs(f.minX) < 0.5, "\(tag): laid out grown, drawn cut to the width (\(f))")
            } else {
                #expect(abs(f.width - 402 * scale) < 0.5 && abs(f.midX - 201) < 0.5, "\(tag): uniform scale, centred (\(f), s \(scale))")
            }
            if let d = Self.drawnFrames(of: Self.headerMarker, in: w).first {
                #expect(abs(d.minX) < 1e-6 && abs(d.maxX - 402) < 1e-6 && abs(d.minY - top0) < 0.5
                            && abs(d.maxY - (top0 + resting + g)) < 0.5, "\(tag): drawn \(d) (exactly the width: R5)")
            }
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
        #expect(ZTronRenderCounters.value("header.content") == 0, "\(path) \(size): no header content body for a pull")
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
        var content: ZTronHeaderStretchContent = .keepTextMagnified
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Content(counts: counts) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), pull: .stretch,
                                   stretchContent: content) { _ in SizeProbe(box: box) }
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
    /// D76 `.keepTextSize`: every layout is the grown aspect box `(W · s, R + g)`, still on the aspect height of its width.
    @Test(arguments: OSPath.allCases, [ZTronHeaderStretchContent.keepTextMagnified, .keepTextSize])
    func aStretchHoldKeepsTheScaleAcrossAnAnimatedWidthChange(path: OSPath, content: ZTronHeaderStretchContent) {
        let box = Box(), counts = BodyCount(), width = Width()
        let s = makeState(path)
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        let w = withOSPath(path) { window(HoldHost(state: s, width: width, box: box, counts: counts, content: content)) }
        defer { unhost(w) }
        resolve(s)
        let installed = counts.bodies
        #if DEBUG
        let builds = ZTronRenderCounters.value("header.builder")
        #endif
        s.beginRefreshing()
        pump(0.6)
        let hold = s.headerGeometry?.stretch ?? 0
        #expect(hold > 30, "\(path): the hold stretches the header (\(String(describing: s.headerGeometry)))")
        // The hold's stretch runs no content body and no header builder (the install's runs are counted apart).
        #expect(counts.bodies == installed, "\(path): no content body for the hold (\(counts.bodies - installed))")
        #if DEBUG
        print("STRETCH \(path) builder runs: install \(builds), after the hold \(ZTronRenderCounters.value("header.builder"))")
        #expect(ZTronRenderCounters.value("header.builder") == builds,
                "\(path): builder runs for the hold (\(ZTronRenderCounters.value("header.builder") - builds); install \(builds))")
        #expect(ZTronRenderCounters.value("header.frame") > 0, "\(path): the leaf drew the hold")
        #endif
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
        let tag = "\(path) \(content)"
        if Self.grows(content, s) {
            let grown = box.sizes.filter { $0.width > 241.5 * 1.1 || $0.width > 402.5 }
            #expect(!grown.isEmpty, "\(tag): laid out grown (\(box.sizes))")
        }
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
            if Self.grows(content, s) {
                if let d = Self.drawnFrames(of: Self.headerMarker, in: w).first {
                    #expect(abs(d.width - 241) < 0.5 && abs(d.midX - c.midX) < 0.5, "\(tag): end: drawn \(d)")
                }
            } else {
                #expect(abs(f.width - 241 * (r + hold) / r) < 0.5, "\(tag): end: scaled width \(f.width)")
            }
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

    /// The user's setup (D69's motivating bug): `NavigationView` + `GeometryReader`, `.aspectRatio(16/9, min: 0)`,
    /// `.refit`, a fade, and an aspect-fit 16:9 content with `maxWidth: .infinity` (the user's `Image`). Before D69 the
    /// pull grew the frame and the aspect-fit content stayed `W × W·9/16` inside it: nothing grew. Now the drawn content
    /// grows by the pull: its bottom edge moves down by `g`, its width by the same scale, its top stays.
    /// D76: the same pixels with `.keepTextSize` (the image is laid out `W · s` wide instead of magnified).
    @Test(arguments: OSPath.allCases, [ZTronHeaderStretchContent.keepTextMagnified, .keepTextSize])
    func theUsersAspectFitImageGrowsWithThePull(path: OSPath, content: ZTronHeaderStretchContent) {
        struct UserScreen: View {
            let state: ZTronScrollState
            let counts: BodyCount
            let content: ZTronHeaderStretchContent
            var body: some View {
                NavigationView {
                    GeometryReader { _ in
                        ZTronScrollView(.vertical, state: state) { Content(counts: counts) }
                            .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 0.0), pull: .stretch,
                                               fade: .linear(to: Color(white: 0.5)), overflow: .refit,
                                               stretchContent: content) { _ in
                                HeaderStretchScaleTests.color(HeaderStretchScaleTests.headerMarker)
                                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                    .frame(maxWidth: .infinity)
                            }
                    }
                }
                .navigationViewStyle(.stack)
            }
        }
        let counts = BodyCount()
        let s = makeState(path)
        let w = withOSPath(path) { window(UserScreen(state: s, counts: counts, content: content)) }
        defer { unhost(w) }
        resolve(s)
        guard let resting = s.peek.metrics.header?.resting,
              let rest = Self.frames(of: Self.headerMarker, in: w).first else {
            Issue.record("\(path): unresolved or no marker"); return
        }
        #expect(abs(rest.width - 402) < 0.5 && abs(rest.height - resting) < 0.5, "\(path): at rest \(rest), R \(resting)")
        let bodies = counts.bodies
        for g in [40, 100] as [CGFloat] {
            s.track(offset: CGPoint(x: 0, y: -g - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.1)
            guard let f = Self.frames(of: Self.headerMarker, in: w).first,
                  let c = Self.frames(of: Self.contentMarker, in: w).first else {
                Issue.record("\(path) g \(g): no marker"); continue
            }
            let scale = (resting + g) / resting
            #expect(abs(f.minY - rest.minY) < 0.5 && abs(f.maxY - (rest.maxY + g)) < 0.5,
                    "\(path) g \(g): the image grows down by the pull (\(rest) -> \(f))")
            if Self.grows(content, s) {
                // The image is laid out `402 · s` wide (the reader's box, not a layer: SwiftUI draws it cut to the width).
                let d = Self.drawnFrames(of: Self.headerMarker, in: w).first ?? .null
                #expect(abs(d.minX) < 1e-6 && abs(d.maxX - 402) < 1e-6, "\(path) g \(g): drawn \(d)")
            } else {
                #expect(abs(f.width - 402 * scale) < 0.5 && abs(f.midX - 201) < 0.5, "\(path) g \(g): and wider by its scale (\(f))")
            }
            #expect(abs(f.maxY - c.minY) < 0.5, "\(path) g \(g): its bottom on the content's top (\(f.maxY) vs \(c.minY))")
        }
        #expect(counts.bodies == bodies, "\(path): no content body")
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
        effect.animatableData = AnimatablePair(-50, 0)
        clip.animatableData = AnimatablePair(-50, 0)
        #expect(effect.live.stretch == 50 && clip.live.stretch == 50 && effect.live.stateHeight == 240,
                "following: the stretch re-derived, the layout height not (\(effect.live))")
        live.followsOffset = false
        live.stretch = 60
        effect = HeaderStretchEffect(live: live)
        effect.animatableData = AnimatablePair(-10, 0)
        #expect(effect.live.stretch == 60, "held: only o′ moves")
        // D76: the second component is the laid-out share; it moves only `m` (and the pin, D79, replaces only `o′`).
        effect.animatableData = AnimatablePair(-10, 0.5)
        #expect(effect.live.stretch == 60 && effect.live.layoutShare == 0.5 && effect.live.layoutStretch == 30
                    && effect.live.scaleStretch == 30, "\(effect.live)")
        #expect(effect.animatableData == AnimatablePair(-10, 0.5))
    }

    /// D76 math (pure): the clip without a laid-out share is D69's `HeaderStretchClip.rect` bit for bit; with one it is the
    /// grown frame's centred `W` at the drawn height (or the frame's own `W` on the 15 path's slot-wide frame), exact under
    /// an affine interpolation of the frame; the grown size and the side pad are the identity / 0 without a share and for
    /// non-finite input; the aspect side pad is free of `W`; the shares are exact at `m = 0` and `m = 1`.
    @Test func theStretchContentMathReducesToD69WithoutALaidOutShare() {
        let rects = [CGRect(x: 0, y: 0, width: 402, height: 240), CGRect(x: 3.5, y: -2, width: 241, height: 135.5625),
                     CGRect(x: 0, y: 0, width: 393, height: 0)]
        for r in rects {
            for g in [0, 0.25, 60, 1234.5, .nan, .infinity, -5] as [CGFloat] {
                let d69 = HeaderStretchClip.rect(in: r, stretch: g)
                let mine = HeaderMath.stretchClip(in: r, layoutStretch: 0, scaleStretch: g, grownFrame: true)
                #expect(mine == d69 || (mine.height.isNaN && d69.height.isNaN), "g_l 0: D69's clip \(r) g \(g): \(mine) vs \(d69)")
                #expect(HeaderMath.stretchClip(in: r, layoutStretch: 0, scaleStretch: g, grownFrame: false) == mine)
            }
        }
        // Grown (16+): the stack proposed `grownSize`, its clip the centred W at its own height (g_s = 0).
        let W: CGFloat = 402, h: CGFloat = 240, g: CGFloat = 60
        let grown = HeaderMath.grownSize(width: W, layoutHeight: h, stretch: g)
        #expect(grown == CGSize(width: W * 1.25, height: 300), "grown \(grown)")
        let frame = CGRect(x: 201 - grown.width / 2, y: 10, width: grown.width, height: grown.height)
        let clip = HeaderMath.stretchClip(in: frame, layoutStretch: g, scaleStretch: 0, grownFrame: true)
        #expect(abs(clip.width - W) < 1e-9 && abs(clip.midX - 201) < 1e-9 && clip.minY == 10 && clip.height == 300, "\(clip)")
        // R5: SwiftUI places the grown frame at pixel-rounded edges (402 · 270/240 = 452.25 laid out as 452 at 3x): the
        // derived W is 401.78; the inset snapped to the pixel grid puts the clip on the slot's edges.
        let rounded = CGRect(x: -25, y: 0, width: 452, height: 270)
        let raw = HeaderMath.stretchClip(in: rounded, layoutStretch: 30, scaleStretch: 0, grownFrame: true)
        let snapped = HeaderMath.stretchClip(in: rounded, layoutStretch: 30, scaleStretch: 0, grownFrame: true, displayScale: 3)
        #expect(abs(raw.width - 452 * 240 / 270) < 1e-9, "\(raw)")
        #expect(snapped == CGRect(x: 0, y: 0, width: 402, height: 270), "\(snapped)")
        // The 15 path's frame is the slot's W already: only the height.
        let slot = CGRect(x: 0, y: 0, width: W, height: 300)
        #expect(HeaderMath.stretchClip(in: slot, layoutStretch: g, scaleStretch: 0, grownFrame: false) == slot)
        // A mix (m = 0.5): laid out at h + 30, magnified by (h + 60)/(h + 30): the drawn height is h + g, the width W.
        let half = HeaderMath.grownSize(width: W, layoutHeight: h, stretch: 30)
        let mixed = HeaderMath.stretchClip(in: CGRect(origin: .zero, size: half), layoutStretch: 30, scaleStretch: 30,
                                           grownFrame: true)
        #expect(abs(mixed.width - W) < 1e-9 && abs(mixed.height - 300) < 1e-9, "mix \(mixed)")
        // Exact under the affine interpolation of an aspect frame (W(t) + g·r, W(t)/r + g).
        let r: CGFloat = 16.0 / 9.0
        for t in stride(from: 0.0, through: 1.0, by: 0.125) {
            let w = 402 + (241 - 402) * CGFloat(t)
            let f = CGRect(x: 0, y: 0, width: w + g * r, height: w / r + g)
            let c = HeaderMath.stretchClip(in: f, layoutStretch: g, scaleStretch: 0, grownFrame: true)
            #expect(abs(c.width - w) < 1e-9, "t \(t): \(c.width) vs \(w)")
        }
        // Identity / zero without a share, for h ≤ 0 and non-finite input.
        for bad in [0, -3, .nan, .infinity] as [CGFloat] {
            #expect(HeaderMath.grownSize(width: W, layoutHeight: h, stretch: bad) == CGSize(width: W, height: h))
            #expect(HeaderMath.grownSidePad(width: W, layoutHeight: h, stretch: bad) == 0)
            #expect(HeaderMath.grownSize(width: W, layoutHeight: bad, stretch: g).width == W)
        }
        #expect(HeaderMath.grownSidePad(width: .nan, layoutHeight: h, stretch: g) == 0)
        // The aspect side pad is g · r / 2 at every width.
        for w in [402, 241, 874.5] as [CGFloat] {
            #expect(abs(HeaderMath.grownSidePad(width: w, layoutHeight: w / r, stretch: g) - g * r / 2) < 1e-9)
        }
        // The shares: exact at the ends, the sum is the stretch.
        let m = HeaderMetrics(min: 64, resting: 240, behavior: .stretch, width: 402)
        var live = HeaderLiveInput(size: .fixed(min: 64, max: 240), metrics: m, stretch: 60.1, stateHeight: 240)
        #expect(live.layoutStretch == 0 && live.scaleStretch == 60.1)
        live.layoutShare = 1
        #expect(live.layoutStretch == 60.1 && live.scaleStretch == 0)
        live.layoutShare = 0.25
        #expect(abs(live.layoutStretch - 15.025) < 1e-12 && abs(live.layoutStretch + live.scaleStretch - 60.1) < 1e-12)
        // The fade's pull weight R (HeaderFadeOverlay): the grown frame's height less g_l, the frame itself at m = 0.
        live.stretch = 60
        live.layoutShare = 1
        #expect(HeaderFadeOverlay.restingHeight(300, live) == 240)
        live.layoutShare = 0
        #expect(HeaderFadeOverlay.restingHeight(240.123, live) == 240.123)
        live.stretch = .nan
        #expect(live.layoutStretch == 0)
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
        // D76 `.keepTextSize` (m = 1, set by the leaf; the commit never changes it): the grown proposal, the clip and the
        // (identity) effect are bit-identical too.
        var b1 = before, a1 = after
        b1.layoutShare = 1
        a1.layoutShare = 1
        let gb = HeaderMath.grownSize(width: 241, layoutHeight: resting, stretch: b1.layoutStretch)
        let ga = HeaderMath.grownSize(width: 241, layoutHeight: resting, stretch: a1.layoutStretch)
        #expect(gb == ga && gb.height == resting + 60, "grown \(gb) vs \(ga)")
        let frame = CGRect(origin: .zero, size: ga)
        #expect(HeaderMath.stretchClip(in: frame, layoutStretch: b1.layoutStretch, scaleStretch: b1.scaleStretch, grownFrame: true)
                    == HeaderMath.stretchClip(in: frame, layoutStretch: a1.layoutStretch, scaleStretch: a1.scaleStretch,
                                              grownFrame: true))
        #expect(HeaderStretchEffect.transform(size: ga, stretch: a1.scaleStretch) == .identity)
    }

    /// D76, the mix (pure): for a static laid-out share `m` ∈ {0, ½, 1} the drawn stack (the layout frame
    /// `grownSize(W, h, m·g)` placed at the slot's top centre, magnified by the effect's `s_eff`) and its drawn clip are
    /// the same rect, `W × (h + g)` from the slot's top, to ½ pt: the frame does not move whatever `m` is.
    @Test func aMixIsTheSameDrawnFrame() {
        let W: CGFloat = 402
        for (h, g) in [(240, 60), (226.125, 120), (135.5625, 33.3)] as [(CGFloat, CGFloat)] {
            var drawn: [CGRect] = []
            for m in [0, 0.5, 1] as [CGFloat] {
                let metrics = HeaderMetrics(min: 64, resting: h, behavior: .stretch, width: W)
                var live = HeaderLiveInput(size: .fixed(min: 64, max: h), metrics: metrics, stretch: g, stateHeight: h)
                live.layoutShare = m
                let size = HeaderMath.grownSize(width: W, layoutHeight: h, stretch: live.layoutStretch)
                let origin = CGPoint(x: W / 2 - size.width / 2, y: 0)
                let t = HeaderStretchEffect.transform(size: size, stretch: live.scaleStretch)
                    .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
                let stack = CGRect(origin: .zero, size: size).applying(t)
                // The clip is the effected view's shape, in its unscaled layout frame (not transformed by the effect).
                let clip = HeaderMath.stretchClip(in: CGRect(origin: .zero, size: size), layoutStretch: live.layoutStretch,
                                                  scaleStretch: live.scaleStretch, grownFrame: true)
                    .offsetBy(dx: origin.x, dy: origin.y)
                let tag = "h \(h) g \(g) m \(m)"
                #expect(abs(stack.minY) < 1e-9 && abs(stack.height - (h + g)) < 1e-9 && abs(stack.midX - W / 2) < 1e-9,
                        "\(tag): the stack \(stack)")
                #expect(abs(stack.width - W * (h + g) / h) < 1e-9, "\(tag): the stack is W · s wide \(stack)")
                #expect(abs(clip.minX) < 0.5 && abs(clip.width - W) < 0.5 && abs(clip.minY) < 0.5
                            && abs(clip.height - (h + g)) < 0.5, "\(tag): the clip \(clip)")
                drawn.append(clip)
            }
            #expect(drawn.allSatisfy { abs($0.minX - drawn[0].minX) < 0.5 && abs($0.maxX - drawn[0].maxX) < 0.5
                        && abs($0.maxY - drawn[0].maxY) < 0.5 }, "h \(h) g \(g): \(drawn)")
        }
    }
}
