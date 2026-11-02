import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// D70 hosted (design M8b-header-behaviors §5 tests 2 and 6): the split fade drawn by `HeaderFadeOverlay` in the header's
/// hot leaf, on both OS paths. A pure red header under a pure white fade (a pixel's opacity is its green channel), read
/// from the layer tree rendered on the CPU (`layer.render(in:)`; no render server in this test host) down one column:
/// every row's opacity is the blend of the frame it is drawn in, the content's drawn top read from the same image
/// (the content marker strip), so the fade never lags the geometry. No content body and no header builder run after the
/// install, through the crossfades (collapse, pull, cover). The live input's pull and bit-stability are pure tests in
/// `HeaderFadeMathTests`.
@MainActor
@Suite(.serialized)
struct HeaderFadeHostedTests {
    typealias T = HeaderStretchScaleTests
    static let white = Color(red: 1, green: 1, blue: 1)
    /// The lab's split: rest from 0.5, collapse from 0, no pull fade.
    static let split = ZTronHeaderFade(rest: .linear(to: white, from: 0.5), collapse: .linear(to: white, from: 0), pull: nil)

    struct Content: View {
        let counts: BodyCount
        var body: some View {
            counts.bodies += 1
            return VStack(spacing: 0) {
                T.color(T.contentMarker).frame(height: 8)
                Color.green.frame(height: 3000)
            }
        }
    }

    struct Host: View {
        let state: ZTronScrollState
        let collapse: ZTronHeaderCollapseBehavior
        let fade: ZTronHeaderFade?
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Content(counts: counts) }
                .withScalingHeader(size: .fixed(min: 64, max: 240), collapse: collapse, fade: fade) { _ in
                    Color(red: 1, green: 0, blue: 0)
                }
                .refresher(refreshView: { _ in Color.clear.frame(width: 20, height: 20) }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
        }
    }

    func host(_ path: OSPath, collapse: ZTronHeaderCollapseBehavior, fade: ZTronHeaderFade? = Self.split,
              counts: BodyCount) -> (ZTronScrollState, UIWindow) {
        let s = makeState(path)
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: Host(state: s, collapse: collapse, fade: fade, counts: counts))
            w.makeKeyAndVisible()
            pump(0.4)
            return w
        }
        var n = 0
        while s.peek.metrics.header == nil, n < 60 { pump(0.1); n += 1 }
        pump(0.3)
        return (s, w)
    }

    /// One rendered column (x in points) as RGB (0…1) per point row, at scale 1.
    struct Column {
        var rgb: [(CGFloat, CGFloat, CGFloat)]
        /// The first row (from `from`) drawn in the content marker: the content's drawn top, or nil.
        @MainActor func contentTop(from: Int) -> Int? {
            let m = T.contentMarker
            return (max(0, from)..<rgb.count).first { y in
                let c = rgb[y]
                return abs(c.0 - m.r) < 0.03 && abs(c.1 - m.g) < 0.03 && abs(c.2 - m.b) < 0.03
            }
        }
    }

    static func column(_ window: UIWindow, x: CGFloat) -> Column {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { ctx in
            window.layer.render(in: ctx.cgContext)
        }
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return Column(rgb: []) }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Column(rgb: []) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let col = min(w - 1, max(0, Int(x)))
        return Column(rgb: (0..<h).map { row in
            let i = (row * w + col) * 4
            return (CGFloat(px[i]) / 255, CGFloat(px[i + 1]) / 255, CGFloat(px[i + 2]) / 255)
        })
    }

    /// The opacity the split draws at `u` with weight `t` toward `partner` (`nil`: the pull side, no fade).
    static func expected(u: CGFloat, t: CGFloat, partner: ZTronHeaderFade.Gradient?) -> CGFloat {
        (1 - t) * HeaderFadeMath.alpha(split.rest, at: u) + t * HeaderFadeMath.alpha(partner, at: u)
    }

    /// The worst |measured − expected| opacity over the header rows `[top, bottom)` (the drawn header; a row's u from
    /// the band `[bandTop, bandEnd]`), 2 rows off each edge, plus whether the rows read as the red header under white.
    static func error(_ c: Column, rows: Range<Int>, bandTop: CGFloat, bandEnd: CGFloat, t: CGFloat,
                      partner: ZTronHeaderFade.Gradient?) -> (worst: CGFloat, rows: Int, notRed: Int) {
        var worst: CGFloat = 0, n = 0, notRed = 0
        for y in (rows.lowerBound + 2)..<max(rows.lowerBound + 2, rows.upperBound - 2) where y < c.rgb.count {
            let (r, g, b) = c.rgb[y]
            if r < 0.97 || abs(g - b) > 0.03 { notRed += 1 }
            let u = (CGFloat(y) + 0.5 - bandTop) / (bandEnd - bandTop)
            worst = max(worst, abs(g - expected(u: u, t: t, partner: partner)))
            n += 1
        }
        return (worst, n, notRed)
    }

    /// `.compress`: at rest, half and fully collapsed, through a transaction-driven scroll into the band and back, and
    /// as a refresh hold opens (the pull side: the nil pull state fades the rest out, fully at R / 2): every rendered
    /// frame's column is the blend at the progress (or pull) read from the same frame's content top. No content body, no
    /// builder run after the install.
    @Test(arguments: OSPath.allCases)
    func theSplitFadeCrossfadesWithTheDrawnGeometry(path: OSPath) {
        let counts = BodyCount()
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        let (s, w) = host(path, collapse: .compress, counts: counts)
        defer { unhost(w) }
        #if DEBUG
        let builds = ZTronRenderCounters.value("header.builder")
        #endif
        let bodies = counts.bodies
        let top0 = Int(HeaderMath.top0(s.peek.metrics).rounded())
        let R: CGFloat = 240, band: CGFloat = 176
        var frames = 0, worstAll: CGFloat = 0, pulled = 0, inBand = 0
        func check(_ label: String) {
            let c = Self.column(w, x: 300)
            guard let top = c.contentTop(from: top0) else { Issue.record("\(path) \(label): no content top"); return }
            let travel = CGFloat(top - top0)          // the header's drawn height, or R + the pull's gap
            let e: (worst: CGFloat, rows: Int, notRed: Int)
            if travel > R + 0.5 {
                // The `.openGap` pull: the header still at R, the gap below it; t = min(1, g / (R / 2)).
                let g = travel - R
                e = Self.error(c, rows: top0..<(top0 + Int(R)), bandTop: CGFloat(top0), bandEnd: CGFloat(top0) + R,
                               t: min(1, g / (R / 2)), partner: nil)
                pulled += 1
            } else {
                let p = min(max((R - travel) / band, 0), 1)
                e = Self.error(c, rows: top0..<top, bandTop: CGFloat(top0), bandEnd: CGFloat(top), t: p,
                               partner: Self.split.collapse)
                if p > 0.05, p < 0.95 { inBand += 1 }
            }
            worstAll = max(worstAll, e.worst)
            frames += 1
            #expect(e.worst < 0.03 && e.rows > 20 && e.notRed == 0,
                    "\(path) \(label): worst opacity error \(e.worst) over \(e.rows) rows (not red under white: \(e.notRed))")
        }
        check("rest")
        s.snapHeader(to: .progress(0.5), animated: false)
        pump(0.3)
        check("half")
        s.snapHeader(to: .collapsed, animated: false)
        pump(0.3)
        check("collapsed")
        s.snapHeader(to: .expanded, animated: false)
        pump(0.3)
        let base = HeaderMath.base(s.peek.metrics)
        withAnimation(.linear(duration: 0.5)) { s.scroll(to: CGPoint(x: 0, y: band - base)) }
        for i in 0..<36 { pump(1.0 / 60); check("into the band \(i)") }
        pump(0.3)
        withAnimation(.linear(duration: 0.5)) { s.scroll(to: CGPoint(x: 0, y: -base)) }
        for i in 0..<36 { pump(1.0 / 60); check("back \(i)") }
        pump(0.3)
        s.beginRefreshing()
        for i in 0..<30 { pump(1.0 / 60); check("hold opens \(i)") }
        pump(0.4)
        check("held")
        #expect(inBand >= 10, "\(path): frames inside the band \(inBand)")
        #expect(pulled >= 3, "\(path): frames of the pull side \(pulled)")
        print("FADE \(path) compress: \(frames) frames, worst opacity error \(worstAll), in band \(inBand), pulled \(pulled)")
        #expect(counts.bodies == bodies, "\(path): no content body (\(counts.bodies - bodies))")
        #if DEBUG
        print("FADE \(path) builder runs: install \(builds), after \(ZTronRenderCounters.value("header.builder"))")
        #expect(ZTronRenderCounters.value("header.builder") == builds,
                "\(path): builder runs through the crossfades \(ZTronRenderCounters.value("header.builder") - builds)")
        #endif
    }

    /// `.slideBehind(parallax: 0.5)`: the band ends at the content's top edge (`R − (1 − k)·c` below the header's moved
    /// top `top0 − k·c`), the collapse weight is the covered fraction: through a scroll into the band, every rendered
    /// frame's uncovered rows are that blend.
    @Test(arguments: OSPath.allCases)
    func aSlideBehindFadeEndsAtTheContentsTop(path: OSPath) {
        let counts = BodyCount(), k: CGFloat = 0.5
        let (s, w) = host(path, collapse: .slideBehind(parallax: k), counts: counts)
        defer { unhost(w) }
        let bodies = counts.bodies
        let top0 = Int(HeaderMath.top0(s.peek.metrics).rounded())
        let R: CGFloat = 240
        var inBand = 0
        func check(_ label: String) {
            let c = Self.column(w, x: 300)
            guard let top = c.contentTop(from: top0) else { Issue.record("\(path) \(label): no content top"); return }
            let covered = min(max(R - CGFloat(top - top0), 0), R)
            let headerTop = CGFloat(top0) - k * covered
            let e = Self.error(c, rows: top0..<top, bandTop: headerTop, bandEnd: CGFloat(top), t: covered / R,
                               partner: Self.split.collapse)
            if covered > 10, covered < R - 10 { inBand += 1 }
            #expect(top - top0 < 8 || (e.worst < 0.03 && e.notRed == 0),
                    "\(path) \(label): worst opacity error \(e.worst) over \(e.rows) rows, c \(covered) (not red: \(e.notRed))")
        }
        check("rest")
        s.snapHeader(to: .progress(0.5), animated: false)
        pump(0.3)
        check("half")
        s.snapHeader(to: .expanded, animated: false)
        pump(0.3)
        let base = HeaderMath.base(s.peek.metrics)
        withAnimation(.linear(duration: 0.5)) { s.scroll(to: CGPoint(x: 0, y: 200 - base)) }
        for i in 0..<36 { pump(1.0 / 60); check("into the band \(i)") }
        pump(0.3)
        #expect(inBand >= 10, "\(path): frames inside the band \(inBand)")
        #expect(counts.bodies == bodies, "\(path): no content body (\(counts.bodies - bodies))")
    }

    /// `.linear(to:from:)` draws exactly today's gradient in every state (clear at `start`, the color at the frame's
    /// bottom): a refresh hold (pull) leaves it as at rest; no layout input changes for the fade (the pull is not
    /// tracked).
    @Test(arguments: OSPath.allCases)
    func aLinearFadeIsTheSameInEveryState(path: OSPath) {
        let counts = BodyCount()
        let (s, w) = host(path, collapse: .compress, fade: .linear(to: Self.white, from: 0.5), counts: counts)
        defer { unhost(w) }
        let top0 = Int(HeaderMath.top0(s.peek.metrics).rounded())
        func worst(_ label: String, height: CGFloat) -> CGFloat {
            let c = Self.column(w, x: 300)
            var worst: CGFloat = 0
            for y in (top0 + 2)..<(top0 + Int(height) - 2) {
                let u = (CGFloat(y) + 0.5 - CGFloat(top0)) / height
                worst = max(worst, abs(c.rgb[y].1 - max(0, (u - 0.5) / 0.5)))
            }
            return worst
        }
        #expect(worst("rest", height: 240) < 0.03)
        s.snapHeader(to: .progress(0.5), animated: false)
        pump(0.3)
        #expect(worst("half", height: 152) < 0.03)
        s.snapHeader(to: .expanded, animated: false)
        pump(0.3)
        s.beginRefreshing()
        pump(0.6)
        #expect(worst("held", height: 240) < 0.03, "\(path): the pull leaves .linear as at rest")
    }
}
