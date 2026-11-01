import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// D68 (`collapse: .slideBehind(parallax:backdrop:)`): the header keeps its resting height `R(W, H)`, is drawn BEHIND the
/// content (the container's `.background` slot) and moves up by `k · p · R` (16+ `HeaderSlotLayout` placement, 15 / forced
/// `HeaderTranslation`, both from the layout's own `R`), so the content slides over it. Drawn frames are read from
/// marker-coloured layers (`HeaderStretchScaleTests.frames`), presented ones mid-animation. The hit-testing of the uncovered
/// band and VoiceOver's order need a live app: `HeaderUITests.testSlideBehind…`.
@MainActor
@Suite(.serialized)
struct HeaderSlideBehindTests {
    typealias T = HeaderStretchScaleTests
    static let backdropMarker = (r: 0.27, g: 0.53, b: 0.11)

    /// The content: the content marker strip on top (its drawn top is the content's), a tall filler, `@State` identity.
    struct Content: View {
        let counts: BodyCount
        @State private var id = UUID()
        var body: some View {
            counts.bodies += 1
            counts.ids.insert(id)
            return VStack(spacing: 0) {
                T.color(T.contentMarker).frame(height: 8)
                Color.green.frame(height: 3000)
            }
        }
    }

    final class Model: ObservableObject {
        @Published var collapse: ZTronHeaderCollapseBehavior
        @Published var narrow = false
        init(_ collapse: ZTronHeaderCollapseBehavior) { self.collapse = collapse }
    }

    struct Host: View {
        let state: ZTronScrollState
        let size: ZTronHeaderSize
        @ObservedObject var model: Model
        let box: T.Box
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Content(counts: counts) }
                .withScalingHeader(size: size, collapse: model.collapse) { _ in T.Header(size: size, box: box) }
                .frame(width: model.narrow ? 241 : 402)
                .frame(maxWidth: .infinity)
        }
    }

    enum Start: CaseIterable { case rest, half, collapsed }

    func host(_ path: OSPath, size: ZTronHeaderSize, model: Model, start: Start = .rest, box: T.Box,
              counts: BodyCount) -> (ZTronScrollState, UIWindow) {
        let s = makeState(path)
        switch start {
        case .rest: break
        case .half: s.snapHeader(to: .progress(0.5), animated: false)
        case .collapsed: s.snapHeader(to: .collapsed, animated: false)
        }
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: Host(state: s, size: size, model: model, box: box, counts: counts))
            w.makeKeyAndVisible()
            pump(0.4)
            return w
        }
        var n = 0
        while s.peek.metrics.header == nil, n < 60 { pump(0.1); n += 1 }
        pump(0.3)
        return (s, w)
    }

    nonisolated static let sizes: [ZTronHeaderSize] = [.fixed(min: 64, max: 240), .aspectRatio(16.0 / 9.0, min: 64), .fit(min: 64)]

    /// At rest, half covered and fully covered, for parallax 0, 0.5 and 1: the band is `R` (`min` ignored), the header is
    /// drawn `R` tall at `top0 − k · p · R` (laid out at `R`: the stack's proposal), the content's top at `top0 + R − p · R`
    /// (on the header's bottom edge only for `k = 1`; over it otherwise), the geometry reports the covered fraction and
    /// the drawn height `R`.
    @Test(arguments: OSPath.allCases, Self.sizes)
    func theHeaderKeepsItsHeightAndMovesByTheParallax(path: OSPath, size: ZTronHeaderSize) {
        for k: CGFloat in [0, 0.5, 1] {
            for start in Start.allCases {
                let box = T.Box(), counts = BodyCount()
                let (s, w) = host(path, size: size, model: Model(.slideBehind(parallax: k)), start: start, box: box, counts: counts)
                defer { unhost(w) }
                let tag = "\(path) \(size) k \(k) \(start)"
                guard let m = s.peek.metrics.header, let g = s.headerGeometry else { Issue.record("\(tag): unresolved"); continue }
                let p: CGFloat = start == .rest ? 0 : start == .half ? 0.5 : 1
                let top0 = HeaderMath.top0(s.peek.metrics), r = m.resting
                #expect(m.band == r && m.min == 0, "\(tag): band \(m.band) = R \(r), min ignored (\(m.min))")
                #expect(abs(g.progress - p) < 0.001 && abs(g.height - r) < 0.01, "\(tag): geometry \(g)")
                #expect(abs(box.size.height - r) < 0.5, "\(tag): laid out at R (\(box.size), R \(r))")
                guard let f = T.frames(of: T.headerMarker, in: w).first, let c = T.frames(of: T.contentMarker, in: w).first else {
                    Issue.record("\(tag): no marker layers"); continue
                }
                #expect(abs(f.height - r) < 0.5, "\(tag): drawn height \(f.height) vs R \(r)")
                #expect(abs(f.minY - (top0 - k * p * r)) < 0.5, "\(tag): drawn top \(f.minY) vs \(top0 - k * p * r)")
                #expect(abs(c.minY - (top0 + r - p * r)) < 0.5, "\(tag): content top \(c.minY) vs \(top0 + r - p * r)")
                #expect(abs(f.midX - c.midX) < 0.5 && abs(f.width - c.width) < 0.5, "\(tag): lateral \(f) vs \(c)")
            }
        }
    }

    /// A transaction-driven scroll (`withAnimation { scroll(to:) }`) into the band and back: on every sampled frame the
    /// drawn header top is `top0 − k · c` with `c` read from the drawn content's top (the parallax interpolates with the
    /// content in the same transaction), the height stays `R`. No content body.
    @Test(arguments: OSPath.allCases)
    func aTransactionDrivenScrollMovesTheHeaderByTheParallaxEveryFrame(path: OSPath) {
        let box = T.Box(), counts = BodyCount(), k: CGFloat = 0.5
        let (s, w) = host(path, size: .fixed(min: 64, max: 240), model: Model(.slideBehind(parallax: k)), box: box, counts: counts)
        defer { unhost(w) }
        let bodies = counts.bodies
        let top0 = HeaderMath.top0(s.peek.metrics), r: CGFloat = 240
        func run(_ label: String, _ motion: () -> Void) {
            var worst: CGFloat = 0, height: CGFloat = 0, samples = 0, inBand = 0
            motion()
            for _ in 0..<45 {
                pump(1.0 / 60)
                guard let f = T.frames(of: T.headerMarker, in: w, presented: true).first,
                      let c = T.frames(of: T.contentMarker, in: w, presented: true).first else { continue }
                let covered = top0 + r - c.minY
                worst = max(worst, abs(f.minY - (top0 - k * min(max(covered, 0), r))))
                height = max(height, abs(f.height - r))
                samples += 1
                if covered > 1, covered < r - 1 { inBand += 1 }
            }
            pump(0.3)
            #expect(samples >= 10 && worst < 1, "\(path) \(label): header top vs top0 − k·c, worst \(worst) over \(samples)")
            #expect(height < 0.5, "\(path) \(label): drawn height off R by \(height)")
            #expect(inBand >= 3, "\(path) \(label): frames inside the band \(inBand)")
        }
        let base = HeaderMath.base(s.peek.metrics)
        run("into the band") { withAnimation(.linear(duration: 0.5)) { s.scroll(to: CGPoint(x: 0, y: 180 - base)) } }
        #expect(abs((s.headerGeometry?.progress ?? -1) - 0.75) < 0.01, "\(path): p 0.75 (\(String(describing: s.headerGeometry)))")
        run("back to rest") { withAnimation(.linear(duration: 0.5)) { s.scroll(to: CGPoint(x: 0, y: -base)) } }
        run("snap covered") { s.snapHeader(to: .collapsed, animated: true) }
        run("snap uncovered") { s.snapHeader(to: .expanded, animated: true) }
        #expect(counts.bodies == bodies, "\(path): no content body (\(counts.bodies - bodies))")
    }

    /// Half covered, the app animates the scroll view's width (402 → 241: `R` 226 → 136): every layout is the aspect height
    /// at its width (`R(W)`, never a compressed height), and on every sampled frame the drawn header top is `top0 − k · c`
    /// with `c = top0 + R_drawn − content top` (the parallax interpolates with the drawn size), laterally aligned with the
    /// content; the progress is kept (S7) and the end state is exact. No content body; one builder run (the parent rebuild).
    @Test(arguments: OSPath.allCases)
    func anAnimatedWidthChangeAtHalfCoverKeepsTheParallax(path: OSPath) {
        let box = T.Box(), counts = BodyCount(), model = Model(.slideBehind(parallax: 0.5))
        let (s, w) = host(path, size: .aspectRatio(16.0 / 9.0, min: 64), model: model, start: .half, box: box, counts: counts)
        defer { unhost(w) }
        s.endOfTurn()
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        let bodies = counts.bodies, k: CGFloat = 0.5
        let top0 = HeaderMath.top0(s.peek.metrics)
        box.sizes.removeAll()
        withAnimation(.linear(duration: 0.5)) { model.narrow = true }
        var worst: CGFloat = 0, lateral: CGFloat = 0, samples = 0
        for _ in 0..<40 {
            pump(1.0 / 60)
            guard let f = T.frames(of: T.headerMarker, in: w, presented: true).first,
                  let c = T.frames(of: T.contentMarker, in: w, presented: true).first else { continue }
            let covered = top0 + f.height - c.minY
            worst = max(worst, abs(f.minY - (top0 - k * covered)))
            lateral = max(lateral, abs(f.midX - c.midX))
            samples += 1
        }
        pump(0.5)
        let tag = "\(path)"
        let stale = box.sizes.filter { abs($0.height - $0.width * 9 / 16) > 0.5 }
        #expect(stale.isEmpty, "\(tag): layouts off R(W) \(stale) of \(box.sizes)")
        #expect(samples >= 10 && worst < 1, "\(tag): header top vs top0 − k·c, worst \(worst) over \(samples)")
        #expect(lateral < 1, "\(tag): lateral, worst \(lateral)")
        let r = s.peek.metrics.header?.resting ?? -1
        #expect(abs(r - 241 * 9 / 16) < 0.5 && abs((s.headerGeometry?.progress ?? -1) - 0.5) < 0.01,
                "\(tag): R \(r), progress kept (\(String(describing: s.headerGeometry)))")
        if let f = T.frames(of: T.headerMarker, in: w).first, let c = T.frames(of: T.contentMarker, in: w).first {
            #expect(abs(f.minY - (top0 - k * 0.5 * r)) < 0.5 && abs(f.height - r) < 0.5 && abs(c.minY - (top0 + r / 2)) < 0.5,
                    "\(tag): end: header \(f), content top \(c.minY), top0 \(top0), R \(r)")
        } else {
            Issue.record("\(tag): no marker layers at the end")
        }
        #expect(counts.bodies == bodies, "\(tag): no content body (\(counts.bodies - bodies))")
        #if DEBUG
        #expect(ZTronRenderCounters.value("header.builder") <= 1,
                "\(tag): builder runs \(ZTronRenderCounters.value("header.builder")) (the parent rebuild: 1)")
        #endif
    }

    /// D51 / D62 bit-stability: half covered across an unanimated resize commit (new width's metrics, the target realised
    /// ulps from the anchor), the leaf's live input keeps the progress and the offset, its layout height is `R` and the
    /// translation the layout derives from its own `R(W)` is the same before and after.
    @Test func aHalfCoveredHeaderIsBitStableAcrossTheUnanimatedCommit() {
        var m = ScrollMetrics()
        m.viewportSize = CGSize(width: 402, height: 874)
        m.safeAreaInsets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        m.header = HeaderMetrics(min: 0, resting: 226.125, behavior: .preserve, collapse: .slideBehind(parallax: 0.5), width: 402)
        m.adjustedContentInset = EdgeInsets(top: 62 + 226.125, leading: 0, bottom: 34, trailing: 0)
        m.resize.isOpen = true
        m.resize.intent = ResizeIntent(normalizedCenter: CGPoint(x: 0.5, y: 0.5), scale: 1, atFit: true, header: .progress(0.5))
        let size = ZTronHeaderSize.aspectRatio(16.0 / 9.0, min: 64)
        let before = HeaderFrameModifier.liveInput(size: size, overflow: .uncapped, metrics: m, edges: .vertical,
                                                   target: CGPoint(x: 0, y: 113.0625 - HeaderMath.base(m)), zoom: 1, held: 113.0625)
        var n = m
        let resting: CGFloat = 241.0 * 9 / 16
        n.viewportSize = CGSize(width: 241, height: 874)
        n.header = HeaderMetrics(min: 0, resting: resting, behavior: .preserve, collapse: .slideBehind(parallax: 0.5), width: 241)
        n.adjustedContentInset.top = 62 + resting
        let after = HeaderFrameModifier.liveInput(size: size, overflow: .uncapped, metrics: n, edges: .vertical,
                                                  target: CGPoint(x: 0, y: (resting / 2).nextUp - HeaderMath.base(n)), zoom: 1,
                                                  held: before.offset)
        #expect(!before.followsOffset && !after.followsOffset)
        #expect(before.progress == 0.5 && after.progress == 0.5 && before.offset == after.offset && before.parallax == 0.5
                    && after.parallax == 0.5 && before.translation == 0 && after.translation == 0, "\(before) vs \(after)")
        #expect(after.stateHeight == resting, "the layout height is R (\(after.stateHeight))")
        #expect(after.visibleHeight == resting / 2, "the visible height is R − c (\(after.visibleHeight))")
        // The layout's height at the new width is R(241) on both sides of the commit; so is the translation.
        let h0 = HeaderMath.liveHeight(width: 241, containerHeight: 874 - 96, natural: nil, before)
        let h1 = HeaderMath.liveHeight(width: 241, containerHeight: 874 - 96, natural: nil, after)
        #expect(h0 == h1 && abs(h1 - resting) < 1e-9, "layout heights \(h0) / \(h1)")
        #expect(HeaderTranslation.translation(before, layoutHeight: h0) == HeaderTranslation.translation(after, layoutHeight: h1))
        #expect(HeaderTranslation.translation(after, layoutHeight: h1) == -0.25 * h1)
        // `at(offset:)` re-derives the same values as the leaf while it follows the offset.
        var following = after
        following.followsOffset = true
        let mid = following.at(offset: resting * 0.3)
        #expect(abs(mid.progress - 0.3) < 1e-9 && mid.stateHeight == resting && abs(mid.visibleHeight - resting * 0.7) < 1e-9)
    }

    /// The 15 / forced plan and the 16+ live height lay a `.slideBehind` header out at `R` at every progress (the
    /// translation is the layout's, `HeaderTranslation`), on every size path; the leaf's state height is `R`.
    @Test func theLayoutHeightIsTheRestingHeightAtEveryProgress() {
        let slide = ZTronHeaderCollapseBehavior.Kind.slideBehind(parallax: 0.5)
        let m = HeaderMetrics(min: 0, resting: 226.125, behavior: .preserve, collapse: slide, width: 402)
        for p: CGFloat in [0, 0.5, 1] {
            let h = HeaderLiveInput.layoutHeight(m, progress: p)
            #expect(h == 226.125, "state height at p \(p): \(h)")
            var live = HeaderLiveInput(size: .aspectRatio(16.0 / 9.0, min: 64), metrics: m, progress: p, stateHeight: h)
            var plan = HeaderFallbackPlan(live)
            #expect(plan.ratio == 16.0 / 9.0 && plan.innerPad == 0 && plan.outerPad == 0 && plan.floor == 0,
                    ".aspectRatio at p \(p): the resting aspect box (\(plan))")
            #expect(HeaderMath.liveHeight(width: 402, containerHeight: nil, natural: nil, live) == 226.125)
            #expect(abs(HeaderMath.liveHeight(width: 600, containerHeight: nil, natural: nil, live) - 337.5) < 1e-9,
                    "R(W) at another width, not compressed")
            #expect(HeaderTranslation.translation(live, layoutHeight: 337.5) == -0.5 * p * 337.5)
            live = HeaderLiveInput(size: .fit(min: 64), metrics: m, progress: p, stateHeight: h)
            live.natural = 226.125
            plan = HeaderFallbackPlan(live)
            #expect(plan.fitRest && plan.outerPad == 0, ".fit at p \(p): its ideal height (\(plan))")
            let fixed = HeaderMetrics(min: 0, resting: 240, behavior: .preserve, collapse: slide, width: 402)
            live = HeaderLiveInput(size: .fixed(min: 64, max: 240), metrics: fixed, progress: p,
                                   stateHeight: HeaderLiveInput.layoutHeight(fixed, progress: p))
            plan = HeaderFallbackPlan(live)
            #expect(plan.minHeight == 240 && plan.maxHeight == 240, ".fixed at p \(p): R (\(plan))")
            #expect(HeaderMath.liveHeight(width: 402, containerHeight: nil, natural: nil, live) == 240)
            #expect(live.visibleHeight == 240 - p * 240 && live.parallax == 0.5)
        }
        // `.compress` keeps today's values: the compressed height, no collapse translation.
        let compress = HeaderMetrics(min: 64, resting: 240, behavior: .preserve, width: 402)
        let live = HeaderLiveInput(size: .fixed(min: 64, max: 240), metrics: compress, progress: 0.5,
                                   stateHeight: HeaderLiveInput.layoutHeight(compress, progress: 0.5))
        #expect(live.stateHeight == 152 && live.parallax == 0 && HeaderTranslation.translation(live, layoutHeight: 152) == 0)
    }

    /// Switching `collapse:` at run time (compress → slideBehind → with a backdrop → without → compress) runs no content
    /// body and keeps the content's identity; the header moves to the other slot (one builder run per switch, documented:
    /// its `@State` starts over). The backdrop is a layer exactly behind the content's rect, in content space (it moves
    /// with the content); without one nothing is drawn there.
    @Test(arguments: OSPath.allCases)
    func aModeSwitchAndABackdropRunNoContentBody(path: OSPath) {
        let box = T.Box(), counts = BodyCount(), model = Model(.compress)
        let (s, w) = host(path, size: .fixed(min: 64, max: 240), model: model, start: .half, box: box, counts: counts)
        defer { unhost(w) }
        let bodies = counts.bodies
        let top0 = HeaderMath.top0(s.peek.metrics)
        func step(_ label: String, _ c: ZTronHeaderCollapseBehavior, header: (CGFloat, CGFloat), backdrop: Bool) {
            #if DEBUG
            ZTronRenderCounters.reset()
            #endif
            model.collapse = c
            pump(0.5)
            let tag = "\(path) \(label)"
            #expect(counts.bodies == bodies, "\(tag): no content body (\(counts.bodies - bodies))")
            #expect(counts.ids.count == 1, "\(tag): the content keeps its identity (\(counts.ids.count))")
            #if DEBUG
            #expect(ZTronRenderCounters.value("header.builder") <= 1, "\(tag): builder runs \(ZTronRenderCounters.value("header.builder"))")
            #endif
            let f = T.frames(of: T.headerMarker, in: w).first
            #expect(f.map { abs($0.minY - header.0) < 0.5 && abs($0.height - header.1) < 0.5 } == true,
                    "\(tag): header \(String(describing: f)) vs top \(header.0) height \(header.1)")
            let b = T.frames(of: Self.backdropMarker, in: w)
            let c = T.frames(of: T.contentMarker, in: w).first
            if backdrop {
                #expect(b.count == 1 && c.map { abs(b[0].minY - $0.minY) < 0.5 && abs(b[0].height - 3008) < 0.5
                                                && abs(b[0].width - $0.width) < 0.5 } == true,
                        "\(tag): the backdrop covers the content's rect: \(b) vs content \(String(describing: c))")
            } else {
                #expect(b.isEmpty, "\(tag): no backdrop drawn (\(b))")
            }
        }
        // Half of the compress band (240 − 64) / 2 = 88; the slide band is R = 240, the progress kept (0.5 → 120).
        step("slideBehind", .slideBehind, header: (top0 - 0.5 * 120, 240), backdrop: false)
        #expect(abs((s.headerGeometry?.progress ?? -1) - 0.5) < 0.01, "\(path): progress kept across the switch")
        step("backdrop", .slideBehind(backdrop: T.color(Self.backdropMarker)), header: (top0 - 60, 240), backdrop: true)
        step("no backdrop", .slideBehind, header: (top0 - 60, 240), backdrop: false)
        step("compress", .compress, header: (top0, 152), backdrop: false)
    }

    /// Lead decision 3: a `.slideBehind` header that moves up past the scroll view's top is NOT clipped at `top0` but at
    /// the scroll view's own frame (the container's clip): nothing of it is drawn above a scroll view that starts below
    /// other content; inside, the uncovered band shows it.
    @Test(arguments: OSPath.allCases)
    func theHeaderIsClippedAtTheScrollViewsFrame(path: OSPath) {
        struct Screen: View {
            let state: ZTronScrollState
            let box: T.Box
            let counts: BodyCount
            var body: some View {
                VStack(spacing: 0) {
                    Color.white.frame(height: 200)
                    ZTronScrollView(.vertical, state: state) { Content(counts: counts) }
                        .withScalingHeader(size: .fixed(min: 64, max: 240), collapse: .slideBehind(parallax: 1)) { _ in
                            T.Header(size: .fixed(min: 64, max: 240), box: box)
                        }
                }
            }
        }
        let box = T.Box(), counts = BodyCount()
        let s = makeState(path)
        s.snapHeader(to: .progress(0.5), animated: false)
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: Screen(state: s, box: box, counts: counts))
            w.makeKeyAndVisible()
            pump(0.4)
            return w
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 60 { pump(0.1); n += 1 }
        pump(0.3)
        guard let f = T.frames(of: T.headerMarker, in: w).first, let c = T.frames(of: T.contentMarker, in: w).first else {
            Issue.record("\(path): no marker layers"); return
        }
        let top = c.minY - 120         // the scroll view's top: the content is 120 pt into the 240 pt band
        #expect(abs(f.minY - (top - 120)) < 0.5 && abs(f.maxY - c.minY) < 0.5, "\(path): header \(f), content top \(c.minY)")
        // The layer tree rendered on the CPU (`drawHierarchy` needs the render server, absent in this test host): clips
        // (`masksToBounds`) and layer colours are what Core Animation would draw.
        let image = UIGraphicsImageRenderer(bounds: w.bounds).image { ctx in w.layer.render(in: ctx.cgContext) }
        func isHeader(_ y: CGFloat) -> Bool {
            guard let rgb = Self.pixel(image, x: 201, y: y) else { return false }
            return abs(rgb.0 - T.headerMarker.r) < 0.03 && abs(rgb.1 - T.headerMarker.g) < 0.03 && abs(rgb.2 - T.headerMarker.b) < 0.03
        }
        let above = stride(from: max(f.minY, 1), to: top - 1, by: 4).filter(isHeader)
        #expect(above.isEmpty, "\(path): header pixels above the scroll view's top \(top): \(above.prefix(5))")
        #expect(isHeader(top + 10) && isHeader(c.minY - 10), "\(path): the uncovered band shows the header")
    }

    /// The sRGB components (0…1) of a rendered image's pixel at `(x, y)` in points.
    static func pixel(_ image: UIImage, x: CGFloat, y: CGFloat) -> (CGFloat, CGFloat, CGFloat)? {
        guard let cg = image.cgImage else { return nil }
        let px = Int(x * image.scale), py = Int(y * image.scale)
        guard px >= 0, py >= 0, px < cg.width, py < cg.height else { return nil }
        var data = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: -CGFloat(px), y: -CGFloat(cg.height - 1 - py), width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (CGFloat(data[0]) / 255, CGFloat(data[1]) / 255, CGFloat(data[2]) / 255)
    }
}
