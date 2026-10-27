import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// M8b-3 seamless header (seam spike A, integrated): the header's frame comes from layout (`HeaderFrameLayout` on 16+,
/// `HeaderFallbackFrame` on 15 / forced): `(1 − p) · R(W, H) + p · min + stretch` at the proposed size with the overflow
/// policy (D52) applied by the layout exactly as by the state, equal to the state's live height once committed (also when
/// the resting height exceeds the viewport, a landscape 16:9 header), the header stack proposed the live frame; the
/// `.preserve` translation; the background; the content's rigid layer group.
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
        var committed = HeaderLiveInput(size: .fit(min: 64), metrics: m)
        committed.committedContainer = 778
        #expect(HeaderMath.liveHeight(width: 402, containerHeight: 778, natural: 300, committed) == 226.125,
                ".fit at the committed width and container keeps the committed R")
    }

    /// User decision 2026-10-26: a `.preserve` header under a pull keeps its height and moves down by the pull; its bottom
    /// edge is the content's top; `.stretch` grows with its top pinned. Both paths, through the real container.
    @Test(arguments: OSPath.allCases, [ZTronHeaderScalingBehavior.preserve, .stretch])
    func aPullMovesThePreservedHeaderAndGrowsTheStretchedOne(path: OSPath, behavior: ZTronHeaderScalingBehavior) {
        let box = Box()
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fixed(min: 64, max: 240), scalingBehavior: behavior) { _ in Probe(box: box) },
                   size: CGSize(width: 402, height: 874))
        }
        defer { unhost(w) }
        let bodies = counts.bodies
        for g in [30, 90, 0] as [CGFloat] {
            s.track(offset: CGPoint(x: 0, y: -g - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.1)
            let top0 = HeaderMath.top0(s.peek.metrics)
            let contentTop = -s.peek.presentationOffset.y
            switch behavior {
            case .preserve:
                #expect(abs(box.minY - (top0 + g)) < 0.5 && abs(box.size.height - 240) < 0.5,
                        "\(path) g \(g): moved down by the pull (\(box.minY)), height R (\(box.size.height))")
            case .stretch:
                #expect(abs(box.minY - top0) < 0.5 && abs(box.size.height - (240 + g)) < 0.5,
                        "\(path) g \(g): top pinned (\(box.minY)), grown (\(box.size.height))")
            }
            #expect(abs(box.minY + box.size.height - contentTop) < 0.5, "\(path) g \(g): bottom edge on the content's top")
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
                .withScalingHeader(size: .fixed(min: 64, max: 240), scalingBehavior: .stretch,
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

    /// The background is hidden from accessibility: the header's own controls are exposed exactly once with every
    /// background, the ambient copy (a second instance of the same content, with the same identifiers) included. Walks
    /// the hosted window's accessibility tree through the public UIAccessibility container API.
    @Test(arguments: OSPath.allCases) func theHeadersControlsAreExposedExactlyOnceWithEveryBackground(path: OSPath) {
        struct Header: View {
            var body: some View {
                ZStack(alignment: .bottomLeading) {
                    Color.orange.aspectRatio(1, contentMode: .fit)
                    VStack {
                        Text("Title").accessibilityIdentifier("hdr.title")
                        Button("Play") {}.accessibilityIdentifier("hdr.button")
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        let backgrounds: [(String, ZTronHeaderBackground?)] = [
            ("none", nil), ("ambient", .ambientBlur(radius: 12)), ("glass", .frostedGlass(radius: 20)),
            ("color", .color(.blue)), ("view", .view { Text("Behind").accessibilityIdentifier("hdr.behind") }),
        ]
        for (name, background) in backgrounds {
            let s = makeState(path)
            let w = withOSPath(path) {
                window(ZTronScrollView(.vertical, state: s) { Color.gray.frame(height: 2000) }
                    .withScalingHeader(size: .fixed(min: 64, max: 240), background: background) { _ in Header() },
                       size: CGSize(width: 402, height: 874))
            }
            pump(0.2)
            let ids = accessibilityIdentifiers(in: w)
            #expect(ids.filter { $0 == "hdr.button" }.count == 1, "\(path) \(name): one header button (\(ids))")
            #expect(ids.filter { $0 == "hdr.title" }.count == 1, "\(path) \(name): one header title (\(ids))")
            #expect(!ids.contains("hdr.behind"), "\(path) \(name): the background view is hidden (\(ids))")
            unhost(w)
        }
    }

    /// Every accessibility element's identifier under `root` (UIKit's container API: `accessibilityElements`, else
    /// `accessibilityElementCount` / `accessibilityElement(at:)`, plus subviews; each object visited once).
    private func accessibilityIdentifiers(in root: NSObject) -> [String] {
        var out: [String] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ o: NSObject, _ depth: Int) {
            guard depth < 64, seen.insert(ObjectIdentifier(o)).inserted else { return }
            if o.isAccessibilityElement, let id = (o as? UIAccessibilityIdentification)?.accessibilityIdentifier,
               !id.isEmpty {
                out.append(id)
            }
            var children: [NSObject] = []
            if let els = o.accessibilityElements as? [NSObject] {
                children = els
            } else {
                let n = o.accessibilityElementCount()
                if n != NSNotFound, n > 0 { children = (0..<n).compactMap { o.accessibilityElement(at: $0) as? NSObject } }
            }
            if let v = o as? UIView { children += v.subviews }
            for c in children { visit(c, depth + 1) }
        }
        visit(root, 0)
        return out
    }
}
