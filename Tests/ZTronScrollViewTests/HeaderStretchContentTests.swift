import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// D76 (`stretchContent:`): the default `.keepTextMagnified` is D69 bit for bit. The hosted layer tree of a `.stretch`
/// header (marker fill, text, an SF Symbol) under a 60 pt refresh hold and a 60 pt pull is compared, layer by layer
/// (type, window frame, bounds, transform, clip, fill), with a reference captured at D69 (`d291afc`, before D76's change),
/// per OS version, OS path and size (`HeaderStretchD69Reference`).
@MainActor
@Suite(.serialized)
struct HeaderStretchContentTests {
    static let headerMarker = HeaderStretchScaleTests.headerMarker
    static let contentMarker = HeaderStretchScaleTests.contentMarker

    struct Header: View {
        let size: ZTronHeaderSize
        var body: some View {
            ZStack {
                HeaderStretchScaleTests.color(HeaderStretchContentTests.headerMarker)
                VStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 20)).foregroundColor(.black)
                    Text("Stretch Aa 0123").font(.system(size: 24, weight: .bold)).foregroundColor(.black)
                }
            }
            .modifier(FitIdeal(fit: size.isFit))
        }
    }

    /// `.fit`: a 16:9 ideal height at any width.
    struct FitIdeal: ViewModifier {
        let fit: Bool
        @ViewBuilder func body(content: Content) -> some View {
            if fit {
                Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(content)
            } else {
                content
            }
        }
    }

    struct Strip: View {
        var body: some View {
            VStack(spacing: 0) {
                HeaderStretchScaleTests.color(HeaderStretchContentTests.contentMarker).frame(height: 8)
                Color.green.frame(height: 3000)
            }
        }
    }

    struct Host: View {
        let state: ZTronScrollState
        let size: ZTronHeaderSize
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Strip() }
                .withScalingHeader(size: size, pull: .stretch) { _ in Header(size: size) }
                .refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20) }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
        }
    }

    /// The model layer tree in the header's region (every layer whose window frame meets `0 ... bottom`), one line each.
    static func dump(_ window: UIWindow, bottom: CGFloat) -> [String] {
        var out: [String] = []
        let root = window.layer
        func d(_ v: CGFloat) -> String { "\(Double(v))" }
        func walk(_ layer: CALayer, _ depth: Int) {
            let r = layer.convert(layer.bounds, to: root)
            if r.minY < bottom, r.maxY > 0, r.width > 0, r.height > 0 {
                let t = layer.transform
                var line = "\(depth) \(type(of: layer)) f=(\(d(r.minX)),\(d(r.minY)),\(d(r.width)),\(d(r.height)))"
                line += " b=(\(d(layer.bounds.width)),\(d(layer.bounds.height)))"
                if !CATransform3DIsIdentity(t) {
                    line += " t=(\(d(t.m11)),\(d(t.m12)),\(d(t.m21)),\(d(t.m22)),\(d(t.m41)),\(d(t.m42)))"
                }
                if layer.masksToBounds { line += " clip" }
                if layer.mask != nil { line += " mask" }
                if let c = layer.backgroundColor?.components { line += " bg=\(c.map { d($0) }.joined(separator: ","))" }
                out.append(line)
            }
            for sub in layer.sublayers ?? [] { walk(sub, depth + 1) }
        }
        walk(root, 0)
        return out
    }

    nonisolated static let sizes: [ZTronHeaderSize] = HeaderStretchScaleTests.sizes

    static func key(_ path: OSPath, _ size: ZTronHeaderSize, _ phase: String) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let kind: String
        switch size {
        case .fixed: kind = "fixed"
        case .aspectRatio: kind = "aspect"
        case .fit: kind = "fit"
        }
        return "ios\(os.majorVersion).\(os.minorVersion)-\(path)-\(kind)-\(phase)"
    }

    /// The default (no `stretchContent:` argument) draws exactly D69's layer tree under a 60 pt pull and a 60 pt refresh
    /// hold: every layer of the header's region equal to the reference captured before D76, bit for bit.
    @Test(arguments: OSPath.allCases, Self.sizes)
    func theDefaultIsD69BitForBit(path: OSPath, size: ZTronHeaderSize) {
        let s = makeState(path)
        let w = withOSPath(path) { hostDriven(Host(state: s, size: size), driven: false) }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 60 { pump(0.1); n += 1 }
        pump(0.3)
        guard let resting = s.peek.metrics.header?.resting else { Issue.record("\(path) \(size): unresolved"); return }
        let top0 = HeaderMath.top0(s.peek.metrics)
        // A 60 pt pull.
        s.track(offset: CGPoint(x: 0, y: -60 - HeaderMath.base(s.peek.metrics)), zoom: 1)
        pump(0.3)
        check(w, key: Self.key(path, size, "pull60"), bottom: top0 + resting + 61)
        s.track(offset: CGPoint(x: 0, y: -HeaderMath.base(s.peek.metrics)), zoom: 1)
        s.endOfTurn()
        pump(0.3)
        // A 60 pt refresh hold.
        s.beginRefreshing()
        pump(1.0)
        #expect(abs((s.headerGeometry?.stretch ?? 0) - 60) < 0.5, "\(path) \(size): a 60 pt hold (\(String(describing: s.headerGeometry)))")
        check(w, key: Self.key(path, size, "hold60"), bottom: top0 + resting + 61)
    }

    final class Option: ObservableObject { @Published var content: ZTronHeaderStretchContent = .keepTextMagnified }

    /// A refreshing `.fixed(240)` `.stretch` header with the text mark (`HeaderStretchScaleTests.Header`) whose
    /// `stretchContent:` the app switches.
    struct SwitchHost: View {
        let state: ZTronScrollState
        @ObservedObject var option: Option
        let box: HeaderStretchScaleTests.Box
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) { HeaderStretchScaleTests.Content(counts: counts) }
                .withScalingHeader(size: .fixed(min: 64, max: 240), pull: .stretch, stretchContent: option.content) { _ in
                    HeaderStretchScaleTests.Header(size: .fixed(min: 64, max: 240), box: box)
                }
                .refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20) }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
        }
    }

    /// D76: a `withAnimation` switch `.keepTextMagnified` → `.keepTextSize` during a 60 pt hold morphs inside the frame:
    /// every drawn frame keeps the header's outer rect (`W · s × (R + g)` from `top0`, its bottom on the content's top),
    /// and the fixed-size text mark shrinks monotonically from `s` times its size to its point size, over many frames (no
    /// step ≥ ½ of the change). Unanimated, it lands in one frame. The switch runs the header's builder exactly once and
    /// no content body. 15 path (C14, until s7): both cases draw D69, the mark stays magnified.
    @Test(arguments: OSPath.allCases, [true, false])
    func anAnimatedSwitchMorphsInsideTheFrame(path: OSPath, animated: Bool) {
        let box = HeaderStretchScaleTests.Box(), counts = BodyCount(), option = Option()
        let s = makeState(path)
        let w = withOSPath(path) { hostDriven(SwitchHost(state: s, option: option, box: box, counts: counts)) }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 60 { pump(0.1); n += 1 }
        pump(0.3)
        s.beginRefreshing()
        pump(1.0)
        guard let resting = s.peek.metrics.header?.resting, let g = s.headerGeometry?.stretch, g > 30 else {
            Issue.record("\(path): no hold (\(String(describing: s.headerGeometry)))"); return
        }
        let top0 = HeaderMath.top0(s.peek.metrics), scale = (resting + g) / resting
        let grows = s.usesLayoutProtocol
        let tag = "\(path) \(animated ? "animated" : "unanimated")"
        let bodies = counts.bodies
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        if animated {
            withAnimation(.linear(duration: 0.5)) { option.content = .keepTextSize }
        } else {
            option.content = .keepTextSize
        }
        var heights: [CGFloat] = [], worstFrame: CGFloat = 0, worstSeam: CGFloat = 0
        var layouts: [CGFloat] = [], stamps: [CFTimeInterval] = []
        for _ in 0..<45 {
            pump(1.0 / 60)
            let tf = HeaderStretchScaleTests.frames(of: HeaderStretchScaleTests.textMarker, in: w, presented: true)
            let hf = HeaderStretchScaleTests.drawnFrames(of: Self.headerMarker, in: w, presented: true)
            let cf = HeaderStretchScaleTests.frames(of: Self.contentMarker, in: w, presented: true)
            guard let t = tf.first, let f = hf.first, let c = cf.first else { continue }
            heights.append(t.height)
            layouts.append(box.size.height)
            stamps.append(CACurrentMediaTime())
            // The drawn rect (cut by the clips): `W × (R + g)` from `top0` whatever the share.
            worstFrame = max(worstFrame, abs(f.minY - top0), abs(f.maxY - (top0 + resting + g)), abs(f.minX), abs(f.maxX - 402))
            worstSeam = max(worstSeam, abs(f.maxY - c.minY))
        }
        pump(0.3)
        print("SWITCH \(tag): " + zip(zip(heights, layouts), stamps).map {
            String(format: "%.3f mark %.4f layout %.4f eff %.4f", $1 - (stamps.first ?? 0), $0.0, $0.1,
                   20 * (resting + g) / max($0.1, 1))
        }.joined(separator: " | "))
        #expect(heights.count >= 30, "\(tag): sampled \(heights.count) frames")
        #expect(worstFrame < 0.5, "\(tag): the outer frame moved by \(worstFrame)")
        #expect(worstSeam < 0.5, "\(tag): seam \(worstSeam)")
        let start = 20 * scale, end: CGFloat = grows ? 20 : start
        if let last = heights.last { #expect(abs(last - end) < 0.25, "\(tag): the mark ends at \(last), not \(end)") }
        // A sample whose mark does not match its own layout (`20 · (R + g) / layout height`, the effect's `s_eff` at the
        // layout's `m`) was read mid-commit (the asynchronous renderer's presentation ahead of the main thread's model):
        // at most a few, and the monotonicity is judged on the consistent ones.
        let consistent = zip(heights, layouts).filter { abs($0 - 20 * (resting + g) / max($1, 1)) < 0.05 }.map(\.0)
        #expect(heights.count - consistent.count <= 3, "\(tag): \(heights.count - consistent.count) inconsistent samples")
        let steps = zip(consistent, consistent.dropFirst()).map { $1 - $0 }
        #expect(steps.allSatisfy { $0 <= 0.01 }, "\(tag): the mark's height is monotone \(consistent)")
        if grows && animated {
            let mid = heights.filter { $0 < start - 0.25 && $0 > end + 0.25 }
            #expect(mid.count >= 10, "\(tag): a morph over \(mid.count) frames \(heights)")
            let change = start - end
            #expect((steps.map { -$0 }.max() ?? 0) < 0.5 * change, "\(tag): a step >= 0.5 of the change \(heights)")
        } else if grows {
            #expect(abs((heights.first ?? 0) - end) < 0.25, "\(tag): lands in one frame \(heights)")
        }
        #expect(counts.bodies == bodies, "\(tag): no content body (\(counts.bodies - bodies))")
        #if DEBUG
        #expect(ZTronRenderCounters.value("header.builder") == 1,
                "\(tag): the switch ran the builder \(ZTronRenderCounters.value("header.builder")) times (expected 1)")
        #endif
    }

    func check(_ w: UIWindow, key: String, bottom: CGFloat) {
        let lines = Self.dump(w, bottom: bottom)
        let got = lines.joined(separator: "\n")
        guard let ref = HeaderStretchD69Reference.trees[key] else {
            print("D69REF-BEGIN \(key)\n\(got)\nD69REF-END \(key)")
            Issue.record("\(key): no D69 reference for this lane (printed between D69REF-BEGIN / END)")
            return
        }
        if ref != got {
            let r = ref.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var diff = "in the count"
            for (i, pair) in zip(r, lines).enumerated() where pair.0 != pair.1 {
                diff = "#\(i): \(pair.0) -> \(pair.1)"
                break
            }
            print("D69REF-BEGIN \(key)\n\(got)\nD69REF-END \(key)")
            let message = "\(key): the layer tree differs from D69 (\(r.count) vs \(lines.count) layers; first diff \(diff))"
            Issue.record(Comment(rawValue: message))
        }
    }
}
