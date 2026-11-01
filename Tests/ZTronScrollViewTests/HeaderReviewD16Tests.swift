import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Review d16 (M8b-3 seamless header): the reviewers' probes (wf_c4f01d95-d16-4 and others), kept as regression tests of
/// the fixes (SPEC S10, user decisions 2026-10-26). Each test states the rule it checks.
@MainActor
@Suite(.serialized)
struct HeaderReviewD16Tests {
    final class Log {
        var sizes: [CGSize] = []
        var last: CGSize = .zero
        var minY: CGFloat = .nan
    }

    /// Fills its proposal (the header's live frame) and logs every size it is laid out at.
    struct LogProbe: View {
        let log: Log
        var body: some View {
            GeometryReader { g in
                let _ = record(g)
                Color.red
            }
        }
        func record(_ g: GeometryProxy) {
            log.sizes.append(g.size)
            log.last = g.size
            log.minY = g.frame(in: .global).minY
        }
    }

    final class Model: ObservableObject {
        @Published var narrow = false
        @Published var tall = false
    }

    func window<V: View>(_ view: V, size: CGSize = CGSize(width: 402, height: 874)) -> UIWindow {
        let w = UIWindow(frame: CGRect(origin: .zero, size: size))
        w.rootViewController = UIHostingController(rootView: view)
        w.makeKeyAndVisible()
        pump(0.4)
        return w
    }

    // MARK: 1. App-driven animated resize of a horizontal view's banner
    // (The same test with `.vertical` passes on both paths: the layout-driven header is final in the animated pass.)

    /// An app-driven animated width change (`withAnimation { frame(width:) }`): the header's frame must be final in the
    /// ANIMATED layout pass (the layout's `R(W)`), not changed again by the unanimated resize commit (which re-sets the
    /// frame without animation: the header lands at once while the content's top interpolates, the baseline's 90 pt seam).
    struct WidthHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let axes: Axis.Set
        let log: Log
        let overflow: ZTronHeaderOverflow
        var body: some View {
            ZTronScrollView(axes, state: state) {
                if axes.contains(.vertical) { Color.green.frame(height: 4000) } else { Color.green.frame(width: 4000) }
            }
            .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), overflow: overflow) { _ in LogProbe(log: log) }
            .frame(width: model.narrow ? 241 : 402)
            .frame(maxWidth: .infinity)
        }
    }

    func widthChangeFrames(path: OSPath, axes: Axis.Set, overflow: ZTronHeaderOverflow = .uncapped,
                           startNarrow: Bool = false) -> (log: Log, state: ZTronScrollState, drawnTops: [CGFloat], headerBottoms: [CGFloat]) {
        let log = Log(), model = Model()
        model.narrow = startNarrow
        let s = makeState(path)
        let w = withOSPath(path) { window(WidthHost(model: model, state: s, axes: axes, log: log, overflow: overflow)) }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        pump(0.3)
        s.endOfTurn()
        log.sizes.removeAll()
        withAnimation(.linear(duration: 0.5)) { model.narrow.toggle() }
        var tops: [CGFloat] = [], bottoms: [CGFloat] = []
        for _ in 0..<40 {
            pump(1.0 / 60)
            if let p = s.probe.pending {
                // Window coordinates: the viewport's origin is the header slot's top minus top0.
                let origin = log.minY - HeaderMath.top0(s.peek.metrics)
                tops.append(origin - p.offset.y)
                bottoms.append(log.minY + log.last.height)
            }
        }
        pump(0.4)
        return (log, s, tops, bottoms)
    }

    @Test(arguments: OSPath.allCases, [Axis.Set.horizontal, .vertical])
    func anAnimatedWidthChangeSetsTheHeaderFrameInTheAnimatedPass(path: OSPath, axes: Axis.Set) {
        let (log, s, tops, bottoms) = widthChangeFrames(path: path, axes: axes)
        let tag = "\(path) \(axes == .vertical ? "vertical" : "horizontal")"
        let finalR = s.peek.metrics.header?.resting ?? -1
        #expect(abs(finalR - 241 * 9 / 16) < 0.5, "\(tag): R at 241 (\(finalR))")
        // Every frame the header was laid out at the new width must already have the new height.
        let stale = log.sizes.filter { abs($0.width - 241) < 0.5 && abs($0.height - 241 * 9 / 16) > 0.5 }
        #expect(stale.isEmpty, "\(tag): header laid out at the new width with a stale height \(stale), then re-set by the commit (all: \(log.sizes))")
        // Diagnostics only: a GeometryReader reports the header's model (final) frame, not the presented one, so the
        // drawn content top minus it runs 90 … 0 on BOTH axes (the vertical one is seamless on screen, seam lab); the
        // seam itself is measured by the seam lab (`-horizontal` scenarios).
        let seams = zip(tops, bottoms).map { $0 - $1 }
        print("REVIEW \(tag) header sizes \(log.sizes.prefix(3)) content top - header bottom \(seams.map { Int($0.rounded()) })")
    }

    /// The banner's frame at rest is the state's `R` on both paths (the layout-driven banner agrees with the content's
    /// reserve), also with an overflow limit (the banner's container is the committed one).
    @Test(arguments: OSPath.allCases, [ZTronHeaderOverflow.uncapped, .capped(fraction: 0.2)])
    func aBannerAtRestIsTheStatesRestingHeight(path: OSPath, overflow: ZTronHeaderOverflow) {
        let (log, s, _, _) = widthChangeFrames(path: path, axes: .horizontal, overflow: overflow)
        let R = s.peek.metrics.header?.resting ?? -1
        #expect(abs(log.last.height - R) < 0.5, "\(path) \(overflow): banner \(log.last) vs R \(R)")
    }

    // MARK: 2. 15/16 path: the overflow limit becomes active during an app-driven animated resize

    /// `.capped(fraction: 0.2)` on a 778 pt container (limit 155.6): at 241 pt `R = W / r = 135.6` (the limit inactive),
    /// at 402 pt `R = 155.6` (limited). The animated pass must lay the header out at the limited `R`, as on 16+.
    @Test(arguments: OSPath.allCases)
    func anOverflowLimitThatTurnsOnDuringAnAnimatedResizeIsInTheAnimatedPass(path: OSPath) {
        let (log, s, _, _) = widthChangeFrames(path: path, axes: .vertical, overflow: .capped(fraction: 0.2), startNarrow: true)
        let R = s.peek.metrics.header?.resting ?? -1
        let container = HeaderMath.containerHeight(viewport: s.peek.metrics.viewportSize, safe: s.peek.metrics.safeAreaInsets,
                                                   adjusted: .vertical)
        #expect(abs(R - container * 0.2) < 0.5, "\(path): limited R \(R) vs \(container * 0.2)")
        let stale = log.sizes.filter { abs($0.width - 402) < 0.5 && abs($0.height - R) > 0.5 }
        // 15–16 KNOWN LIMIT (SPEC S10 "Seamless edges"): iOS 13 layout modifiers have no size proportional to the
        // proposed height, so the 15 path cannot apply `capped(f)` (`f · H`) to the layout's own `H` without a per-frame
        // GeometryReader (S4.6); a limited `R` is the state's there and lands at the commit of an app-driven animated
        // resize. Rotations are unaffected (laid out once, inside UIKit's block).
        withKnownIssue("15-16: an overflow-limited R is the state's in the animated pass (documented limit)") {
            #expect(stale.isEmpty, "\(path): header laid out at 402 pt with the unlimited W / r first \(stale), re-set by the commit (all: \(log.sizes))")
        } when: { path == .forcedFallback }
    }

    // MARK: 3. `.fit` re-measure of an animated header content change

    struct FitContent: View {
        @ObservedObject var model: Model
        let log: Log
        var body: some View {
            Color.red.frame(height: model.tall ? 300 : 150)
                .frame(maxWidth: .infinity)
                .overlay(LogProbe(log: log))
        }
    }

    /// A header content change animated by the app (`withAnimation { tall.toggle() }`): `.fit`'s new resting height moves
    /// the content by the height change. That move must be animated with the change (frames in between), not land in one
    /// frame (an unanimated commit of the new R: the whole content jumps 150 pt while the header's content animates).
    @Test(arguments: OSPath.allCases)
    func aFitReMeasureOfAnAnimatedHeaderContentChangeMovesTheContentWithoutAJump(path: OSPath) {
        let model = Model(), log = Log()
        let s = makeState(path)
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 4000) }
                .withScalingHeader(size: .fit(min: 64)) { _ in FitContent(model: model, log: log) })
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        pump(0.3)
        #expect(abs((s.peek.metrics.header?.resting ?? -1) - 150) < 0.5, "\(path): R 150 first")
        let start = -(s.probe.pending?.offset.y ?? .nan)
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        withAnimation(.linear(duration: 0.5)) { model.tall = true }
        var tops: [CGFloat] = []
        for _ in 0..<45 {
            pump(1.0 / 60)
            if let p = s.probe.pending { tops.append(-p.offset.y) }
        }
        pump(0.3)
        let end = -(s.probe.pending?.offset.y ?? .nan)
        #expect(abs((s.peek.metrics.header?.resting ?? -1) - 300) < 0.5, "\(path): R 300 eventually")
        #expect(abs(s.peek.presentationOffset.y + s.adjustedContentInset.top) < 0.5, "\(path): the content at its top rest")
        #if DEBUG
        // The new R was adopted in the content change's own animated transaction (`adoptHeaderNatural`).
        #expect(ZTronRenderCounters.events.contains { $0.contains("nat-anim 300") },
                "\(path): adopted in the change's transaction (\(ZTronRenderCounters.eventsJoined))")
        #endif
        // The drawn frames: this logic-test host (no UIApplication) ticks an inset-only SwiftUI animation of the content
        // transform only while another animation in the graph runs; on the forced path it drew one frame and froze (so
        // did a direct `withAnimation { setHeaderMetrics }` on BOTH paths, without the header's own animation). The
        // forced lane's frames are measured in the seam lab instead (`fit-rest-preserve-width-grow`).
        guard path == .preferred else { return }
        #expect(abs(end - start - 150) < 0.5, "\(path): the content moved by the height change (\(start) -> \(end))")
        let between = tops.filter { $0 > start + 1 && $0 < end - 1 }
        var steps: [CGFloat] = []
        for i in 1..<max(1, tops.count) { steps.append(tops[i] - tops[i - 1]) }
        let biggest = steps.max() ?? 0
        print("REVIEW fit \(path) drawn content top \(tops.map { Int($0.rounded()) })")
        #expect(between.count >= 5 && biggest < 75,
                "\(path): the content's drawn top went \(start) -> \(end) with \(between.count) frames in between, largest one-frame step \(biggest) pt")
    }

    // MARK: 5. Content that fits, aligned by `defaultScrollAnchor(_:for: .alignment)` (the default of a zoomable view: .center)

    @Test(arguments: OSPath.allCases, HeaderPullCase.allCases)
    func shortAlignedContentKeepsTheHeaderOnTheContent(path: OSPath, mode: HeaderPullCase) {
        let log = Log(), content = Log()
        let s = makeState(path)
        let behavior = mode.behavior
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 300).overlay(LogProbe(log: content)) }
                .defaultScrollAnchor(.center, for: .alignment)
                .withScalingHeader(size: .fixed(min: 64, max: 240), pull: behavior) { _ in LogProbe(log: log) }
                .scalingHeaderPullBehavior(mode.pull))
        }
        defer { unhost(w) }
        pump(0.3)
        let m = s.peek.metrics
        let g = s.headerGeometry
        let top0 = HeaderMath.top0(m)
        let pull = RefreshMath.signedPull(edge: .top, offset: s.peek.presentationOffset, zoom: 1, metrics: m,
                                          alignment: s.contentAlignment)
        let tag = "\(path) \(mode)"
        #expect(abs(pull) < 0.5, "\(tag): the refresher sees no pull at rest (\(pull))")
        #expect(g?.stretch == 0, "\(tag): stretch at rest \(String(describing: g?.stretch))")
        #expect(abs(log.last.height - 240) < 0.5 && abs(log.minY - top0) < 0.5,
                "\(tag): the header at rest is \(log.last.height) tall at y \(log.minY) (top0 \(top0)); content top \(-s.peek.presentationOffset.y)")
        // No gap between the header's bottom and the content's top at rest; under a pull none with `.followContent` (D61)
        // or `.stretch`, the pull itself with `.openGap` (D65: the header stays still).
        let gapAtRest = content.minY - (log.minY + log.last.height)
        s.track(offset: CGPoint(x: 0, y: s.peek.presentationOffset.y - 50), zoom: 1)
        pump(0.1)
        let gapPulled = content.minY - (log.minY + log.last.height)
        let expected: CGFloat = mode == .openGap ? 50 : 0
        #expect(abs(gapAtRest) < 0.5 && abs(gapPulled - expected) < 0.5,
                "\(tag): gap between the header's bottom and the content's top: \(gapAtRest) at rest, \(gapPulled) under a 50 pt pull (expected \(expected))")
    }

    // MARK: 6. `snapHeader(to: .expanded)` during a refresh hold

    @Test(arguments: OSPath.allCases)
    func snappingAnExpandedHeaderDuringARefreshHoldDoesNotHideTheIndicator(path: OSPath) {
        let s = makeState(path)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 402, height: 874), contentSize: CGSize(width: 402, height: 3000),
                                   safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), displayScale: 3))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        s.headerSpec = HeaderSizing(size: .fixed(min: 64, max: 240), behavior: .preserve, snap: .disabled)
        s.headerSpecChanged()
        s.setRefreshHold(EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0), followsOffset: true)
        let before = s.peek.presentationOffset.y
        #expect(abs(before + s.adjustedContentInset.top) < 0.5, "\(path): resting with the hold open")
        #expect(s.headerGeometry?.progress == 0, "\(path): already expanded")
        s.snapHeader(to: .expanded, animated: false)
        let after = s.peek.presentationOffset.y
        let pull = RefreshMath.signedPull(edge: .top, offset: s.peek.presentationOffset, zoom: 1, metrics: s.peek.metrics,
                                          alignment: .topLeading)
        #expect(abs(after - before) < 0.5, "\(path): an expanded header snapped to .expanded moved the content by \(after - before); the hold's gap (pull \(pull)) closed")
    }

    /// From inside the band `.expanded` returns the content to its top rest with the hold's gap open (`o′ = −hold`).
    @Test(arguments: OSPath.allCases)
    func snappingToExpandedFromTheBandDuringARefreshHoldKeepsTheIndicatorsGap(path: OSPath) {
        let s = makeState(path)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 402, height: 874), contentSize: CGSize(width: 402, height: 3000),
                                   safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), displayScale: 3))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        s.headerSpec = HeaderSizing(size: .fixed(min: 64, max: 240), behavior: .preserve, snap: .disabled)
        s.headerSpecChanged()
        s.setRefreshHold(EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0), followsOffset: true)
        s.track(offset: CGPoint(x: 0, y: 100 - HeaderMath.base(s.peek.metrics)), zoom: 1)
        s.snapHeader(to: .expanded, animated: false)
        let o = HeaderMath.headerOffset(offset: s.peek.presentationOffset, zoom: 1, metrics: s.peek.metrics)
        #expect(abs(o + 60) < 0.5, "\(path): o' \(o) (the top rest of the hold is -60)")
        #expect(abs(s.peek.presentationOffset.y + s.adjustedContentInset.top) < 0.5, "\(path): the content's top rest")
    }

    // MARK: 7. `.frostedGlass` / `.ambientBlur` radius edge values

    @Test func theFrostedGlassRadiusMappingIsMonotonicIncludingInfinity() {
        func name(_ r: CGFloat) -> String { String(describing: ZTronHeaderBackground.material(radius: r)) }
        #expect(name(1000) == String(describing: Material.ultraThickMaterial))
        #expect(name(.infinity) == String(describing: Material.ultraThickMaterial), "an infinite radius picks \(name(.infinity))")
        #expect(name(-5) == String(describing: Material.ultraThinMaterial))
        #expect(name(-.infinity) == String(describing: Material.ultraThinMaterial))
        #expect(name(.nan) == String(describing: Material.regularMaterial))
        // Monotonic: a larger radius never picks a thinner material.
        let order = [Material.ultraThinMaterial, .thinMaterial, .regularMaterial, .thickMaterial, .ultraThickMaterial]
            .map { String(describing: $0) }
        let ranks = stride(from: -10.0, through: 100.0, by: 0.5).map { order.firstIndex(of: name(CGFloat($0))) ?? -1 }
        #expect(ranks.allSatisfy { $0 >= 0 } && zip(ranks, ranks.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func theAmbientBlurRadiusIsTheStrongestForInfinityAndNoneForNegativeOrNaN() {
        #expect(ZTronHeaderBackground.blurRadius(.infinity) == ZTronHeaderBackground.maximumBlurRadius)
        #expect(ZTronHeaderBackground.blurRadius(1e9) == ZTronHeaderBackground.maximumBlurRadius)
        #expect(ZTronHeaderBackground.blurRadius(30) == 30)
        #expect(ZTronHeaderBackground.blurRadius(-4) == 0)
        #expect(ZTronHeaderBackground.blurRadius(-.infinity) == 0)
        #expect(ZTronHeaderBackground.blurRadius(.nan) == 0)
    }

    // MARK: 8. `.ambientBlur`: the copy's readers are cold

    final class Runs { var n = 0 }

    struct ReaderHeader: View {
        let header: ZTronHeaderProxy
        let runs: Runs
        var body: some View {
            ZTronHeaderGeometryReader(header, of: \.height) { h -> Color in
                runs.n += 1
                return Color(white: Double(min(max(h / 400, 0), 1)))
            }
        }
    }

    /// A header with a per-frame reader (`ZTronHeaderGeometryReader(of: \.height)`): its content closure runs once per
    /// frame of collapse / stretch, with or without a background. The `.ambientBlur` copy's reader is cold (SPEC S10: the
    /// copy never runs per frame): the same count as without a background.
    @Test(arguments: OSPath.allCases)
    func theAmbientCopysReaderNeverRunsPerFrame(path: OSPath) {
        func runs(_ background: ZTronHeaderBackground?) -> Int {
            let runs = Runs()
            let s = makeState(path)
            let w = withOSPath(path) {
                window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 3000) }
                    .withScalingHeader(size: .fixed(min: 64, max: 240), pull: .stretch, background: background) {
                        ReaderHeader(header: $0, runs: runs)
                    })
            }
            defer { unhost(w) }
            pump(0.3)
            runs.n = 0
            for o in stride(from: -50, through: 250, by: 30) {
                s.track(offset: CGPoint(x: 0, y: CGFloat(o) - HeaderMath.base(s.peek.metrics)), zoom: 1)
                pump(0.05)
            }
            return runs.n
        }
        let plain = runs(nil), color = runs(.color(.gray)), ambient = runs(.ambientBlur(radius: 20))
        #expect(plain >= 9, "\(path): the reader follows the frames (\(plain))")
        #expect(color == plain, "\(path): .color \(color) vs none \(plain)")
        #expect(ambient == plain, "\(path): .ambientBlur \(ambient) vs none \(plain): the copy's reader ran per frame")
    }

    final class Seen { var heights: [CGFloat] = [] }

    struct RestingProbe: View {
        let header: ZTronHeaderProxy
        let seen: Seen
        var body: some View {
            ZTronHeaderGeometryReader(header, of: \.restingHeight) { r -> Color in
                seen.heights.append(r)
                return Color.orange
            }
        }
    }

    /// The cold reader in the copy still follows a cold change: a new resting height (a resize) reaches both instances.
    @Test(arguments: OSPath.allCases)
    func theAmbientCopysReaderFollowsAColdChange(path: OSPath) {
        let seen = Seen()
        let s = makeState(path)
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 3000) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), background: .ambientBlur()) {
                    RestingProbe(header: $0, seen: seen)
                })
        }
        defer { unhost(w) }
        pump(0.3)
        w.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        pump(0.6)
        let R = s.peek.metrics.header?.resting ?? -1
        #expect(abs(R - 874 * 9 / 16) < 0.5, "\(path): R \(R)")
        #expect(seen.heights.suffix(2).allSatisfy { abs($0 - R) < 0.5 }, "\(path): R \(R), seen \(seen.heights)")
    }

    // MARK: 9. The 15–16 content group and blend modes

    struct BlendProbe: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        var body: some View {
            let view = ZTronScrollView(.vertical, state: state) { Color.blue.blendMode(.multiply).frame(height: 3000) }
            ZStack {
                Color.yellow
                // The same view type either way (`withScalingHeader` returns `Self`): toggling keeps the identity.
                model.tall ? view.withScalingHeader(size: .fixed(min: 0, max: 100)) { _ in Color.red } : view
            }
        }
    }

    /// The content's 15–16 `compositingGroup()` isolates a content `.blendMode` from what is behind the scroll view (the
    /// reviewer's pixel probe: a multiply row over a yellow background drew unblended blue on the forced path, blended
    /// on 17+ and on a native ScrollView). So 15–16 group the content only on a view with a scaling header at its first
    /// render (the seam requirement is the header's), latched so that installing or removing the header later never
    /// changes the content's identity. (A logic-test host has no render server, so this checks the latched branch.)
    @Test(arguments: OSPath.allCases, [false, true])
    func theFifteenContentGroupIsOnlyForAViewWithAHeader(path: OSPath, headerFirst: Bool) {
        #if DEBUG
        ZTronRenderCounters.reset()
        let model = Model()
        model.tall = headerFirst
        let s = makeState(path)
        let w = withOSPath(path) { window(BlendProbe(model: model, state: s)) }
        defer { unhost(w) }
        let first = ZTronRenderCounters.notes["content.group"]
        model.tall.toggle()   // install / remove the header at runtime
        pump(0.3)
        let after = ZTronRenderCounters.notes["content.group"]
        if path == .preferred {
            #expect(first == nil && after == nil, "17+: geometryGroup, no latch (\(String(describing: first)))")
        } else {
            #expect(first == (headerFirst ? "compositing" : "none"), "\(path) header first \(headerFirst): \(String(describing: first))")
            #expect(after == first, "\(path): the latch never re-decides (\(String(describing: after)))")
        }
        #endif
    }
}
