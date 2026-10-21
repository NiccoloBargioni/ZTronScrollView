import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

// User request 2026-10-21: "Clamping should at least produce a log, otherwise it becomes hard to track an error
// originating from an unexpected clamp." Every silent normalization of caller input in the content-overlay API is
// reported in DEBUG builds (`ZTronDiagnostics`): once per (site, kind, input), at most `perSiteLimit` values per call
// site, with the caller's location where one can be captured (for layout reports, the declaring modifier's).
//
// The hook is process-wide. Only this suite resets it (before and after each test), and it is serialized, so no reset
// lands inside another test; other suites may add their own reports while a hosted test here pumps the run loop, so
// those tests count only the entries of their own, distinctive values. The lines themselves are read through the sink
// (`capture`), which takes every line in the process while installed: assertions on it filter by those values too.

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

/// Builds clamping unit values from many threads at once, each built many times: `distinct` lengths and as many points,
/// each at its own call site (explicit `line:`), and `distinct` sizes at one call site (the per-site limit applies).
private func hammer(iterations: Int, distinct: Int) {
    DispatchQueue.concurrentPerform(iterations: iterations) { @Sendable i in
        let k = i % distinct
        _ = ZTronUnitLength(CGFloat(2 + k), fileID: "Hammer/Length.swift", line: UInt(1 + k))
        _ = ZTronUnitPoint(x: -CGFloat(1 + k), y: 0.5, fileID: "Hammer/Point.swift", line: UInt(1 + k))
        _ = ZTronUnitSize(width: CGFloat(2 + k), height: 0.5, fileID: "Hammer/Size.swift", line: 1)
        _ = D.recorded.count   // readers interleave with writers
    }
}

/// Lines from any thread (the capturing sink).
private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func append(_ line: String) { lock.lock(); items.append(line); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

/// The lines sent to the sink while `body` runs (instead of `NSLog`); the previous sink is restored afterwards.
private func capture(_ body: () -> Void) -> [String] {
    let lines = Lines()
    let previous = D.sink
    D.sink = { lines.append($0) }
    defer { D.sink = previous }
    body()
    return lines.all
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
    static let twinOverlayAnchor = UnitPoint(x: -CGFloat.infinity, y: 0.375)
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

    /// A literal carries no location: it reports as `literal`, once per value. `ZTronUnitLength(-0.4375)` with a literal
    /// argument is that literal (Swift's literal coercion), not `init(_:fileID:line:)`. A constructor that receives a
    /// clamped literal reports it again with its caller's location, at every such call.
    @Test func literalsReportAsLiteralOncePerValueAndAgainWhereAConstructorReceivesThem() {
        let a: ZTronUnitLength = 1.875
        let b: ZTronUnitLength = 3
        let c = ZTronUnitLength(-0.4375)
        let (size, l1) = (S.fillMaxWidth(height: .relative(2.625)), #line)
        for _ in 0..<3 { let again: ZTronUnitLength = 1.875; _ = again }
        // The percent-for-fraction mistake, at two call sites, and a negative fraction on the other free axis.
        let (r1, l2) = (S.relative(width: 50, height: 20), #line)
        let (r2, l3) = (S.relative(width: 50, height: 20), #line)
        let (h, l4) = (S.fillMaxHeight(width: .relative(-3)), #line)
        let literals = ["1.875 -> 1.0", "3.0 -> 1.0", "-0.4375 -> 0.0", "2.625 -> 1.0", "50.0 -> 1.0", "20.0 -> 1.0", "-3.0 -> 0.0"]
        for text in literals {
            let e = logged("ZTronUnitLength.value is outside 0...1: \(text)", "literal")
            #expect(e.count == 1, "\(text): \(D.recorded.map(\.message))")
            #expect(e.first?.kind == .unitClamped && e.first?.fileID == nil && e.first?.line == nil, "\(text)")
        }
        let located: [(String, Int)] = [
            ("ZTronContentOverlaySize.fillMaxWidth(height:) .relative is a literal outside 0...1: 2.625 -> 1.0", l1),
            ("ZTronContentOverlaySize.relative(width:height:) width is a literal outside 0...1: 50.0 -> 1.0", l2),
            ("ZTronContentOverlaySize.relative(width:height:) height is a literal outside 0...1: 20.0 -> 1.0", l2),
            ("ZTronContentOverlaySize.relative(width:height:) width is a literal outside 0...1: 50.0 -> 1.0", l3),
            ("ZTronContentOverlaySize.relative(width:height:) height is a literal outside 0...1: 20.0 -> 1.0", l3),
            ("ZTronContentOverlaySize.fillMaxHeight(width:) .relative is a literal outside 0...1: -3.0 -> 0.0", l4),
        ]
        for (text, line) in located {
            let e = logged(text, "\(file):\(line)")
            #expect(e.count == 1, "\(text) at \(line): \(D.recorded.map(\.message))")
            #expect(e.first?.kind == .unitClamped && e.first?.fileID == file && e.first?.line == UInt(line), "\(text)")
        }
        #expect(D.recorded.count == literals.count + located.count, "nothing else: \(D.recorded.map(\.message))")
        // The clamps are unchanged, and the kept literal is outside `==` and `hash`.
        #expect(a == .full && b == .full && c == .zero && size == .fillMaxWidth(height: .relative(.full)))
        #expect(r1 == .relative(.full) && r2 == r1 && h == .fillMaxHeight(width: .relative(0)))
        #expect(b.hashValue == ZTronUnitLength.full.hashValue && Set([b, .full, ZTronUnitLength(1)]).count == 1)
        #expect(ZTronContentOverlayLength.relative(b) == .relative(.full))
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
        // A finite counter-scale anchor outside the view is legitimate.
        _ = Color.red.ztronScrollCounterScaled(anchor: UnitPoint(x: 2, y: -1))
        _ = Color.red.ztronScrollCounterScaled()
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

    /// The process-wide backstop: `capacity` distinct reports from as many call sites (one value each, so the per-site
    /// limit never applies), then one line saying further reports are not logged.
    @Test func theBoundHolds() {
        let extra = 100
        let base: UInt = 100_000
        let saturation = "[ZTronScrollView] \(D.capacity) distinct reports: further ones are not logged"
        let out = capture {
            for i in 0..<(D.capacity + extra) { _ = ZTronUnitLength(CGFloat(2), fileID: "Bound/Sites.swift", line: base + UInt(i)) }
            #expect(D.recorded.count == D.capacity)
            #expect(D.recordedKeyCount == D.capacity)
            #expect(Set(D.recorded.map(\.message)).count == D.capacity, "no duplicates")
            // The first `capacity` sites are the ones kept; a new one is dropped, a kept one still dedupes.
            #expect(D.recorded.last?.message == "[ZTronScrollView] ZTronUnitLength.value is outside 0...1: 2.0 -> 1.0 "
                        + "(Bound/Sites.swift:\(base + UInt(D.capacity) - 1))")
            _ = ZTronUnitLength(-5)
            for _ in 0..<3 { _ = ZTronUnitLength(CGFloat(2), fileID: "Bound/Sites.swift", line: base) }
            #expect(D.recorded.count == D.capacity && D.recordedKeyCount == D.capacity)
        }
        // One line per kept report, the saturation line once.
        #expect(out.filter { $0.hasSuffix("2.0 -> 1.0 (Bound/Sites.swift:\(base))") }.count == 1)
        #expect(out.filter { $0.contains("(Bound/Sites.swift:") }.count == D.capacity)
        #expect(out.filter { $0 == saturation }.count == 1, "\(out.filter { !$0.contains("Bound/Sites.swift") })")
        D.resetForTesting()
        #expect(D.recorded.isEmpty && D.recordedKeyCount == 0)
        _ = ZTronUnitLength(CGFloat(-5))
        #expect(D.recorded.count == 1)
    }

    /// A value that changes every frame at one call site (a marker dragged past the content's edge): `perSiteLimit`
    /// values logged, then one line saying further ones are not, and the rest of the budget stays for other sites.
    @Test func aSiteThatClampsEveryFrameLogsAFewValuesAndLeavesTheBudgetToOtherSites() {
        func drag(_ i: Int, y: CGFloat = 0.5) -> ZTronUnitPoint { ZTronUnitPoint(x: 1 + CGFloat(i + 1) / 128, y: y) }   // one site
        let site = #line - 1
        var l2 = 0
        let out = capture {
            for i in 0..<200 { _ = drag(i) }
            for i in 0..<200 { _ = drag(i) }   // again: nothing new, and the limit line is not repeated
            #expect(D.recorded.count == D.perSiteLimit && D.recordedKeyCount == D.perSiteLimit, "\(D.recorded.map(\.message))")
            // Another site, and another component at the same site, still log.
            let (_, l) = (ZTronUnitPoint(x: 1 + 1.0 / 128, y: 0.5), #line)
            l2 = l
            _ = drag(0, y: 3.25)
            #expect(logged("ZTronUnitPoint.y is outside 0...1: 3.25 -> 1.0", "\(file):\(site)").count == 1)
        }
        let here = D.recorded.filter { $0.line == UInt(site) && $0.message.contains("ZTronUnitPoint.x") }
        #expect(here.count == D.perSiteLimit)
        #expect(here.map(\.message) == (1...D.perSiteLimit).map {
            "[ZTronScrollView] ZTronUnitPoint.x is outside 0...1: \(1 + CGFloat($0) / 128) -> 1.0 (\(file):\(site))"
        }, "the first values, in order")
        #expect(logged("ZTronUnitPoint.x is outside 0...1: \(1 + 1.0 / 128) -> 1.0", "\(file):\(l2)").count == 1)
        let limitLine = "[ZTronScrollView] ZTronUnitPoint.x (\(file):\(site)): \(D.perSiteLimit) distinct values reported, "
            + "further ones are not logged"
        #expect(out.filter { $0 == limitLine }.count == 1, "\(out)")
        #expect(out.filter { $0.contains("ZTronUnitPoint.x is outside") && $0.hasSuffix("(\(file):\(site))") }.count
                    == D.perSiteLimit, "one line per logged value")
        #expect(D.recordedKeyCount == D.perSiteLimit + 2)
    }

    /// The literal site gathers every literal in the process (source constants, finitely many): not limited per site.
    @Test func theLiteralSiteIsNotLimitedPerSite() {
        for i in 0..<(4 * D.perSiteLimit) { _ = ZTronUnitLength(floatLiteral: 2 + Double(i)) }
        #expect(D.recorded.filter { $0.message.hasSuffix(" (literal)") }.count == 4 * D.perSiteLimit)
    }

    // MARK: Sink

    /// The lines reach the sink (`NSLog` by default): the breakpoint hint once per process, before the first report,
    /// then one line per new report and none for a repeat.
    @Test func theLinesReachTheSinkTheHintOnceAndEachReportOnce() {
        func clampOne() { _ = ZTronUnitLength(1.0625 + CGFloat(0)) }   // one site
        let l1 = #line - 1
        var l2 = 0
        let first = capture {
            D.resetForTesting(includingHint: true)
            for _ in 0..<3 { clampOne() }
            let (_, l) = (ZTronUnitSize(width: -0.0625, height: 1.0625), #line)
            l2 = l
        }
        let mine = [
            "[ZTronScrollView] ZTronUnitLength.value is outside 0...1: 1.0625 -> 1.0 (\(file):\(l1))",
            "[ZTronScrollView] ZTronUnitSize.width is outside 0...1: -0.0625 -> 0.0 (\(file):\(l2))",
            "[ZTronScrollView] ZTronUnitSize.height is outside 0...1: 1.0625 -> 1.0 (\(file):\(l2))",
        ]
        #expect(first.filter { $0 == D.hint }.count == 1, "\(first)")
        #expect(first.first == D.hint, "the hint comes first: \(first)")
        #expect(first.filter { mine.contains($0) } == mine, "each once, in order: \(first)")
        #expect(mine.allSatisfy { line in D.recorded.contains { $0.message == line } })
        let second = capture {
            for _ in 0..<3 { clampOne() }
            _ = ZTronUnitLength(1.1875 + CGFloat(0))   // not a literal: located
        }
        #expect(!second.contains(D.hint), "once per process: \(second)")
        #expect(second.filter { $0.contains("1.0625") }.isEmpty, "a repeat logs nothing: \(second)")
        #expect(second.filter { $0.contains(": 1.1875 -> 1.0 (\(file):") }.count == 1, "\(second)")
    }

    @Test func concurrentReportsKeepTheLockInvariant() {
        let distinct = 64
        let want = 2 * distinct + D.perSiteLimit
        let out = capture { hammer(iterations: 4_000, distinct: distinct) }
        let got = D.recorded
        #expect(got.count == want, "\(got.count)")
        #expect(D.recordedKeyCount == got.count)
        #expect(Set(got.map(\.message)).count == got.count, "each report once")
        #expect(got.filter { $0.message.hasPrefix("[ZTronScrollView] ZTronUnitLength.value is outside 0...1: ") }.count == distinct)
        #expect(got.filter { $0.message.hasPrefix("[ZTronScrollView] ZTronUnitPoint.x is outside 0...1: ") }.count == distinct)
        #expect(got.filter { $0.message.hasPrefix("[ZTronScrollView] ZTronUnitSize.width is outside 0...1: ") }.count == D.perSiteLimit)
        // One line per report and one limit line, whichever threads won.
        #expect(out.filter { $0.contains("(Hammer/") && !$0.contains("further ones") }.count == want, "\(out.count)")
        #expect(out.filter { $0.hasPrefix("[ZTronScrollView] ZTronUnitSize.width (Hammer/Size.swift:1): ") }.count == 1)
        // Again, with every key known: nothing new.
        let again = capture { hammer(iterations: 2_000, distinct: distinct) }
        #expect(D.recorded.count == want && D.recordedKeyCount == want)
        #expect(again.filter { $0.contains("Hammer/") }.isEmpty, "\(again.filter { $0.contains("Hammer/") })")
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

    /// A layout report is keyed on the normalized component only: a NaN `x` with a `y` that follows a drag is one
    /// report per call, not one per frame (located, so the per-site limit would otherwise cap it at a few, and
    /// unlocated, where nothing else would).
    @Test func aLayoutReportKeysOnTheNormalizedComponentOnly() {
        let located = ZTronDiagnostics.CallSite(fileID: "Drag/Marker.swift", line: 42)
        for site in [located, .unlocated] {
            for i in 0..<50 {
                let y = 100 + 1.5 * CGFloat(i)
                var placement = ContentOverlayPlacement(anchor: .absolute(CGPoint(x: CGFloat.nan, y: y)),
                                                        overlayAnchor: UnitPoint(x: y / 1000, y: -CGFloat.infinity), size: .ideal)
                placement.site = site
                _ = ContentOverlayMath.resolve(placement, content: CGSize(width: 300, height: 600)) { _ in CGSize(width: 10, height: 10) }
            }
        }
        for place in ["Drag/Marker.swift:42, at layout", "at layout"] {
            let x = D.recorded.filter { $0.kind == .anchorNotFinite && $0.message.hasSuffix("(\(place))") }
            let q = D.recorded.filter { $0.kind == .overlayAnchorNotFinite && $0.message.hasSuffix("(\(place))") }
            #expect(x.map(\.message) == ["[ZTronScrollView] ZTronContentOverlayAnchor.absolute x is not finite: "
                                            + "nan in .absolute(\(CGPoint(x: CGFloat.nan, y: 100))) -> 0.0 (\(place))"], "\(place)")
            #expect(q.map(\.message) == ["[ZTronScrollView] scrollContentIntegralOverlay overlayAnchor.y is not finite: "
                                            + "-inf in UnitPoint(x: 0.1, y: -inf) -> 0.0 (\(place))"], "\(place)")
        }
        #expect(D.recorded.first?.fileID == "Drag/Marker.swift" && D.recorded.first?.line == 42)
        #expect(D.recorded.count == 4, "\(D.recorded.map(\.message))")
    }

    // MARK: Counter-scaled helper

    /// `ztronScrollCounterScaled(anchor:)` reads a non-finite anchor component as 0 and reports it with its caller's
    /// location, at the call, keyed on that component.
    @Test func theCounterScaledHelperReportsANonFiniteAnchorWithTheCallersLocation() {
        var l1 = 0
        for y in [0, 0.25, 1] as [CGFloat] { _ = Color.red.ztronScrollCounterScaled(anchor: UnitPoint(x: .nan, y: y)); l1 = #line }
        let (_, l2) = (Color.red.ztronScrollCounterScaled(anchor: UnitPoint(x: 0.5, y: -.infinity)), #line)
        let want: [(String, Int)] = [
            ("ztronScrollCounterScaled anchor.x is not finite: nan in UnitPoint(x: nan, y: 0.0) -> 0.0", l1),
            ("ztronScrollCounterScaled anchor.y is not finite: -inf in UnitPoint(x: 0.5, y: -inf) -> 0.0", l2),
        ]
        for (text, line) in want {
            let e = logged(text, "\(file):\(line)")
            #expect(e.count == 1, "\(text): \(D.recorded.map(\.message))")
            #expect(e.first?.kind == .counterScaleAnchorNotFinite && e.first?.fileID == file && e.first?.line == UInt(line))
        }
        #expect(D.recorded.count == want.count, "\(D.recorded.map(\.message))")
        // The transform reads the component as 0, as before.
        #expect(CounterScaleEffect.transform(zoom: 2, anchor: UnitPoint(x: .nan, y: 1), size: CGSize(width: 10, height: 10))
                    == CounterScaleEffect.transform(zoom: 2, anchor: UnitPoint(x: 0, y: 1), size: CGSize(width: 10, height: 10)))
    }

    /// The same, from overlays hosted in a scroll view on both hosts: reported once per value at the first layout and
    /// never again over several content-owned reflows, which re-place the overlays by layout alone (the report adds no
    /// body, no host evaluation). Each report names the modifier call that declared the overlay (member or twin).
    @Test(arguments: OSPath.allCases) func layoutReportsArriveFromAHostedOverlayOncePerValueAcrossReflows(path: OSPath) {
        let s = makeState(path)
        let first = #line
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
                .scrollContentIntegralOverlay(anchor: .absolute(Hosted.anchor), overlayAnchor: Hosted.overlayAnchor, size: .ideal,
                                              fileID: "Hosted/Marker.swift", line: 7) {
                    Color.green.frame(width: 8, height: 8).ztronScrollID("d.anchor")
                }
                .ztronScrollContentIntegralOverlay(anchor: .center, overlayAnchor: Hosted.twinOverlayAnchor, size: .ideal,
                                                   fileID: "Hosted/Twin.swift", line: 11) {
                    Color.yellow.frame(width: 4, height: 4).ztronScrollID("d.twin")
                })
        }
        let last = #line
        pump(0.2)
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1000))
        let a = Hosted.anchor, q = Hosted.overlayAnchor
        let t = Hosted.twinOverlayAnchor
        // `nil` place: the default `#fileID` / `#line` of a call in this test.
        let texts: [(D.Kind, String, String?)] = [
            (.aspectRatioOverflow, ".fillMaxWidth(height: .aspectRatio(\(Hosted.tinyRatio))) -> 0.0", nil),
            (.aspectRatioOverflow, ".fillMaxHeight(width: .aspectRatio(\(Hosted.hugeRatio))) -> 0.0", nil),
            (.anchorNotFinite, "x is not finite: nan in .absolute(\(a)) -> 0.0", "Hosted/Marker.swift:7"),
            (.overlayAnchorNotFinite, "y is not finite: inf in UnitPoint(x: \(q.x), y: \(q.y)) -> 0.0", "Hosted/Marker.swift:7"),
            (.overlayAnchorNotFinite, "x is not finite: -inf in UnitPoint(x: \(t.x), y: \(t.y)) -> 0.0", "Hosted/Twin.swift:11"),
        ]
        func expectOnce(_ label: String) {
            for (kind, text, place) in texts {
                let e = logged(kind, containing: text)
                #expect(e.count == 1, "\(path) \(label) \(text): \(D.recorded.map(\.message))")
                guard let entry = e.first else { continue }
                if let place {
                    #expect(entry.message.hasSuffix(" (\(place), at layout)"), "\(entry.message)")
                } else {
                    #expect(entry.fileID == file && entry.line.map { $0 > UInt(first) && $0 < UInt(last) } == true,
                            "the member call in this test: \(entry.message)")
                    #expect(entry.message.hasSuffix(" (\(file):\(entry.line ?? 0), at layout)"), "\(entry.message)")
                }
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
