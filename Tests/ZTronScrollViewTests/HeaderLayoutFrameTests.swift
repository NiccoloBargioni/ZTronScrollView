import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// M8b-3 seamless header (seam spike A, integrated): the header's frame comes from layout (`HeaderSlotLayout` on 16+,
/// `HeaderFallbackFrame` on 15 / forced): `(1 − p) · R(W, H) + p · min` at the proposed size with the overflow
/// policy (D59) applied by the layout exactly as by the state, equal to the state's layout height once committed (also when
/// the resting height exceeds the viewport, a landscape 16:9 header), the header stack proposed the live frame; the
/// `.preserve` translation; the background; the content's rigid layer group. The `.stretch` growth is not laid out (D69,
/// its drawn scale is `HeaderStretchScaleTests`). The background's accessibility (hidden, the
/// header's controls exposed once) needs a live accessibility tree, which a unit-test host does not build: it is
/// `HeaderUITests.testAmbientBackgroundIsHiddenAndNeverRunsPerFrame`.
@MainActor
@Suite(.serialized)
struct HeaderLayoutFrameTests {
    final class Box {
        var size: CGSize = .zero
        var minY: CGFloat = .nan
    }

    /// Fills the proposal it gets (the live frame) and records it.
    struct Probe: View {
        let box: Box
        var body: some View {
            GeometryReader { g in
                let _ = record(g)
                Color.red
            }
        }
        func record(_ g: GeometryProxy) {
            box.size = g.size
            box.minY = g.frame(in: .global).minY
        }
    }

    /// `.fit`'s probe: a 16:9 ideal height at any width, then the same fill-and-record.
    struct FitProbe: View {
        let box: Box
        var body: some View {
            Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Probe(box: box))
        }
    }

    func window<V: View>(_ view: V, size: CGSize) -> UIWindow {
        let w = UIWindow(frame: CGRect(origin: .zero, size: size))
        w.rootViewController = UIHostingController(rootView: view)
        w.makeKeyAndVisible()
        pump(0.4)
        return w
    }

    enum Start: String, CaseIterable { case rest, half, collapsed }

    func host(_ path: OSPath, size: ZTronHeaderSize, overflow: ZTronHeaderOverflow = .uncapped, start: Start,
              window: CGSize, box: Box) -> (ZTronScrollState, UIWindow) {
        let s = makeState(path)
        switch start {
        case .rest: break
        case .half: s.snapHeader(to: .progress(0.5), animated: false)
        case .collapsed: s.snapHeader(to: .collapsed, animated: false)
        }
        let w = withOSPath(path) {
            self.window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 4000) }
                .withScalingHeader(size: size, overflow: overflow) { _ in
                    if size.isFit { AnyView(FitProbe(box: box)) } else { AnyView(Probe(box: box)) }
                }, size: window)
        }
        // The 15 / forced `.fit` resolves after its measuring pass (a run-loop block later); a loaded host can take a
        // while, and a resize in the same turn as the first resolution would capture its intent from the header-less
        // origin (D16), not what this suite looks at.
        var n = 0
        while s.peek.metrics.header == nil, n < 60 { pump(0.1); n += 1 }
        pump(0.3)
        if s.peek.metrics.header == nil {
            Issue.record("\(path) \(size) \(start): the header never resolved (natural \(String(describing: s.headerNatural)), measurements \(s.headerMeasurements))")
        }
        return (s, w)
    }

    static let sizes: [ZTronHeaderSize] = [.fixed(min: 64, max: 240), .aspectRatio(16.0 / 9.0, min: 64), .fit(min: 64)]
    static let overflows: [ZTronHeaderOverflow] = [.uncapped, .capped(fraction: 0.5), .refit]

    @Test(arguments: OSPath.allCases, [CGSize(width: 402, height: 874), CGSize(width: 874, height: 402)])
    func theLayoutFrameIsTheStateHeight(path: OSPath, windowSize: CGSize) {
        for overflow in Self.overflows {
            for size in Self.sizes {
                for start in Start.allCases {
                    let box = Box()
                    let (s, w) = host(path, size: size, overflow: overflow, start: start, window: windowSize, box: box)
                    guard let m = s.peek.metrics.header, let g = s.headerGeometry else {
                        Issue.record("\(size) \(start): unresolved"); unhost(w); continue
                    }
                    let p: CGFloat = start == .rest ? 0 : start == .half ? 0.5 : 1
                    let expected = m.resting - p * m.band
                    let tag = "\(path) \(size) \(overflow) \(start) \(windowSize)"
                    #expect(abs(g.height - expected) < 0.5, "\(tag): state h \(g.height) vs \(expected)")
                    #expect(abs(box.size.height - g.height) < 0.5, "\(tag): layout h \(box.size.height) vs state \(g.height) (R \(m.resting))")
                    #expect(abs(box.size.width - s.peek.metrics.viewportSize.width) < 0.5, "\(tag): full width \(box.size.width)")
                    #expect(abs(box.minY - HeaderMath.top0(s.peek.metrics)) < 0.5, "\(tag): top edge \(box.minY)")
                    if overflow != .uncapped {
                        #expect(m.resting <= windowSize.height + 0.5, "\(tag): the policy limits R (\(m.resting))")
                    }
                    unhost(w)
                }
            }
        }
    }

    /// A width change (window resize, no animation): the layout's height at the new size equals the committed one, the
    /// progress kept; `.fit` adopts the layout's measurement in the viewport commit (one measurement); the overflow policy
    /// is applied to the new container on both sides.
    @Test(arguments: OSPath.allCases) func aSizeChangeKeepsLayoutAndStateTogether(path: OSPath) {
        for overflow in Self.overflows {
            for size in Self.sizes {
                for start in [Start.rest, .half] {
                    let box = Box()
                    let (s, w) = host(path, size: size, overflow: overflow, start: start, window: CGSize(width: 402, height: 874), box: box)
                    let measurements = s.headerMeasurements
                    // A synchronous main-actor test never drains main-queue blocks, so the state's end-of-turn hop (D16)
                    // never runs: the turn origin captured when the 15-path `.fit` header resolved (an idle inset change)
                    // would still stand at the resize. An app's next turn clears it; do that here.
                    s.endOfTurn()
                    w.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
                    pump(0.8)
                    let tag = "\(path) \(size) \(overflow) \(start)"
                    guard let m = s.peek.metrics.header, let g = s.headerGeometry else {
                        Issue.record("\(tag): lost"); unhost(w); continue
                    }
                    // The test host's window keeps the device's safe area (62 / 34 on an iPhone 18 Pro): the container.
                    let mm = s.peek.metrics
                    let container = HeaderMath.containerHeight(viewport: mm.viewportSize, safe: mm.safeAreaInsets, adjusted: .vertical)
                    let limit: CGFloat
                    switch overflow {
                    case .uncapped: limit = .infinity
                    case let .capped(f): limit = container * f
                    case .refit: limit = container
                    }
                    if case .fixed = size {
                        #expect(abs(m.resting - min(240, limit)) < 0.5, "\(tag): R \(m.resting)")
                    } else {
                        #expect(abs(m.resting - max(min(64, limit), min(874 / (16.0 / 9.0), limit))) < 0.5, "\(tag): R \(m.resting) at 874")
                    }
                    let p: CGFloat = start == .rest || m.band == 0 ? 0 : 0.5
                    #expect(abs(g.progress - p) < 0.01, "\(tag): progress kept \(g.progress)")
                    #expect(abs(box.size.height - g.height) < 0.5, "\(tag): layout \(box.size.height) vs state \(g.height)")
                    if size.isFit, overflow == .uncapped {
                        #expect(s.headerMeasurements == measurements + 1, "\(tag): one measurement per width change")
                    }
                    unhost(w)
                }
            }
        }
    }

    /// A system rotation is laid out ONCE, inside UIKit's animation block, and Core Animation interpolates only what changes
    /// there; a value committed a run-loop turn later lands at once (seam lab, 15 path, `.fit` half collapsed: header and
    /// content jumped 98 pt at the rotation's start). So the synchronous layout of the new size must already commit the new
    /// resting height (`.fit`: its measurement at the new width), the header's frame and the state agreeing, with no
    /// run-loop turn in between.
    @Test(arguments: OSPath.allCases) func aSizeChangeCommitsTheNewRestingHeightInsideItsLayout(path: OSPath) {
        for size in Self.sizes {
            for start in [Start.rest, .half] {
                let box = Box()
                let (s, w) = host(path, size: size, start: start, window: CGSize(width: 402, height: 874), box: box)
                s.endOfTurn()
                w.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
                w.rootViewController?.view.setNeedsLayout()
                w.rootViewController?.view.layoutIfNeeded()
                let tag = "\(path) \(size) \(start)"
                let expected: CGFloat
                if case .fixed = size { expected = 240 } else { expected = 874 * 9 / 16 }
                let r = s.peek.metrics.header?.resting ?? -1
                let h = s.headerGeometry?.height ?? -1
                #expect(abs(r - expected) < 0.5, "\(tag): R \(r) after the synchronous layout (natural \(String(describing: s.headerNatural)))")
                #expect(abs(box.size.height - h) < 0.5, "\(tag): layout \(box.size.height) vs state \(h)")
                pump(0.6)
                unhost(w)
            }
        }
    }

    @Test func theFallbackPlan() {
        let m = HeaderMetrics(min: 64, resting: 226.125, behavior: .preserve, width: 402)
        var live = HeaderLiveInput(size: .aspectRatio(16.0 / 9.0, min: 64), metrics: m, progress: 0.5, stretch: 0, stateHeight: 145.0625)
        var plan = HeaderFallbackPlan(live)
        #expect(plan.ratio == 16.0 / 9.0 / 0.5 && plan.innerPad == -32 && plan.outerPad == 32 && plan.maxHeight == .infinity)
        live.progress = 1
        plan = HeaderFallbackPlan(live)
        #expect(plan.minHeight == live.stateHeight && plan.maxHeight == live.stateHeight && plan.ratio == HeaderFallbackPlan.neutralRatio,
                "collapsed: the state's height")
        // An active overflow limit (R below W / r): the state's height, the limited R does not follow the width.
        live = HeaderLiveInput(size: .aspectRatio(16.0 / 9.0, min: 64), overflow: .refit,
                               metrics: HeaderMetrics(min: 64, resting: 381, behavior: .preserve, width: 874),
                               progress: 0.5, stateHeight: 222.5)
        plan = HeaderFallbackPlan(live)
        #expect(plan.minHeight == 222.5 && plan.ratio == HeaderFallbackPlan.neutralRatio, "limited: the state's height")
        live = HeaderLiveInput(size: .fit(min: 64), metrics: m, progress: 0.1 / m.band, stretch: 0, stateHeight: 226.025)
        live.natural = 226.125
        plan = HeaderFallbackPlan(live)
        #expect(plan.fitRest && abs(plan.outerPad + 0.1) < 1e-9, ".fit at rest within the snap")
        live.natural = 491.625
        #expect(!HeaderFallbackPlan(live).fitRest, "a limited .fit R (natural 491.625 > R): the state's height")
        live.natural = 226.125
        live.progress = 0.2
        #expect(!HeaderFallbackPlan(live).fitRest)
        let fit = HeaderLiveInput(size: .fit(min: 64), metrics: m, progress: 0.5, stretch: 0, stateHeight: 0)
        #expect(abs(HeaderMath.liveHeight(width: 600, containerHeight: nil, natural: 337.5, fit) - (0.5 * 337.5 + 32)) < 1e-9)
        // D69: the stretch is the scale effect's, never in the plan (nor in the live height).
        let stretched = HeaderMetrics(min: 64, resting: 226.125, behavior: .stretch, width: 402)
        live = HeaderLiveInput(size: .aspectRatio(16.0 / 9.0, min: 64), metrics: stretched, progress: 0, stretch: 60,
                               stateHeight: 226.125)
        plan = HeaderFallbackPlan(live)
        #expect(plan.ratio == 16.0 / 9.0 && plan.innerPad == 0 && plan.outerPad == 0 && plan.floor == 64,
                ".aspectRatio under a pull: the resting aspect box (\(plan))")
        live = HeaderLiveInput(size: .fit(min: 64), metrics: stretched, progress: 0, stretch: 60, stateHeight: 226.125)
        live.natural = 226.125
        plan = HeaderFallbackPlan(live)
        #expect(plan.fitRest && plan.outerPad == 0, ".fit under a pull: at its ideal height (\(plan))")
        live = HeaderLiveInput(size: .fixed(min: 64, max: 240),
                               metrics: HeaderMetrics(min: 64, resting: 240, behavior: .stretch, width: 402),
                               progress: 0, stretch: 60, stateHeight: 240)
        plan = HeaderFallbackPlan(live)
        #expect(plan.minHeight == 240 && plan.maxHeight == 240, ".fixed under a pull: R, not R + g (\(plan))")
        #expect(HeaderMath.liveHeight(width: 402, containerHeight: nil, natural: nil, live) == 240, "no stretch in the live height")
        var committed = HeaderLiveInput(size: .fit(min: 64), metrics: m)
        committed.committedContainer = 778
        #expect(HeaderMath.liveHeight(width: 402, containerHeight: 778, natural: 300, committed) == 226.125,
                ".fit at the committed width and container keeps the committed R")
    }

    /// D78: with the slot's `W × H` (`HeaderSlotReader`) the 15 plan of a non-`.fit` size is `h_L(W, H)`
    /// (`HeaderMath.liveHeight`, 16+'s formula): the overflow limit and `min ≥ R` resolved against the slot, not the
    /// committed metrics; no slot (or an unusable one): the committed plan.
    @Test func theFallbackPlanFromTheSlot() {
        let committed = HeaderMetrics(min: 64, resting: 194.5, behavior: .preserve, width: 402)
        var live = HeaderLiveInput(size: .aspectRatio(16.0 / 9.0, min: 64), overflow: .capped(fraction: 0.25),
                                   metrics: committed, progress: 0.5, stateHeight: 129.25)
        live.committedContainer = 778
        // S-RS-2: 402 → 241 pt, the limit turns off (W / r = 135.5625 < 194.5): (1 − p) · 135.5625 + p · 64.
        var plan = HeaderFallbackPlan(live, slot: CGSize(width: 241, height: 778))
        #expect(abs((plan.minHeight ?? -1) - (0.5 * 241 * 9 / 16 + 32)) < 1e-9 && plan.maxHeight == plan.minHeight,
                "the slot's width: \(plan)")
        #expect(plan.ratio == HeaderFallbackPlan.neutralRatio && plan.innerPad == 0 && plan.outerPad == 0 && !plan.fitBox)
        // The committed viewport: the state's own height.
        plan = HeaderFallbackPlan(live, slot: CGSize(width: 402, height: 778))
        #expect(abs((plan.minHeight ?? -1) - 129.25) < 1e-9, "the committed viewport: \(plan)")
        // A height change engages `.capped(0.5)` on `.fixed`: L = 0.5 · 287.6.
        live = HeaderLiveInput(size: .fixed(min: 64, max: 240), overflow: .capped(fraction: 0.5),
                               metrics: HeaderMetrics(min: 64, resting: 240, behavior: .preserve, width: 402),
                               progress: 0, stateHeight: 240)
        live.committedContainer = 778
        plan = HeaderFallbackPlan(live, slot: CGSize(width: 402, height: 287.6))
        #expect(abs((plan.minHeight ?? -1) - 143.8) < 1e-9, ".fixed under the slot's limit: \(plan)")
        // `.refit` at the slot's height; `min ≥ R` there: a fixed header of height min (band 0).
        live = HeaderLiveInput(size: .aspectRatio(16.0 / 9.0, min: 64), overflow: .refit,
                               metrics: HeaderMetrics(min: 64, resting: 226.125, behavior: .preserve, width: 402),
                               progress: 0.5, stateHeight: 145.0625)
        live.committedContainer = 778
        plan = HeaderFallbackPlan(live, slot: CGSize(width: 402, height: 200))
        #expect(abs((plan.minHeight ?? -1) - (0.5 * 200 + 32)) < 1e-9, ".refit at the slot's H: \(plan)")
        plan = HeaderFallbackPlan(live, slot: CGSize(width: 402, height: 50))
        #expect(abs((plan.minHeight ?? -1) - 50) < 1e-9, "min limited to L = 50 = R: \(plan)")
        // `.slideBehind` (D68): R(W, H) at every progress.
        live = HeaderLiveInput(size: .aspectRatio(16.0 / 9.0, min: 64),
                               metrics: HeaderMetrics(min: 0, resting: 226.125, behavior: .preserve,
                                                      collapse: .slideBehind(parallax: 1), width: 402),
                               progress: 0.5, stateHeight: 226.125)
        live.committedContainer = 778
        plan = HeaderFallbackPlan(live, slot: CGSize(width: 241, height: 778))
        #expect(abs((plan.minHeight ?? -1) - 241 * 9 / 16) < 1e-9, ".slideBehind: R(W) \(plan)")
        // No usable slot: the committed plan.
        #expect(HeaderFallbackPlan(live, slot: CGSize(width: 0, height: 778)) == HeaderFallbackPlan(live))
        #expect(HeaderFallbackPlan(live, slot: nil) == HeaderFallbackPlan(live))
        // Fully collapsed to a zero `min`: the plan's floor height.
        live = HeaderLiveInput(size: .aspectRatio(16.0 / 9.0), metrics: HeaderMetrics(min: 0, resting: 226.125,
                                                                                     behavior: .preserve, width: 402),
                               progress: 1, stateHeight: 0)
        live.committedContainer = 778
        plan = HeaderFallbackPlan(live, slot: CGSize(width: 402, height: 778))
        #expect(plan.minHeight == HeaderFallbackPlan.minimumHeight, "collapsed to 0: \(plan)")
    }

    /// Under a pull (layout = state, through the real container, both paths): a `.preserve` `.openGap` header (D65, the
    /// default) stays at `top0` with its height and the content's top is its bottom edge + the pull; a `.preserve`
    /// `.followContent` header (D61) keeps its height and moves down by the pull, its bottom edge on the content's top;
    /// `.stretch` grows with its top pinned. The layout's frame is the state's (`top0 + translation`, `h`) in every case.
    @Test(arguments: OSPath.allCases, HeaderPullCase.allCases)
    func aPullKeepsOrMovesThePreservedHeaderAndGrowsTheStretchedOne(path: OSPath, mode: HeaderPullCase) {
        let box = Box()
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fixed(min: 64, max: 240), pull: mode.behavior) { _ in Probe(box: box) }
                .scalingHeaderPullBehavior(mode.pull),
                   size: CGSize(width: 402, height: 874))
        }
        defer { unhost(w) }
        #expect(s.peek.metrics.header?.pull == mode.pull)
        let bodies = counts.bodies
        for g in [30, 90, 0] as [CGFloat] {
            s.track(offset: CGPoint(x: 0, y: -g - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.1)
            let m = s.peek.metrics
            let top0 = HeaderMath.top0(m)
            let contentTop = -s.peek.presentationOffset.y
            switch mode {
            case .openGap:
                #expect(abs(box.minY - top0) < 0.5 && abs(box.size.height - 240) < 0.5,
                        "\(path) g \(g): still (\(box.minY)), height R (\(box.size.height))")
                #expect(abs(contentTop - (box.minY + box.size.height) - g) < 0.5,
                        "\(path) g \(g): the gap below the header is the pull (\(contentTop - box.minY - box.size.height))")
            case .followContent:
                #expect(abs(box.minY - (top0 + g)) < 0.5 && abs(box.size.height - 240) < 0.5,
                        "\(path) g \(g): moved down by the pull (\(box.minY)), height R (\(box.size.height))")
                #expect(abs(box.minY + box.size.height - contentTop) < 0.5, "\(path) g \(g): bottom edge on the content's top")
            case .stretch:
                // D69: laid out at R (the growth is the scale effect's; drawn frame: `HeaderStretchScaleTests`).
                #expect(abs(box.minY - top0) < 0.5 && abs(box.size.height - 240) < 0.5,
                        "\(path) g \(g): top pinned (\(box.minY)), laid out at R (\(box.size.height))")
                #expect(abs(top0 + 240 + g - contentTop) < 0.5, "\(path) g \(g): the content's top is the scaled bottom edge")
            }
            // Layout = state: the frame the state describes at this offset.
            let header = m.header!
            let o = HeaderMath.headerOffset(offset: s.peek.presentationOffset, zoom: 1, metrics: m)
            #expect(abs(box.minY - (top0 + HeaderMath.translation(o: o, m: header))) < 0.5
                        && abs(box.size.height - HeaderMath.layoutHeight(o: o, m: header)) < 0.5, "\(path) \(mode) g \(g): layout = state")
        }
        #expect(counts.bodies == bodies, "no content body under a pull")
    }

    /// The background: the ambient copy is a second instance of the builder result (its root body runs once more per
    /// cold change), never per frame (collapse, stretch, a resize), and the builder itself still runs once.
    @Test(arguments: OSPath.allCases) func theAmbientCopyRunsOncePerColdChangeNeverPerFrame(path: OSPath) {
        final class Runs { var n = 0 }
        struct Root: View {
            let runs: Runs
            var body: some View {
                runs.n += 1
                return Color.orange.aspectRatio(1, contentMode: .fit)
            }
        }
        let runs = Runs(), counts = BodyCount()
        let s = makeState(path)
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fixed(min: 64, max: 240), pull: .stretch,
                                   background: .ambientBlur(radius: 12)) { _ in Root(runs: runs) },
                   size: CGSize(width: 402, height: 874))
        }
        defer { unhost(w) }
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        let installed = runs.n
        #expect(installed >= 2, "the content and its ambient copy: two instances (\(installed))")
        let bodies = counts.bodies
        for o in [-60, -20, 0, 50, 120, 176, 300, 0] as [CGFloat] {
            s.track(offset: CGPoint(x: 0, y: o - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.05)
        }
        w.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        pump(0.6)
        w.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        pump(0.6)
        #expect(runs.n == installed, "\(path): no header body (content or copy) per frame or per resize (\(runs.n - installed))")
        #expect(counts.bodies == bodies, "\(path): no content body")
        #if DEBUG
        #expect(ZTronRenderCounters.value("header.builder") == 0, "\(path): the builder never ran per frame")
        #endif
    }

    /// The content's rigid layer group (17+ `geometryGroup`, 15–16 `compositingGroup`): no content body and the same
    /// identity across resizes, scrolling and header collapse; the group adds no offscreen trigger (no rasterization,
    /// filter or mask anywhere in the scroll view's layer tree).
    @Test(arguments: OSPath.allCases) func theRigidGroupKeepsIdentityAndAddsNoOffscreenPass(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64)) { _ in Color.red },
                   size: CGSize(width: 402, height: 874))
        }
        defer { unhost(w) }
        let bodies = counts.bodies
        #expect(counts.ids.count == 1)
        for size in [CGSize(width: 874, height: 402), CGSize(width: 600, height: 874), CGSize(width: 402, height: 874)] {
            w.frame = CGRect(origin: .zero, size: size)
            pump(0.5)
        }
        s.track(offset: CGPoint(x: 0, y: 100 - HeaderMath.base(s.peek.metrics)), zoom: 1)
        pump(0.1)
        #expect(counts.bodies == bodies, "\(path): no content body")
        #expect(counts.ids.count == 1, "\(path): the content's identity (its @State) survives")
        var offenders: [String] = []
        func walk(_ layer: CALayer, _ depth: Int) {
            if layer.shouldRasterize { offenders.append("rasterized \(type(of: layer)) at \(depth)") }
            if let f = layer.filters, !f.isEmpty { offenders.append("filters \(f) on \(type(of: layer)) at \(depth)") }
            if layer.mask != nil { offenders.append("mask on \(type(of: layer)) at \(depth)") }
            for sub in layer.sublayers ?? [] { walk(sub, depth + 1) }
        }
        if let root = w.rootViewController?.view.layer { walk(root, 0) }
        #expect(offenders.isEmpty, "\(path): \(offenders)")
    }

    /// The header offset `o′` is the header layout's animatable data (16+ `HeaderSlotLayout`, 15 `HeaderFallbackFrame` /
    /// `HeaderTranslation`): an interpolated `o′` re-derives the progress, stretch, translation and height exactly as the
    /// leaf derives them from a target at that `o′` (pull, band, its edges, past it); while a resize is open
    /// (`followsOffset` false) only `offset` moves, so the resize intent's anchor stays bit-stable.
    @Test func theLiveInputAtAnOffsetIsTheLeafsDerivation() {
        for mode in HeaderPullCase.allCases {
            let behavior = mode.behavior
            var m = ScrollMetrics()
            m.viewportSize = CGSize(width: 402, height: 874)
            m.safeAreaInsets = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
            m.header = HeaderMetrics(min: 64, resting: 240, behavior: behavior, pull: mode.pull, width: 402)
            m.adjustedContentInset = EdgeInsets(top: 302, leading: 0, bottom: 34, trailing: 0)
            func leaf(_ o: CGFloat) -> HeaderLiveInput {
                HeaderFrameModifier.liveInput(size: .fixed(min: 64, max: 240), overflow: .uncapped, metrics: m,
                                              edges: .vertical, target: CGPoint(x: 0, y: o - 302), zoom: 1)
            }
            let start = leaf(0)
            #expect(start.followsOffset && start.offset == 0)
            for o in [-80, -10, 0, 30, 88, 175.5, 176, 250] as [CGFloat] {
                let a = start.at(offset: o), b = leaf(o)
                #expect(a == b, "\(behavior) o′ \(o): \(a) vs \(b)")
            }
            let pulled = start.at(offset: -80)
            let translation: CGFloat = mode == .followContent ? 80 : 0, visible: CGFloat = behavior == .stretch ? 320 : 240
            // D69: the layout height never has the stretch; the visible height does.
            #expect(pulled.translation == translation && pulled.stateHeight == 240 && pulled.visibleHeight == visible
                        && pulled.stretch == (behavior == .stretch ? 80 : 0), "\(mode): \(pulled)")
            if mode == .openGap {
                // D65: the `.openGap` header's live input is the rest's under any pull (only `o′` moves): no new layout work.
                var rest = start
                rest.offset = -80
                #expect(pulled == rest, "openGap: a pull changes only o′")
            }
            var held = leaf(88)
            held.followsOffset = false
            let moved = held.at(offset: 10)
            #expect(moved.offset == 10 && moved.progress == held.progress && moved.stateHeight == held.stateHeight
                        && moved.translation == held.translation && moved.stretch == held.stretch, "held: only o′ moves")
        }
    }

    /// A transaction-driven scroll through the band and back (`withAnimation { scroll(to:) }`) and an animated snap both
    /// ways (the clock path): in every sampled frame the header's bottom edge is on the drawn content's top, frames inside
    /// the band included (the layout's frame used to jump to the final height while the content interpolated, the header
    /// up to 132 pt off the content mid-band, seam lab); no content body runs.
    @Test(arguments: OSPath.allCases) func aTransactionDrivenScrollKeepsTheHeaderOnTheContent(path: OSPath) {
        let box = Box()
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fixed(min: 64, max: 240)) { _ in Probe(box: box) },
                   size: CGSize(width: 402, height: 874))
        }
        defer { unhost(w) }
        let bodies = counts.bodies
        let collapsedBottom = HeaderMath.top0(s.peek.metrics) + 64
        func run(_ label: String, _ motion: () -> Void) {
            var inBand = 0, worst: CGFloat = 0, samples = 0
            motion()
            for _ in 0..<60 {
                pump(1.0 / 60)
                guard let drawn = s.probe.pending?.offset else { continue }
                // The content's drawn top in the window is −y (the viewport is the window here); past the band the
                // content scrolls on under the collapsed header, whose bottom edge stays at `top0 + min`.
                let seam = box.minY + box.size.height - max(-drawn.y, collapsedBottom)
                worst = max(worst, abs(seam))
                samples += 1
                if box.size.height > 64.5, box.size.height < 239.5 { inBand += 1 }
            }
            pump(0.3)
            #expect(worst < 1, "\(path) \(label): header bottom vs drawn content top, worst \(worst) over \(samples)")
            #expect(inBand >= 3, "\(path) \(label): sampled frames inside the band (\(inBand) of \(samples))")
        }
        let base = HeaderMath.base(s.peek.metrics)
        run("scroll to o′ 300") { withAnimation(.linear(duration: 0.5)) { s.scroll(to: CGPoint(x: 0, y: 300 - base)) } }
        #expect(abs(box.size.height - 64) < 0.5, "\(path): collapsed at the end (\(box.size.height))")
        run("scroll back to rest") { withAnimation(.linear(duration: 0.5)) { s.scroll(to: CGPoint(x: 0, y: -base)) } }
        #expect(abs(box.size.height - 240) < 0.5, "\(path): at rest at the end (\(box.size.height))")
        run("snap collapsed") { s.snapHeader(to: .collapsed, animated: true) }
        run("snap expanded") { s.snapHeader(to: .expanded, animated: true) }
        #expect(counts.bodies == bodies, "\(path): no content body")
    }

    /// The background fills the header's live frame in every state (it is the background of the stack the leaf frames):
    /// the `.preserve` pull in both modes (still with `.openGap`, translated with `.followContent`), the `.stretch` growth,
    /// collapse, past the band and after a resize.
    @Test(arguments: OSPath.allCases, HeaderPullCase.allCases)
    func theBackgroundFollowsTheLiveFrame(path: OSPath, mode: HeaderPullCase) {
        let box = Box(), bg = Box()
        let s = makeState(path)
        let behavior = mode.behavior
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 4000) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), pull: behavior,
                                   background: .view { Probe(box: bg) }) { _ in Probe(box: box) }
                .ztronScalingHeaderPullBehavior(mode.pull),
                   size: CGSize(width: 402, height: 874))
        }
        defer { unhost(w) }
        func check(_ label: String) {
            #expect(abs(bg.size.width - box.size.width) < 0.5 && abs(bg.size.height - box.size.height) < 0.5
                        && abs(bg.minY - box.minY) < 0.5,
                    "\(path) \(behavior) \(label): background \(bg.size) at \(bg.minY), header \(box.size) at \(box.minY)")
        }
        check("rest")
        for o in [-60, 50, 400, 0] as [CGFloat] {
            s.track(offset: CGPoint(x: 0, y: o - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.1)
            check("o′ \(o)")
            if o == -60 {
                let top0 = HeaderMath.top0(s.peek.metrics)
                #expect(abs(bg.minY - (mode == .followContent ? top0 + 60 : top0)) < 0.5, "\(path) \(mode): pull")
            }
        }
        s.endOfTurn()
        w.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        pump(0.8)
        check("landscape")
        #expect(abs(bg.size.width - 874) < 0.5, "\(path) \(behavior): the background spans the new width (\(bg.size))")
    }

    /// The header's layer group keeps the header's identity: its `@State` survives resizes, scrolling and collapse, and
    /// its body never re-runs for them (the content's group is `theRigidGroupKeepsIdentityAndAddsNoOffscreenPass`).
    @Test(arguments: OSPath.allCases) func theHeaderGroupKeepsTheHeadersIdentity(path: OSPath) {
        let s = makeState(path)
        let header = BodyCount()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 4000) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64)) { _ in StatefulContent(counts: header) },
                   size: CGSize(width: 402, height: 874))
        }
        defer { unhost(w) }
        let bodies = header.bodies
        #expect(header.ids.count == 1)
        for o in [100, 300, -40, 0] as [CGFloat] {
            s.track(offset: CGPoint(x: 0, y: o - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.05)
        }
        s.endOfTurn()
        for size in [CGSize(width: 874, height: 402), CGSize(width: 600, height: 874), CGSize(width: 402, height: 874)] {
            w.frame = CGRect(origin: .zero, size: size)
            pump(0.5)
        }
        #expect(header.bodies == bodies, "\(path): no header body (\(header.bodies - bodies))")
        #expect(header.ids.count == 1, "\(path): the header's identity (its @State) survives")
    }
}
