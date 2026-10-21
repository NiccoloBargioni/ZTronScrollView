import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

// User request 2026-10-21: "Clamping should at least produce a log, otherwise it becomes hard to track an error
// originating from an unexpected clamp." Every silent normalization of caller input in the content-overlay API is
// reported in DEBUG builds (`ZTronDiagnostics`): once per (site, kind, input), with the caller's location where one
// can be captured.
//
// The hook is process-wide. Only this suite resets it (before and after each test), and it is serialized, so no reset
// lands inside another test; other suites may add their own reports while a hosted test here pumps the run loop, so
// those tests count only the entries of their own, distinctive values.

#if DEBUG
private typealias D = ZTronDiagnostics
private typealias S = ZTronContentOverlaySize

private let file: String = #fileID

/// The recorded entries whose message is exactly `text` at `site`.
private func logged(_ text: String, _ site: String) -> [D.Entry] {
    D.recorded.filter { $0.message == "[ZTronScrollView] \(text) (\(site))" }
}

/// The recorded entries of `kind` whose message contains `text`.
private func logged(_ kind: D.Kind, containing text: String) -> [D.Entry] {
    D.recorded.filter { $0.kind == kind && $0.message.contains(text) }
}

/// Builds clamping unit values from many threads at once: `distinct` lengths and as many points, each built many times.
private func hammer(iterations: Int, distinct: Int) {
    DispatchQueue.concurrentPerform(iterations: iterations) { @Sendable i in
        _ = ZTronUnitLength(CGFloat(2 + i % distinct))
        _ = ZTronUnitPoint(x: -CGFloat(1 + i % distinct), y: 0.5)
        _ = D.recorded.count   // readers interleave with writers
    }
}

private extension Notification.Name {
    static let diagnosticsReflow = Notification.Name("ContentOverlayDiagnosticsTests.reflow")
}

/// Content `200 × (1000 + 100 n)`: each notification grows it through its own `@State` (a content-owned reflow, the
/// rotation shape: no container evaluation).
private struct ReflowingContent: View {
    @State private var n = 0
    var body: some View {
        Color.red.frame(width: 200, height: 1000 + 100 * CGFloat(n))
            .onReceive(NotificationCenter.default.publisher(for: .diagnosticsReflow)) { _ in n += 1 }
    }
}

/// The hosted overlays' degenerate values, distinct from every other test's.
private enum Hosted {
    static let tinyRatio: CGFloat = 3e-308          // W / r overflows
    static let hugeRatio: CGFloat = 2e307           // H · r overflows
    static let anchor = CGPoint(x: CGFloat.nan, y: 12.5)
    static let overlayAnchor = UnitPoint(x: 0.25, y: .infinity)
}

@MainActor
@Suite(.serialized)
final class ContentOverlayDiagnosticsTests {
    init() { D.resetForTesting() }
    deinit { D.resetForTesting() }

    // MARK: Sites with the caller's location

    @Test func everyUnitInitializerReportsOnceWithTheCallersLocation() {
        let v: CGFloat = 1.5, m: CGFloat = -0.25, n = CGFloat.nan
        let (_, l1) = (ZTronUnitLength(v), #line)
        let (_, l2) = (ZTronUnitSize(width: v, height: m), #line)
        let (_, l3) = (ZTronUnitSize(CGSize(width: n, height: 0.5)), #line)
        let (_, l4) = (ZTronUnitPoint(x: m, y: v), #line)
        let (_, l5) = (ZTronUnitPoint(UnitPoint(x: 0.5, y: .infinity)), #line)
        let want: [(String, Int)] = [
            ("ZTronUnitLength.value is outside 0...1: 1.5 -> 1.0", l1),
            ("ZTronUnitSize.width is outside 0...1: 1.5 -> 1.0", l2),
            ("ZTronUnitSize.height is outside 0...1: -0.25 -> 0.0", l2),
            ("ZTronUnitSize.width is NaN: nan -> 0.0", l3),
            ("ZTronUnitPoint.x is outside 0...1: -0.25 -> 0.0", l4),
            ("ZTronUnitPoint.y is outside 0...1: 1.5 -> 1.0", l4),
            ("ZTronUnitPoint.y is outside 0...1: inf -> 1.0", l5),
        ]
        for (text, line) in want {
            let e = logged(text, "\(file):\(line)")
            #expect(e.count == 1, "\(text) at \(line): \(D.recorded.map(\.message))")
            #expect(e.first?.kind == .unitClamped && e.first?.fileID == file && e.first?.line == UInt(line), "\(text)")
        }
        #expect(D.recorded.filter { $0.fileID == file }.count == want.count, "\(D.recorded.map(\.message))")
    }

    @Test func everyNormalizingConstructorReportsOnceWithTheCallersLocation() {
        let r: CGFloat = -2, a: CGFloat = -7, nan = CGFloat.nan, w: CGFloat = 1.25
        let (_, l1) = (S.fillMaxWidth(r), #line)
        let (_, l2) = (S.fillMaxWidth(height: .aspectRatio(0)), #line)
        let (_, l3) = (S.fillMaxHeight(.infinity), #line)
        let (_, l4) = (S.fillMaxHeight(width: .aspectRatio(nan)), #line)
        let (_, l5) = (S.fillMaxWidth(height: .absolute(a)), #line)
        let (_, l6) = (S.fillMaxHeight(width: .absolute(.infinity)), #line)
        let (_, l7) = (S.absolute(CGSize(width: a, height: nan)), #line)
        let (_, l8) = (S.relative(ZTronUnitSize(width: w, height: 0.5)), #line)
        let (_, l9) = (S.relative(width: ZTronUnitLength(w), height: 0.5), #line)
        let want: [(D.Kind, String, Int)] = [
            (.aspectRatioIgnored, "ZTronContentOverlaySize.fillMaxWidth(height:) .aspectRatio is not a positive finite ratio: -2.0 -> .ideal", l1),
            (.aspectRatioIgnored, "ZTronContentOverlaySize.fillMaxWidth(height:) .aspectRatio is not a positive finite ratio: 0.0 -> .ideal", l2),
            (.aspectRatioIgnored, "ZTronContentOverlaySize.fillMaxHeight(width:) .aspectRatio is not a positive finite ratio: inf -> .ideal", l3),
            (.aspectRatioIgnored, "ZTronContentOverlaySize.fillMaxHeight(width:) .aspectRatio is not a positive finite ratio: nan -> .ideal", l4),
            (.absoluteLengthZeroed, "ZTronContentOverlaySize.fillMaxWidth(height:) .absolute is negative or not finite: -7.0 -> 0.0", l5),
            (.absoluteLengthZeroed, "ZTronContentOverlaySize.fillMaxHeight(width:) .absolute is negative or not finite: inf -> 0.0", l6),
            (.absoluteLengthZeroed, "ZTronContentOverlaySize.absolute(_:) width is negative or not finite: -7.0 -> 0.0", l7),
            (.absoluteLengthZeroed, "ZTronContentOverlaySize.absolute(_:) height is negative or not finite: nan -> 0.0", l7),
            (.unitClamped, "ZTronUnitSize.width is outside 0...1: 1.25 -> 1.0", l8),
            (.unitClamped, "ZTronUnitLength.value is outside 0...1: 1.25 -> 1.0", l9),
        ]
        for (kind, text, line) in want {
            let e = logged(text, "\(file):\(line)")
            #expect(e.count == 1, "\(text) at \(line): \(D.recorded.map(\.message))")
            #expect(e.first?.kind == kind && e.first?.fileID == file && e.first?.line == UInt(line), "\(text)")
        }
        #expect(D.recorded.filter { $0.fileID == file }.count == want.count, "\(D.recorded.map(\.message))")
        // The clamps and normalizations themselves are unchanged.
        #expect(S.fillMaxWidth(r) == .fillMaxWidth() && S.absolute(CGSize(width: a, height: nan)) == .absolute(.zero))
        #expect(S.relative(width: ZTronUnitLength(w), height: 0.5) == .relative(width: 1, height: 0.5))
    }

    // MARK: Literals

    /// A literal carries no location: it reports as `literal`. `ZTronUnitLength(-0.4375)` with a literal argument is
    /// that literal (Swift's literal coercion), not `init(_:fileID:line:)`.
    @Test func literalsReportWithoutALocationOncePerValue() {
        let a: ZTronUnitLength = 1.875
        let b: ZTronUnitLength = 3
        let c = ZTronUnitLength(-0.4375)
        let size = S.fillMaxWidth(height: .relative(2.625))
        for _ in 0..<3 { let again: ZTronUnitLength = 1.875; _ = again }
        let want = ["1.875 -> 1.0", "3.0 -> 1.0", "-0.4375 -> 0.0", "2.625 -> 1.0"]
        for text in want {
            let e = logged("ZTronUnitLength.value is outside 0...1: \(text)", "literal")
            #expect(e.count == 1, "\(text): \(D.recorded.map(\.message))")
            #expect(e.first?.kind == .unitClamped && e.first?.fileID == nil && e.first?.line == nil, "\(text)")
        }
        #expect(D.recorded.count == want.count, "nothing else: \(D.recorded.map(\.message))")
        #expect(a == .full && b == .full && c == .zero && size == .fillMaxWidth(height: .relative(.full)))
    }

    // MARK: In range

    @Test func inRangeValuesReportNothing() {
        for v in [CGFloat(0), -0.0, 0.25, 0.5, 1] {
            _ = ZTronUnitLength(v)
            _ = ZTronUnitSize(width: v, height: v)
            _ = ZTronUnitSize(CGSize(width: v, height: v))
            _ = ZTronUnitPoint(x: v, y: v)
            _ = ZTronUnitPoint(UnitPoint(x: v, y: v))
            _ = S.fillMaxWidth(height: .absolute(v * 40))
            _ = S.absolute(CGSize(width: v, height: v * 40))
            _ = S.relative(ZTronUnitSize(width: v, height: v))
        }
        let literals: [ZTronUnitLength] = [0, 1, 0.5, 0.0, 1.0, .zero, .full]
        // A relative fraction of 0 becomes the length 0: not an error (0 is in range).
        let sizes: [S] = [.fillMaxSize, .ideal, .fillMaxWidth(), .fillMaxWidth(nil), .fillMaxWidth(16 / 9), .fillMaxHeight(0.5),
                          .fillMaxWidth(height: .ideal), .fillMaxWidth(height: .relative(0)), .fillMaxHeight(width: .relative(1)),
                          .fillMaxHeight(width: .absolute(-0.0)), .relative(width: 0, height: 1), .relative(.zero), .relative(.full),
                          .absolute(.zero), .fillMaxWidth(height: .aspectRatio(4))]
        // Layout: finite anchors (an `.absolute` point outside the content and an `overlayAnchor` outside the frame are
        // legitimate), ratios that do not overflow, `.fillMaxSize` with non-finite anchors (ignored, never resolved).
        let content = CGSize(width: 300, height: 600)
        let anchors: [ZTronContentOverlayAnchor] = [.center, .relative(ZTronUnitPoint(x: 0.3, y: 0.65)), .absolute(CGPoint(x: -40, y: 900))]
        for anchor in anchors {
            for size in sizes {
                _ = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: anchor, overlayAnchor: UnitPoint(x: 2, y: -1), size: size),
                                               content: content) { _ in CGSize(width: 50, height: 30) }
            }
        }
        _ = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: .absolute(CGPoint(x: CGFloat.nan, y: .infinity)),
                                                               overlayAnchor: UnitPoint(x: CGFloat.nan, y: 0), size: .fillMaxSize),
                                       content: content) { _ in .zero }
        #expect(literals.count == 7)
        #expect(D.recorded.isEmpty, "\(D.recorded.map(\.message))")
        #expect(D.recordedKeyCount == 0)
    }

    // MARK: Dedupe

    @Test func aRepeatedCallReportsOnceAndADifferentValueOrLineReportsAgain() {
        let v: CGFloat = 1.5
        var l1 = 0, l2 = 0
        // A body that re-runs: the same call site and value, many times.
        for _ in 0..<5 { _ = ZTronUnitLength(v); l1 = #line }
        func body() -> S { S.fillMaxWidth(height: .absolute(-3)) }
        let l3 = #line - 1
        for _ in 0..<5 { _ = body() }
        #expect(logged("ZTronUnitLength.value is outside 0...1: 1.5 -> 1.0", "\(file):\(l1)").count == 1)
        #expect(logged("ZTronContentOverlaySize.fillMaxWidth(height:) .absolute is negative or not finite: -3.0 -> 0.0",
                       "\(file):\(l3)").count == 1)
        // A different value at the same site reports again; the same value at another site too.
        for x in [v, 2.5, 2.5] { _ = ZTronUnitLength(x); l2 = #line }
        let (_, l4) = (ZTronUnitLength(v), #line)
        #expect(logged("ZTronUnitLength.value is outside 0...1: 1.5 -> 1.0", "\(file):\(l2)").count == 1)
        #expect(logged("ZTronUnitLength.value is outside 0...1: 2.5 -> 1.0", "\(file):\(l2)").count == 1)
        #expect(logged("ZTronUnitLength.value is outside 0...1: 1.5 -> 1.0", "\(file):\(l4)").count == 1)
        // Another component of the same type at the same site and value is another report.
        let (_, l5) = (ZTronUnitSize(width: v, height: v), #line)
        #expect(logged("ZTronUnitSize.width is outside 0...1: 1.5 -> 1.0", "\(file):\(l5)").count == 1)
        #expect(logged("ZTronUnitSize.height is outside 0...1: 1.5 -> 1.0", "\(file):\(l5)").count == 1)
        #expect(D.recorded.count == 7 && D.recordedKeyCount == 7, "\(D.recorded.map(\.message))")
        // After a reset the same call reports again.
        D.resetForTesting()
        for _ in 0..<3 { _ = ZTronUnitLength(v); l1 = #line }
        #expect(D.recorded.count == 1 && D.recorded.first?.line == UInt(l1))
    }

    @Test func theBoundHolds() {
        let extra = 100
        var line = 0
        for i in 0..<(D.capacity + extra) { _ = ZTronUnitLength(CGFloat(2 + i)); line = #line }
        #expect(D.recorded.count == D.capacity)
        #expect(D.recordedKeyCount == D.capacity)
        #expect(Set(D.recorded.map(\.message)).count == D.capacity, "no duplicates")
        // The first `capacity` values are the ones kept; a new one is dropped, a kept one still dedupes.
        #expect(D.recorded.last?.message.contains(": \(CGFloat(2 + D.capacity - 1)) -> 1.0 (\(file):\(line))") == true)
        let (_, l2) = (ZTronUnitLength(-5), #line)
        _ = l2
        for _ in 0..<3 { _ = ZTronUnitLength(CGFloat(2)); line = #line }
        _ = line
        #expect(D.recorded.count == D.capacity && D.recordedKeyCount == D.capacity)
        D.resetForTesting()
        #expect(D.recorded.isEmpty && D.recordedKeyCount == 0)
        _ = ZTronUnitLength(CGFloat(-5))
        #expect(D.recorded.count == 1)
    }

    @Test func concurrentReportsKeepTheLockInvariant() {
        let distinct = 64
        hammer(iterations: 4_000, distinct: distinct)
        let got = D.recorded
        #expect(got.count == 2 * distinct, "\(got.count)")
        #expect(D.recordedKeyCount == got.count)
        #expect(Set(got.map(\.message)).count == got.count, "each report once")
        #expect(got.filter { $0.message.hasPrefix("[ZTronScrollView] ZTronUnitLength.value is outside 0...1: ") }.count == distinct)
        #expect(got.filter { $0.message.hasPrefix("[ZTronScrollView] ZTronUnitPoint.x is outside 0...1: ") }.count == distinct)
        // Again, with every key known: nothing new.
        hammer(iterations: 2_000, distinct: distinct)
        #expect(D.recorded.count == 2 * distinct && D.recordedKeyCount == 2 * distinct)
    }

    // MARK: Layout sites

    /// The values a size or anchor holds are resolved in layout: an overflowing ratio and non-finite anchors report
    /// there (`at layout`), once per value and axis however many passes or content sizes see them.
    @Test func layoutReportsOncePerValueAcrossPasses() {
        let tiny: CGFloat = 1e-307, huge: CGFloat = 1e307
        let sizes: [S] = [.fillMaxWidth(height: .aspectRatio(tiny)), .fillMaxHeight(width: .aspectRatio(huge))]
        #expect(D.recorded.isEmpty, "a positive ratio is kept when the size is built")
        let points: [(ZTronContentOverlayAnchor, UnitPoint)] = [
            (.absolute(CGPoint(x: CGFloat.nan, y: 17.5)), .topLeading),
            (.absolute(CGPoint(x: 3, y: -CGFloat.infinity)), .center),
            (.absolute(CGPoint(x: CGFloat.infinity, y: CGFloat.nan)), UnitPoint(x: CGFloat.infinity, y: 0.5)),
        ]
        for h in [600, 700, 800] as [CGFloat] {
            let content = CGSize(width: 300, height: h)
            for size in sizes {
                let f = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: .topLeading, overlayAnchor: .topLeading, size: size),
                                                   content: content) { _ in .zero }
                #expect(f.width == 300 && f.height == 0 || f.width == 0 && f.height == h, "draws 0 on the overflowing axis: \(f)")
            }
            for (anchor, q) in points {
                _ = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: anchor, overlayAnchor: q, size: .ideal),
                                               content: content) { _ in CGSize(width: 10, height: 10) }
            }
        }
        // Not overflowing on this content: no report for the value.
        _ = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: .topLeading, overlayAnchor: .topLeading, size: sizes[1]),
                                       content: CGSize(width: 300, height: 1e-10)) { _ in .zero }
        let want: [(D.Kind, String)] = [
            (.aspectRatioOverflow, "ZTronContentOverlaySize.fillMaxWidth(height: .aspectRatio) height overflows (W / r): "
                + ".fillMaxWidth(height: .aspectRatio(\(tiny))) -> 0.0"),
            (.aspectRatioOverflow, "ZTronContentOverlaySize.fillMaxHeight(width: .aspectRatio) width overflows (H · r): "
                + ".fillMaxHeight(width: .aspectRatio(\(huge))) -> 0.0"),
            (.anchorNotFinite, "ZTronContentOverlayAnchor.absolute x is not finite: nan in .absolute(\(CGPoint(x: CGFloat.nan, y: 17.5))) -> 0.0"),
            (.anchorNotFinite, "ZTronContentOverlayAnchor.absolute y is not finite: -inf in .absolute(\(CGPoint(x: 3, y: -CGFloat.infinity))) -> 0.0"),
            (.anchorNotFinite, "ZTronContentOverlayAnchor.absolute x is not finite: inf in .absolute(\(CGPoint(x: CGFloat.infinity, y: CGFloat.nan))) -> 0.0"),
            (.anchorNotFinite, "ZTronContentOverlayAnchor.absolute y is not finite: nan in .absolute(\(CGPoint(x: CGFloat.infinity, y: CGFloat.nan))) -> 0.0"),
            (.overlayAnchorNotFinite, "scrollContentIntegralOverlay overlayAnchor.x is not finite: inf in UnitPoint(x: inf, y: 0.5) -> 0.0"),
        ]
        for (kind, text) in want {
            let e = logged(text, "at layout")
            #expect(e.count == 1, "\(text): \(D.recorded.map(\.message))")
            #expect(e.first?.kind == kind && e.first?.fileID == nil && e.first?.line == nil, "\(text)")
        }
        #expect(D.recorded.count == want.count, "\(D.recorded.map(\.message))")
    }

    /// The same, from overlays hosted in a scroll view on both hosts: reported once per value at the first layout and
    /// never again over several content-owned reflows, which re-place the overlays by layout alone (the report adds no
    /// body, no host evaluation).
    @Test(arguments: OSPath.allCases) func layoutReportsArriveFromAHostedOverlayOncePerValueAcrossReflows(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { ReflowingContent() }
                .scrollContentIntegralOverlay(anchor: .top, overlayAnchor: .top,
                                              size: .fillMaxWidth(height: .aspectRatio(Hosted.tinyRatio))) {
                    Color.red.ztronScrollID("d.tiny")
                }
                .scrollContentIntegralOverlay(anchor: .leading, overlayAnchor: .leading,
                                              size: .fillMaxHeight(width: .aspectRatio(Hosted.hugeRatio))) {
                    Color.blue.ztronScrollID("d.huge")
                }
                .scrollContentIntegralOverlay(anchor: .absolute(Hosted.anchor), overlayAnchor: Hosted.overlayAnchor, size: .ideal) {
                    Color.green.frame(width: 8, height: 8).ztronScrollID("d.anchor")
                })
        }
        pump(0.2)
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1000))
        let a = Hosted.anchor, q = Hosted.overlayAnchor
        let texts: [(D.Kind, String)] = [
            (.aspectRatioOverflow, ".fillMaxWidth(height: .aspectRatio(\(Hosted.tinyRatio))) -> 0.0"),
            (.aspectRatioOverflow, ".fillMaxHeight(width: .aspectRatio(\(Hosted.hugeRatio))) -> 0.0"),
            (.anchorNotFinite, "x is not finite: nan in .absolute(\(a)) -> 0.0"),
            (.overlayAnchorNotFinite, "y is not finite: inf in UnitPoint(x: \(q.x), y: \(q.y)) -> 0.0"),
        ]
        func expectOnce(_ label: String) {
            for (kind, text) in texts {
                let e = logged(kind, containing: text)
                #expect(e.count == 1, "\(path) \(label) \(text): \(D.recorded.map(\.message))")
                #expect(e.first?.message.hasSuffix(" (at layout)") == true && e.first?.fileID == nil, "\(text)")
            }
        }
        expectOnce("initial")
        // Placed with the degenerate values read as 0 (an empty strip, an empty bar, the marker at (0, 12.5) − q · 8).
        let r = s.targets
        #expect(r.frame(of: "d.tiny").map { $0.width == 200 && $0.height == 0 } == true, "\(String(describing: r.frame(of: "d.tiny")))")
        #expect(r.frame(of: "d.huge").map { $0.width == 0 && $0.height == 1000 } == true, "\(String(describing: r.frame(of: "d.huge")))")
        #expect(r.frame(of: "d.anchor").map { abs($0.minX + 2) < 0.5 && abs($0.minY - 12.5) < 0.5 } == true,
                "\(String(describing: r.frame(of: "d.anchor")))")
        ZTronRenderCounters.reset()
        for i in 1...3 {
            withOSPath(path) { NotificationCenter.default.post(name: .diagnosticsReflow, object: nil); pump(0.2) }
            #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1000 + 100 * CGFloat(i)))
        }
        expectOnce("after 3 reflows")
        #expect(r.frame(of: "d.huge").map { $0.height == 1300 } == true, "re-placed: \(String(describing: r.frame(of: "d.huge")))")
        #expect(ZTronRenderCounters.value("contentOverlay.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") == 0, "no container evaluation")
        #expect(ZTronRenderCounters.value(s.usesLayoutProtocol ? "contentOverlay.place" : "contentOverlay.reader") >= 3)
        unhost(w)
    }
}
#endif
