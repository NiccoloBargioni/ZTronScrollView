import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// D75 (M8b-s8 s8, design M8b-s8-d75 §9.2): `withScalingHeader(…, fittingContent:)` and the content's animatable shape.
///
/// Ground truth: the drawn (presentation) frames of the header marker and of the content's first row, sampled every
/// display frame by a `CADisplayLink`. The rig hosts through `hostDriven` (an undriven hosted window stalls animated
/// insertions, open item 34). A 402 x 874 window, `.fixed(min: 64, max: 240)`, `.defaultScrollAnchor(.center, for:
/// .alignment)`, rows of 60 pt: 5 rows (300 pt) fit, 10 (600 pt) overflow the region below the resting header.
///
/// `.headerFollows` (M8b-s8 s9): the header rides on the content's top edge, lifted by `slack · a` (`HeaderLift.swift`):
/// its bottom edge is the content's top on every drawn frame (grow, shrink, the clamp, option changes, a pinch, a refresh
/// hold and a catch of its reset).
@MainActor
@Suite(.serialized)
struct HeaderFittingContentTests {
    static let headerMarker = (r: 0.13, g: 0.26, b: 0.39)
    static let contentMarker = (r: 0.47, g: 0.11, b: 0.23)
    static let indicatorMarker = (r: 0.91, g: 0.62, b: 0.05)
    static func color(_ m: (r: Double, g: Double, b: Double)) -> Color { Color(red: m.r, green: m.g, blue: m.b) }

    final class Rows: ObservableObject {
        @Published var n: Int
        init(_ n: Int) { self.n = n }
    }

    final class Option: ObservableObject {
        @Published var fitting: ZTronHeaderFittingContent
        init(_ f: ZTronHeaderFittingContent) { fitting = f }
    }

    /// Body runs of the content (S4).
    final class Bodies { var content = 0 }

    /// An app's bottom `.safeAreaInset` around the scroll view (the seam lab's `kbfake`), animated by the test.
    final class InsetBox: ObservableObject {
        @Published var height: CGFloat = 0
    }

    struct InsetWrap<Content: View>: View {
        @ObservedObject var box: InsetBox
        let content: Content
        var body: some View {
            content.safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: box.height) }
        }
    }

    struct RowStack: View {
        let n: Int
        let bodies: Bodies
        var body: some View {
            bodies.content += 1
            return VStack(spacing: 0) {
                ForEach(0..<n, id: \.self) { i in
                    (i == 0 ? HeaderFittingContentTests.color(HeaderFittingContentTests.contentMarker)
                        : i % 2 == 0 ? Color.green : Color.yellow).frame(height: 60)
                }
            }
        }
    }

    /// The content observing the model (an internal change: only this view re-runs).
    struct Inner: View {
        @ObservedObject var rows: Rows
        let bodies: Bodies
        var body: some View { RowStack(n: rows.n, bodies: bodies) }
    }

    struct Host: View {
        @ObservedObject var ext: Rows
        @ObservedObject var option: Option
        let inner: Rows?
        let state: ZTronScrollState
        let bodies: Bodies
        var hold = false
        var setup = Setup()

        var body: some View {
            let inner = inner, bodies = bodies, ext = ext.n
            var scroll = ZTronScrollView(.vertical, state: state) {
                if let inner { Inner(rows: inner, bodies: bodies) } else { RowStack(n: ext, bodies: bodies) }
            }
            if setup.zoomable { scroll = scroll.zoomRange(min: .absolute(1), max: .absolute(4)) }
            let view = scroll
            .defaultScrollAnchor(.center, for: .alignment)
            .withScalingHeader(size: .fixed(min: 64, max: 240), collapse: setup.collapse, pull: setup.behavior,
                               fittingContent: option.fitting, stretchContent: setup.stretchContent) { _ in
                HeaderFittingContentTests.color(HeaderFittingContentTests.headerMarker)
            }
            .scalingHeaderPullBehavior(setup.pull)
            return Group {
                if hold {
                    view.refresher(refreshView: { _ in
                        HeaderFittingContentTests.color(HeaderFittingContentTests.indicatorMarker).frame(width: 20, height: 20)
                    }, overlay: setup.overlay) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                    }
                } else {
                    view
                }
            }
        }
    }

    /// The s9 variations of the host (defaults: the s8 host).
    struct Setup {
        var zoomable = false
        var collapse: ZTronHeaderCollapseBehavior = .compress
        var pull: ZTronHeaderPullBehavior = .openGap
        var overlay = false
        /// Hosts the view in `InsetWrap` with this box.
        var inset: InsetBox? = nil
        /// M8b-s8 s10: `pull: .stretch` and its `stretchContent:` case.
        var behavior: ZTronHeaderScalingBehavior = .preserve
        var stretchContent: ZTronHeaderStretchContent = .keepTextMagnified
    }

    /// The drawn header bottom and content top every display frame.
    @MainActor final class Sampler: NSObject {
        struct S { var t: CFTimeInterval; var header: CGFloat?; var content: CGFloat?; var headerTop: CGFloat? = nil
                   var indicator: CGRect? = nil }
        var samples: [S] = []
        weak var window: UIWindow?
        private var link: CADisplayLink?
        func start(_ w: UIWindow) {
            window = w
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        @objc func tick(_ l: CADisplayLink?) {
            guard let w = window else { return }
            let h = HeaderFittingContentTests.frames(of: HeaderFittingContentTests.headerMarker, in: w).first
            samples.append(S(t: CACurrentMediaTime(), header: h?.maxY,
                             content: HeaderFittingContentTests.frames(of: HeaderFittingContentTests.contentMarker, in: w).first?.minY,
                             headerTop: h?.minY,
                             indicator: HeaderFittingContentTests.frames(of: HeaderFittingContentTests.indicatorMarker, in: w,
                                                                         clipped: true).first))
        }
        func stop() { link?.invalidate(); link = nil }
        func since(_ t: CFTimeInterval) -> [S] { samples.filter { $0.t >= t } }
    }

    /// The window frames of the layers filled with `marker`, as drawn now (the presentation tree); `clipped`: the part
    /// left visible by the ancestors that clip (`masksToBounds`; an empty rect when nothing of it is).
    static func frames(of marker: (r: Double, g: Double, b: Double), in window: UIWindow, clipped: Bool = false) -> [CGRect] {
        var out: [CGRect] = []
        let root = window.layer.presentation() ?? window.layer
        func visit(_ layer: CALayer, _ clip: CGRect) {
            var clip = clip
            if clipped, layer.masksToBounds { clip = clip.intersection(layer.convert(layer.bounds, to: root)) }
            if let c = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - marker.r) < 0.02, abs(g - marker.g) < 0.02, abs(b - marker.b) < 0.02 {
                    let f = layer.convert(layer.bounds, to: root)
                    out.append(clipped ? f.intersection(clip) : f)
                }
            }
            layer.sublayers?.forEach { visit($0, clip) }
        }
        visit(root, .infinite)
        return out
    }

    /// One drawn value's motion: drawn frames that moved it within 0.5 s of its first move, the largest single-frame step
    /// as a fraction of the change, start and end.
    struct Motion: CustomStringConvertible {
        var start: CGFloat = 0, end: CGFloat = 0, total: CGFloat = 0
        var moves = 0, movesIn500 = 0
        var maxStep: CGFloat = 0, maxStepFraction: CGFloat = 0
        var range: CGFloat = 0
        var description: String {
            String(format: "%.1f -> %.1f (change %.1f, range %.1f): %d moving frames, %d in 0.5 s, max step %.2f pt = %.3f",
                   start, end, total, range, moves, movesIn500, maxStep, maxStepFraction)
        }
    }

    static func motion(_ xs: [(t: CFTimeInterval, v: CGFloat)]) -> Motion {
        var m = Motion()
        guard let a = xs.first, let b = xs.last else { return m }
        m.start = a.v; m.end = b.v; m.total = abs(b.v - a.v)
        let vs = xs.map(\.v)
        m.range = (vs.max() ?? 0) - (vs.min() ?? 0)
        var first: CFTimeInterval?
        for (p, q) in zip(xs, xs.dropFirst()) where abs(q.v - p.v) > 0.01 {
            m.moves += 1
            if first == nil { first = q.t }
            if let f = first, q.t - f <= 0.5 { m.movesIn500 += 1 }
            m.maxStep = max(m.maxStep, abs(q.v - p.v))
        }
        m.maxStepFraction = m.total > 0.5 ? m.maxStep / m.total : 0
        return m
    }

    struct Rig {
        let state: ZTronScrollState
        let window: UIWindow
        let ext: Rows
        let inner: Rows?
        let option: Option
        let bodies: Bodies
        let sampler: Sampler
        var rows: Rows { inner ?? ext }
    }

    enum Change: String, CaseIterable, Sendable { case `internal`, external }

    func host(_ path: OSPath, _ fitting: ZTronHeaderFittingContent, rows: Int = 5, change: Change = .external,
              hold: Bool = false, setup: Setup = Setup()) -> Rig {
        let s = makeState(path), ext = Rows(rows), option = Option(fitting), bodies = Bodies()
        let inner: Rows? = change == .internal ? Rows(rows) : nil
        let w = withOSPath(path) {
            let h = Host(ext: ext, option: option, inner: inner, state: s, bodies: bodies, hold: hold, setup: setup)
            return setup.inset.map { hostDriven(InsetWrap(box: $0, content: h)) } ?? hostDriven(h)
        }
        var k = 0
        while s.peek.metrics.header == nil, k < 40 { pump(0.1); k += 1 }
        pump(0.3)
        let sampler = Sampler()
        sampler.start(w)
        pump(0.1)
        return Rig(state: s, window: w, ext: ext, inner: inner, option: option, bodies: bodies, sampler: sampler)
    }

    /// Lets the main queue run (the hosted tests run on it, so `pump()` never drains it): `PositionDriver`'s
    /// one-turn transaction capture ends there, so a later unanimated change is not adopted in an earlier animation.
    func drainMainQueue() async {
        for _ in 0..<10 { await Task.yield() }
    }

    /// The region below the resting header and the slack of `height` pt of content in it (vertical alignment 0.5).
    func pad(_ s: ZTronScrollState, contentHeight: CGFloat) -> CGFloat {
        let m = s.peek.metrics
        let region = m.viewportSize.height - m.adjustedContentInset.top - m.adjustedContentInset.bottom
        return max(0, region - contentHeight) * 0.5
    }

    func contentTops(_ xs: [Sampler.S]) -> [(t: CFTimeInterval, v: CGFloat)] { xs.compactMap { s in s.content.map { (s.t, $0) } } }
    func headerBottoms(_ xs: [Sampler.S]) -> [(t: CFTimeInterval, v: CGFloat)] { xs.compactMap { s in s.header.map { (s.t, $0) } } }

    // MARK: API and the published alignment

    @Test(arguments: OSPath.allCases)
    func theDefaultIsD63(path: OSPath) throws {
        let spec = try #require(ZTronScrollView { Color.clear }.withScalingHeader(size: .fixed(max: 200)) { _ in Color.red }
            .config.header)
        #expect(spec.fitting == .topAligned)
        let r = host(path, .topAligned)
        defer { r.sampler.stop(); unhost(r.window) }
        #expect(r.state.contentAlignment == UnitPoint(x: 0.5, y: 0), "\(path): D63 zeroes the vertical alignment only")
        #expect(r.state.peek.metrics.alignment == ContentAlignment(content: UnitPoint(x: 0.5, y: 0), liftY: 0))
        let s = r.sampler.samples.last
        let gap = (s?.content ?? -1) - (s?.header ?? 0)
        #expect(abs(gap) < 0.5, "\(path): the content starts at the header's bottom edge (gap \(gap))")
    }

    @Test(arguments: OSPath.allCases)
    func aPinnedHeaderLeavesTheAlignmentPadBelowIt(path: OSPath) {
        let r = host(path, .headerPinned)
        defer { r.sampler.stop(); unhost(r.window) }
        #expect(r.state.contentAlignment == .center)
        #expect(r.state.peek.metrics.alignment == ContentAlignment(content: .center, liftY: 0))
        let expected = pad(r.state, contentHeight: 300)
        let s = r.sampler.samples.last
        let gap = (s?.content ?? -1) - (s?.header ?? 0)
        #expect(expected > 50 && abs(gap - expected) < 0.5, "\(path): gap \(gap), slack · a \(expected)")
        // `.headerFollows` publishes its lift alignment (the lift itself is M8b-s8 s9).
        r.option.fitting = .headerFollows
        pump(0.3)
        #expect(r.state.peek.metrics.alignment == ContentAlignment(content: .center, liftY: 0.5))
    }

    // MARK: Content-size changes (the shape adopted in the change's transaction)

    @Test(arguments: OSPath.allCases, Change.allCases)
    func aPinnedHeadersContentGrowsAndShrinksOnTheChangesCurve(path: OSPath, change: Change) async {
        let r = host(path, .headerPinned, change: change)
        defer { r.sampler.stop(); unhost(r.window) }
        let tag = "\(path) \(change)"
        let pad5 = pad(r.state, contentHeight: 300)
        for (to, name) in [(10, "grow"), (5, "shrink")] {
            await drainMainQueue()
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = to }
            pump(0.8)
            let xs = r.sampler.since(t0)
            let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs))
            print("D75 \(tag) \(name): content \(c); header \(h)")
            #expect(abs(c.total - pad5) < 0.5, "\(tag) \(name): the content moved by slack · a (\(c.total) vs \(pad5))")
            #expect(c.movesIn500 >= 20 && c.maxStepFraction <= 0.25, "\(tag) \(name): content \(c)")
            #expect(h.range < 0.5, "\(tag) \(name): the header stays (\(h))")
        }
    }

    @Test(arguments: OSPath.allCases, Change.allCases)
    func aTopAlignedContentChangeMovesNeitherHeaderNorContent(path: OSPath, change: Change) async {
        let r = host(path, .topAligned, change: change)
        defer { r.sampler.stop(); unhost(r.window) }
        for to in [10, 5] {
            await drainMainQueue()
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = to }
            pump(0.8)
            let xs = r.sampler.since(t0)
            let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs))
            #expect(c.range < 0.5 && h.range < 0.5, "\(path) \(change) -> \(to): content \(c); header \(h)")
        }
    }

    @Test(arguments: OSPath.allCases)
    func aPlainChangeLandsInOneFrame(path: OSPath) async {
        let r = host(path, .headerPinned)
        defer { r.sampler.stop(); unhost(r.window) }
        let pad5 = pad(r.state, contentHeight: 300)
        for to in [10, 5] {
            await drainMainQueue()
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            r.rows.n = to
            pump(0.5)
            let c = Self.motion(contentTops(r.sampler.since(t0)))
            #expect(c.moves == 1 && abs(c.total - pad5) < 0.5, "\(path) -> \(to): unanimated, as native: \(c)")
        }
    }

    /// The default mode's clamp (62 pt in one frame before D75) and `.headerPinned`'s clamp + pad: content scrolled to
    /// its bottom, then 600 -> 300 pt animated.
    @Test(arguments: OSPath.allCases, [ZTronHeaderFittingContent.topAligned, .headerPinned])
    func aShrinkAtTheBottomClampsOnTheChangesCurve(path: OSPath, fitting: ZTronHeaderFittingContent) async {
        let r = host(path, fitting, rows: 10)
        defer { r.sampler.stop(); unhost(r.window) }
        let m = r.state.peek.metrics
        let maxY = m.contentSize.height - (m.viewportSize.height - m.adjustedContentInset.bottom)
        r.state.setContentOffset(CGPoint(x: 0, y: maxY), animated: false)
        pump(0.4)
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = 5 }
        pump(0.8)
        let xs = r.sampler.since(t0)
        let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs))
        let tag = "\(path) \(fitting) (offset \(maxY))"
        print("D75 \(tag) shrink at the bottom: content \(c); header \(h)")
        #expect(c.total > 30 && c.movesIn500 >= 20 && c.maxStepFraction <= 0.25, "\(tag): content \(c)")
        #expect(h.total > 30 && h.movesIn500 >= 20 && h.maxStepFraction <= 0.25, "\(tag): header \(h)")
        if fitting == .topAligned {
            let seams = xs.compactMap { s -> CGFloat? in
                guard let c = s.content, let h = s.header else { return nil }
                return c - h
            }
            #expect(seams.allSatisfy { abs($0) <= 1 }, "\(tag): seam \(seams.min() ?? 0)...\(seams.max() ?? 0)")
        }
        #expect(abs(r.state.peek.presentationOffset.y + r.state.adjustedContentInset.top) < 0.5, "\(tag): clamped")
    }

    // MARK: Option change at run time

    @Test(arguments: OSPath.allCases)
    func anAnimatedOptionChangeMovesTheContentOnly(path: OSPath) async {
        let r = host(path, .topAligned)
        defer { r.sampler.stop(); unhost(r.window) }
        let pad5 = pad(r.state, contentHeight: 300)
        for (to, name) in [(ZTronHeaderFittingContent.headerPinned, "top -> pinned"), (.topAligned, "pinned -> top")] {
            await drainMainQueue()
            #if DEBUG
            let builds = ZTronRenderCounters.value("header.builder")
            #endif
            let bodies = r.bodies.content
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            withAnimation(.easeInOut(duration: 0.5)) { r.option.fitting = to }
            pump(0.8)
            let xs = r.sampler.since(t0)
            let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs))
            print("D75 \(path) \(name): content \(c); header \(h)")
            #expect(abs(c.total - pad5) < 0.5 && c.movesIn500 >= 20 && c.maxStepFraction <= 0.25, "\(path) \(name): \(c)")
            #expect(h.range < 0.5, "\(path) \(name): the header stays (\(h))")
            #expect(r.bodies.content == bodies, "\(path) \(name): no content body (\(r.bodies.content - bodies))")
            #if DEBUG
            #expect(ZTronRenderCounters.value("header.builder") - builds <= 1,
                    "\(path) \(name): one header build at most (\(ZTronRenderCounters.value("header.builder") - builds))")
            #endif
        }
    }

    // MARK: R6: the shape's own attribute runs through unanimated per-frame writes

    /// Rows inserted while the clock draws a bounce (a pull released, unanimated offset writes every frame): the pad keeps
    /// its curve (in the transform's attribute, 27.0 would end it at the first clock frame).
    @Test(arguments: OSPath.allCases)
    func rowsInsertedDuringABounceKeepTheirCurve(path: OSPath) async {
        let r = host(path, .headerPinned)
        defer { r.sampler.stop(); unhost(r.window) }
        let s = r.state
        let c = withOSPath(path) { PanCoordinator(state: s, axes: .vertical) }
        let pad5 = pad(s, contentHeight: 300)
        let top = s.peek.presentationOffset
        s.beginTracking(); s.beginDragging()
        s.writeDragOffset(CGPoint(x: top.x, y: top.y - 80))
        // The finger's (unanimated) write is drawn first: it is a one-frame step of its own, not the pad's.
        let rest = r.sampler.samples.last?.content ?? 0
        var k = 0
        repeat { pump(0.05); await drainMainQueue(); k += 1 } while (r.sampler.samples.last?.content ?? 0) < rest + 79 && k < 40
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        s.endDrag(ReleaseRequest(origin: CGPoint(x: top.x, y: top.y - 80), dragStart: top, liftTime: s.now(), fallbackVelocity: .zero),
                  tracker: PointVelocityTracker(), env: c.peekEnvironment(), settings: ReleaseSettings())
        pump(0.05)
        #expect(s.isDecelerating, "\(path): the bounce runs")
        withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = 10 }
        pump(1.2)
        // From the frame that draws the pull at its deepest (the finger's write is a one-frame step of its own; on the
        // preferred path the hosted window may draw it only after the release, so the bounce is measured from its peak).
        let window = r.sampler.samples.indices.filter { r.sampler.samples[$0].t >= t0 - 2.5 && r.sampler.samples[$0].content != nil }
        let drawnPull = window.max { (r.sampler.samples[$0].content ?? 0) < (r.sampler.samples[$1].content ?? 0) } ?? 0
        let m = Self.motion(contentTops(Array(r.sampler.samples[drawnPull...])))
        print("D75 \(path) rows during a bounce: content \(m) (pad change \(pad5); waited \(k) pumps for the pull)")
        #expect(m.maxStep < 0.5 * pad5, "\(path): no step >= 0.5 of the pad change (\(m))")
        #expect(abs(s.peek.presentationOffset.y - top.y) < 0.5, "\(path): back at rest")
    }

    /// Rows inserted while a refresh hold retracts (clock-driven inset writes every frame).
    @Test(arguments: OSPath.allCases)
    func rowsInsertedDuringAHoldReleaseKeepTheirCurve(path: OSPath) async {
        let r = host(path, .headerPinned, hold: true)
        defer { r.sampler.stop(); unhost(r.window) }
        let s = r.state
        s.beginRefreshing()
        pump(1.0)
        let pad5 = pad(s, contentHeight: 300)
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        s.endRefreshing()
        pump(0.05)
        withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = 10 }
        pump(1.2)
        let m = Self.motion(contentTops(r.sampler.since(t0)))
        print("D75 \(path) rows during a hold release: content \(m) (pad change \(pad5))")
        #expect(pad5 > 50 && m.maxStep < 0.5 * pad5, "\(path): no step >= 0.5 of the pad change (\(m))")
    }

    /// A touch during a content-size animation (C10: the shape is not pinned): the pad keeps its curve through the
    /// touch-down and its lift, and a catch of the animated clamp (D79) holds the content where it is drawn.
    @Test(arguments: OSPath.allCases)
    func aTouchDuringAContentSizeAnimationKeepsTheCurve(path: OSPath) async {
        let r = host(path, .headerPinned)
        defer { r.sampler.stop(); unhost(r.window) }
        let s = r.state
        let pad5 = pad(s, contentHeight: 300)
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = 10 }
        pump(0.15)
        s.interrupt(catching: true)
        s.beginTracking()
        pump(0.15)
        s.endTracking()
        pump(0.6)
        let m = Self.motion(contentTops(r.sampler.since(t0)))
        print("D75 \(path) touch during the change: content \(m) (pad change \(pad5))")
        #expect(abs(m.total - pad5) < 0.5 && m.maxStepFraction <= 0.25, "\(path): \(m)")

        // The clamp (content at its bottom, shrinking): a catch holds the drawn offset; the pad goes on.
        r.rows.n = 10
        pump(0.4)
        let mm = s.peek.metrics
        let maxY = mm.contentSize.height - (mm.viewportSize.height - mm.adjustedContentInset.bottom)
        s.setContentOffset(CGPoint(x: 0, y: maxY), animated: false)
        pump(0.4)
        await drainMainQueue()
        let t1 = CACurrentMediaTime()
        r.sampler.tick(nil)
        withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = 5 }
        pump(0.2)
        s.interrupt(catching: true)
        s.beginTracking()
        let caught = s.peek.presentationOffset.y
        pump(0.6)
        let k = Self.motion(contentTops(r.sampler.since(t1)))
        print("D75 \(path) catch of the clamp at \(caught) (from \(maxY)): content \(k)")
        #expect(k.maxStepFraction < 0.5, "\(path): no jump at the catch (\(k))")
        #expect(abs(s.peek.presentationOffset.y - caught) < 0.5, "\(path): held under the finger")
        s.endTracking()
    }

    // MARK: `.headerFollows`: the lift (M8b-s8 s9)

    /// The header-content seams of the frames that drew both (content top − header bottom).
    func seams(_ xs: [Sampler.S]) -> [CGFloat] {
        xs.compactMap { s in
            guard let c = s.content, let h = s.header else { return nil }
            return c - h
        }
    }

    func seamText(_ xs: [CGFloat]) -> String { String(format: "seam %.2f...%.2f over %d frames", xs.min() ?? 0, xs.max() ?? 0, xs.count) }

    /// The forced lane's (15–16 path) and the preferred path's lift at rest: `slack · a`, the header's bottom edge the
    /// content's top; overflowing content: no lift; the geometry and `obscuredDelta` report it.
    @Test(arguments: OSPath.allCases)
    func aFollowingHeaderRidesOnFittingContentAtRest(path: OSPath) {
        let r = host(path, .headerFollows)
        defer { r.sampler.stop(); unhost(r.window) }
        let expected = pad(r.state, contentHeight: 300)
        let m = r.state.peek.metrics
        let restingBottom = HeaderMath.top0(m) + (m.header?.resting ?? 0)
        let s = r.sampler.samples.last
        let seam = (s?.content ?? -1) - (s?.header ?? 0)
        let lift = (s?.header ?? 0) - restingBottom
        #expect(expected > 50 && abs(lift - expected) < 0.5, "\(path): lift at rest \(lift) = slack · a \(expected)")
        #expect(abs(seam) < 0.5, "\(path): header bottom = content top (seam \(seam))")
        #expect(abs(HeaderMath.lift(zoom: 1, metrics: m) - expected) < 0.5)
        #expect(abs((r.state.geometry.header?.lift ?? 0) - expected) < 0.5, "\(path): the reader reports the lift")
        r.rows.n = 10
        pump(0.4)
        let t = r.sampler.samples.last
        #expect(abs((t?.header ?? 0) - restingBottom) < 0.5, "\(path): overflowing content: no lift")
        #expect(abs((t?.content ?? -1) - (t?.header ?? 0)) < 0.5)
    }

    @Test(arguments: OSPath.allCases, Change.allCases)
    func aFollowingHeaderGrowsAndShrinksWithItsContent(path: OSPath, change: Change) async {
        let r = host(path, .headerFollows, change: change)
        defer { r.sampler.stop(); unhost(r.window) }
        let tag = "\(path) \(change)"
        let pad5 = pad(r.state, contentHeight: 300)
        for (to, name) in [(10, "grow"), (5, "shrink")] {
            await drainMainQueue()
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = to }
            pump(0.8)
            let xs = r.sampler.since(t0)
            let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs)), sm = seams(xs)
            print("D75 follows \(tag) \(name): content \(c); header \(h); \(seamText(sm))")
            #expect(abs(c.total - pad5) < 0.5 && c.movesIn500 >= 20 && c.maxStepFraction <= 0.25, "\(tag) \(name): content \(c)")
            #expect(abs(h.total - pad5) < 0.5 && h.movesIn500 >= 20, "\(tag) \(name): the header moves with it (\(h))")
            #expect(!sm.isEmpty && sm.allSatisfy { abs($0) <= 1 }, "\(tag) \(name): \(seamText(sm))")
        }
    }

    @Test(arguments: OSPath.allCases)
    func aShrinkAtTheBottomKeepsTheFollowingHeaderOnTheContent(path: OSPath) async {
        let r = host(path, .headerFollows, rows: 10)
        defer { r.sampler.stop(); unhost(r.window) }
        let m = r.state.peek.metrics
        let maxY = m.contentSize.height - (m.viewportSize.height - m.adjustedContentInset.bottom)
        r.state.setContentOffset(CGPoint(x: 0, y: maxY), animated: false)
        pump(0.4)
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = 5 }
        pump(0.8)
        let xs = r.sampler.since(t0)
        let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs)), sm = seams(xs)
        print("D75 follows \(path) shrink at the bottom: content \(c); header \(h); \(seamText(sm))")
        #expect(c.total > 30 && c.movesIn500 >= 20 && c.maxStepFraction <= 0.25, "\(path): content \(c)")
        #expect(sm.allSatisfy { abs($0) <= 1 }, "\(path): \(seamText(sm))")
    }

    /// `top → follows` (both move together), `follows → pinned` (the header slides up, the content stays), `pinned →
    /// follows` (back), `follows → top` (both).
    @Test(arguments: OSPath.allCases)
    func optionChangesIntoAndOutOfFollowsAnimate(path: OSPath) async {
        let r = host(path, .topAligned)
        defer { r.sampler.stop(); unhost(r.window) }
        let pad5 = pad(r.state, contentHeight: 300)
        let steps: [(ZTronHeaderFittingContent, String, contentMoves: Bool, headerMoves: Bool, seam: Bool)] = [
            (.headerFollows, "top -> follows", true, true, true), (.headerPinned, "follows -> pinned", false, true, false),
            (.headerFollows, "pinned -> follows", false, true, false), (.topAligned, "follows -> top", true, true, true),
        ]
        for (to, name, contentMoves, headerMoves, seam) in steps {
            await drainMainQueue()
            let bodies = r.bodies.content
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            withAnimation(.easeInOut(duration: 0.5)) { r.option.fitting = to }
            pump(0.8)
            let xs = r.sampler.since(t0)
            let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs)), sm = seams(xs)
            print("D75 \(path) \(name): content \(c); header \(h); \(seamText(sm))")
            if contentMoves {
                #expect(abs(c.total - pad5) < 0.5 && c.movesIn500 >= 20 && c.maxStepFraction <= 0.25, "\(path) \(name): \(c)")
            } else {
                #expect(c.range < 0.5, "\(path) \(name): the content stays (\(c))")
            }
            if headerMoves {
                #expect(abs(h.total - pad5) < 0.5 && h.movesIn500 >= 20 && h.maxStepFraction <= 0.25, "\(path) \(name): \(h)")
            }
            if seam { #expect(sm.allSatisfy { abs($0) <= 1 }, "\(path) \(name): \(seamText(sm))") }
            #expect(r.bodies.content == bodies, "\(path) \(name): no content body")
        }
    }

    /// A pinch on a zoomable view (the slack shrinks with `c · s`): unanimated zoom writes every frame, then an animated
    /// zoom back; the header keeps riding on the content.
    @Test(arguments: OSPath.allCases)
    func aPinchOnAZoomableFollowingViewKeepsTheSeam(path: OSPath) async {
        var setup = Setup()
        setup.zoomable = true
        let r = host(path, .headerFollows, setup: setup)
        defer { r.sampler.stop(); unhost(r.window) }
        let s = r.state
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        var z: CGFloat = 1
        while z < 1.5 {
            z += 0.02
            s.setZoomScale(z, animated: false)
            pump(1.0 / 60)
        }
        pump(0.3)
        let pinch = r.sampler.since(t0)
        let h1 = Self.motion(headerBottoms(pinch)), sm1 = seams(pinch)
        print("D75 \(path) pinch: header \(h1); \(seamText(sm1))")
        #expect(h1.total > 40, "\(path): the lift follows the zoom (\(h1))")
        #expect(sm1.allSatisfy { abs($0) <= 1 }, "\(path) pinch: \(seamText(sm1))")
        let t1 = CACurrentMediaTime()
        r.sampler.tick(nil)
        s.setZoomScale(1, animated: true)
        pump(0.8)
        let back = r.sampler.since(t1)
        let h2 = Self.motion(headerBottoms(back)), sm2 = seams(back)
        print("D75 \(path) animated zoom back: header \(h2); \(seamText(sm2))")
        #expect(h2.total > 40 && h2.maxStepFraction < 0.5, "\(path): \(h2)")
        #expect(sm2.allSatisfy { abs($0) <= 1 }, "\(path) zoom back: \(seamText(sm2))")
    }

    /// A refresh hold in `.headerFollows`: the indicator's base is the drawn (lifted) header, never over the content
    /// (`.openGap`: between the header's bottom and the content's top; `.followContent`: above the header), both collapse
    /// modes, from the hold's begin through its end (the slack narrows by the hold until D71: content and header alike).
    enum HoldCase: String, CaseIterable, Sendable { case openGap, followContent, openGapSlide, followContentSlide }

    @Test(arguments: OSPath.allCases, HoldCase.allCases)
    func aHoldInFollowsKeepsTheIndicatorAtTheLiftedHeader(path: OSPath, hold: HoldCase) async {
        let pull: ZTronHeaderPullBehavior = hold == .openGap || hold == .openGapSlide ? .openGap : .followContent
        let slide = hold == .openGapSlide || hold == .followContentSlide
        var setup = Setup()
        setup.pull = pull
        setup.collapse = slide ? .slideBehind : .compress
        let r = host(path, .headerFollows, hold: true, setup: setup)
        defer { r.sampler.stop(); unhost(r.window) }
        let s = r.state
        let tag = "\(path) \(pull) \(slide ? "slideBehind" : "compress")"
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        s.beginRefreshing()
        pump(1.2)
        let held = r.sampler.samples.last
        s.endRefreshing()
        pump(1.2)
        let xs = r.sampler.since(t0)
        var over = 0, offBase = 0, frames = 0
        var worstOver: CGFloat = 0, worstBase: CGFloat = 0
        for x in xs {
            guard let i = x.indicator, !i.isNull, i.height > 0.5, let c = x.content, let hb = x.header, let ht = x.headerTop else { continue }
            frames += 1
            if i.maxY > c + 0.5 { over += 1; worstOver = max(worstOver, i.maxY - c) }
            switch pull {
            case .openGap:
                if i.minY < hb - 0.5 { offBase += 1; worstBase = max(worstBase, hb - i.minY) }
            case .followContent:
                if i.maxY > ht + 0.5 { offBase += 1; worstBase = max(worstBase, i.maxY - ht) }
            }
        }
        if let h = held {
            print(String(format: "D75 %@ held: indicator %.1f...%.1f, header %.1f...%.1f, content %.1f, lift %.1f", tag,
                         h.indicator?.minY ?? -1, h.indicator?.maxY ?? -1, h.headerTop ?? -1, h.header ?? -1, h.content ?? -1,
                         HeaderMath.lift(zoom: 1, metrics: s.peek.metrics)))
        }
        print("D75 \(tag) hold: \(frames) indicator frames, \(over) over the content (\(worstOver)), \(offBase) off the header's edge (\(worstBase)); \(seamText(seams(xs)))")
        #expect(held?.indicator != nil, "\(tag): the indicator is drawn while held")
        #expect(frames > 10 && over == 0 && offBase == 0, "\(tag)")
        if pull == .openGap, let i = held?.indicator, let hb = held?.header, let c = held?.content {
            #expect(abs((i.midY) - (hb + c) / 2) < 0.75, "\(tag): centred in the gap below the lifted header")
        }
    }

    /// D79 / C10: a catch during the hold's reset (an inset animation the library draws): the lift takes the content's
    /// pinned transform vector, so no `Δslack · a` seam opens at the catch.
    @Test(arguments: OSPath.allCases)
    func aCatchDuringTheHoldsResetKeepsTheFollowingSeam(path: OSPath) async {
        var setup = Setup()
        setup.pull = .followContent   // the header rides on the content through the hold (the seam is 0 throughout)
        let r = host(path, .headerFollows, hold: true, setup: setup)
        defer { r.sampler.stop(); unhost(r.window) }
        let s = r.state
        s.beginRefreshing()
        pump(1.2)
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        s.endRefreshing()
        pump(0.12)
        s.interrupt(catching: true)
        s.beginTracking()
        pump(0.5)
        s.endTracking()
        pump(0.8)
        let xs = r.sampler.since(t0), sm = seams(xs)
        let c = Self.motion(contentTops(xs))
        print("D75 \(path) catch during the hold's reset: content \(c); \(seamText(sm))")
        #expect(!sm.isEmpty && sm.allSatisfy { abs($0) <= 1 }, "\(path): \(seamText(sm))")
    }

    // MARK: Safe-area changes at a fixed viewport (M8b-s8 s9: R2's lift reconstruction, K2)

    /// An app-animated bottom `.safeAreaInset` (150 pt, the seam lab's `kbfake`): fitting centred content moves `150 · a`
    /// on the app's curve (measured before: 75 pt in one frame) and a following header rides on it every frame (before:
    /// the lift animated from the slot while the content jumped, 75 pt overlap); top-aligned content and its header stay.
    @Test(arguments: OSPath.allCases, [ZTronHeaderFittingContent.headerFollows, .topAligned])
    func anAppAnimatedSafeAreaInsetMovesFittingContentOnItsCurve(path: OSPath, fitting: ZTronHeaderFittingContent) async {
        var setup = Setup()
        let box = InsetBox()
        setup.inset = box
        let r = host(path, fitting, setup: setup)
        defer { r.sampler.stop(); unhost(r.window) }
        let tag = "\(path) \(fitting)"
        for (to, name) in [(CGFloat(150), "up"), (0, "down")] {
            await drainMainQueue()
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            withAnimation(.easeInOut(duration: 0.6)) { box.height = to }
            pump(1.0)
            let xs = r.sampler.since(t0)
            let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs)), sm = seams(xs)
            print("D75 inset \(tag) \(name): content \(c); header \(h); \(seamText(sm))")
            if fitting == .headerFollows {
                #expect(abs(c.total - 75) < 1 && c.movesIn500 >= 15 && c.maxStepFraction <= 0.25, "\(tag) \(name): content \(c)")
                #expect(!sm.isEmpty && sm.allSatisfy { abs($0) <= 1 }, "\(tag) \(name): \(seamText(sm))")
            } else {
                #expect(c.range < 0.5 && h.range < 0.5, "\(tag) \(name): nothing moves (content \(c); header \(h))")
            }
        }
    }

    /// K2: a keyboard-hide report (no transaction in the turn, as the real keyboard's: D64) that moves fitting centred
    /// content moves it in `KeyboardInsetFollow`'s curve over many frames (measured before: one frame), the following
    /// header on it; a show report is written as it comes (the real one lands inside UIKit's keyboard animation, which
    /// Core Animation interpolates: seam lab `kbreal`), the header on the content in that frame too; top-aligned content:
    /// no motion. Hosted tests cannot show a keyboard: the state gets the container's report. Two rows (120 pt): the
    /// content still fits with the keyboard up, so it moves `336 · a`.
    @Test(arguments: OSPath.allCases, [ZTronHeaderFittingContent.headerFollows, .topAligned])
    func aKeyboardMovesFittingContentInTheKeyboardsCurve(path: OSPath, fitting: ZTronHeaderFittingContent) async {
        let r = host(path, fitting, rows: 2)
        defer { r.sampler.stop(); unhost(r.window) }
        let tag = "\(path) \(fitting)"
        let m0 = r.state.peek.metrics
        let kb: CGFloat = 336
        for (k, name) in [(kb, "up"), (0, "down")] {
            await drainMainQueue()
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            var safe = m0.safeAreaInsets
            safe.bottom += k
            r.state.setViewport(ViewportMetrics(size: m0.viewportSize, safeArea: safe, keyboard: k))
            pump(1.0)
            let xs = r.sampler.since(t0)
            let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs)), sm = seams(xs)
            print("D75 K2 \(tag) \(name): content \(c); header \(h); \(seamText(sm))")
            if fitting == .headerFollows {
                #expect(abs(c.total - kb / 2) < 1, "\(tag) \(name): content \(c)")
                if k == 0 {
                    #expect(c.movesIn500 >= 15 && c.maxStepFraction <= 0.25, "\(tag) \(name): content \(c)")
                }
                #expect(!sm.isEmpty && sm.allSatisfy { abs($0) <= 1 }, "\(tag) \(name): \(seamText(sm))")
            } else {
                #expect(c.range < 0.5 && h.range < 0.5, "\(tag) \(name): nothing moves (content \(c); header \(h))")
            }
        }
    }
    // MARK: `.stretch` takes the lift (M8b-s8 s10, design M8b-s8-d75 §2.2 item 5 on D76)

    static func stretchSetup(_ content: ZTronHeaderStretchContent) -> Setup {
        var setup = Setup()
        setup.behavior = .stretch
        setup.stretchContent = content
        return setup
    }

    /// The header marker's layer: its unscaled layout height (`bounds`) and its drawn frame. `.keepTextSize` lays the
    /// stack out grown (drawn = laid out: crisp), `.keepTextMagnified` scales a stack laid out at `R` (D69).
    static func headerLayer(in window: UIWindow) -> (layout: CGFloat, drawn: CGRect)? {
        let root = window.layer.presentation() ?? window.layer
        var out: (CGFloat, CGRect)?
        func visit(_ layer: CALayer) {
            if out == nil, let c = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                let m = headerMarker
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - m.r) < 0.02, abs(g - m.g) < 0.02, abs(b - m.b) < 0.02 {
                    out = (layer.bounds.height, layer.convert(layer.bounds, to: root))
                }
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root)
        return out
    }

    /// At rest on content that fits, a `.headerFollows` `.stretch` header grows by the lift instead of riding down on it:
    /// top edge at its resting top, height `R + L`, bottom edge the content's top; `.keepTextSize` lays it out at that
    /// height (crisp), `.keepTextMagnified` scales its resting layout by `(R + L) / R` (D69, C13); the reader reports the
    /// growth as stretch. Overflowing content: no growth. Then a pull adds `g`, and the compression starts only once the
    /// content has moved up by `L` (a rubber band of the fitting content).
    @Test(arguments: OSPath.allCases, [ZTronHeaderStretchContent.keepTextMagnified, .keepTextSize])
    func aStretchingHeaderGrowsByTheLiftAndCompressesAfterIt(path: OSPath, content: ZTronHeaderStretchContent) async {
        let r = host(path, .headerFollows, setup: Self.stretchSetup(content))
        defer { r.sampler.stop(); unhost(r.window) }
        let tag = "\(path) \(content)"
        let s = r.state
        let m = s.peek.metrics
        let R = m.header?.resting ?? 0
        let top0 = HeaderMath.top0(m)
        let L = pad(s, contentHeight: 300)
        func check(_ name: String, height: CGFloat, compressed: Bool = false) {
            pump(0.3)
            let x = r.sampler.samples.last
            let hb = x?.header ?? -1, ht = x?.headerTop ?? -1, c = x?.content ?? -2
            let layer = Self.headerLayer(in: r.window)
            print(String(format: "D75 stretch %@ %@: top %.2f (rest %.2f), bottom %.2f, content %.2f, height %.2f (expected %.2f), layout %.2f",
                         tag, name, ht, top0, hb, c, hb - ht, height, layer?.layout ?? -1))
            #expect(abs(ht - top0) < 0.5, "\(tag) \(name): the top edge stays at rest (\(ht) vs \(top0))")
            #expect(abs((hb - ht) - height) < 0.5, "\(tag) \(name): height \(hb - ht), expected \(height)")
            #expect(abs(c - hb) < 0.5, "\(tag) \(name): header bottom = content top (seam \(c - hb))")
            if let layer, !compressed {
                if content == .keepTextSize {
                    #expect(abs(layer.layout - height) < 0.5, "\(tag) \(name): laid out grown, unscaled (\(layer.layout))")
                } else {
                    #expect(abs(layer.layout - R) < 0.5, "\(tag) \(name): laid out at R and magnified (\(layer.layout))")
                }
            }
        }
        #expect(L > 50, "\(tag): the content fits (\(L))")
        check("rest", height: R + L)
        let g = s.geometry.header
        #expect(abs((g?.stretch ?? 0) - L) < 0.5 && (g?.lift ?? -1) == 0 && abs((g?.height ?? 0) - (R + L)) < 0.5,
                "\(tag): the reader reports the growth as stretch (\(String(describing: g)))")
        #expect(abs(HeaderMath.obscuredDelta(offset: s.peek.targetOffset, zoom: 1, metrics: m) - L) < 0.5,
                "\(tag): the unobscured top is the grown header's bottom")
        let top = s.peek.presentationOffset
        s.beginTracking(); s.beginDragging()
        // Two writes: the hosted window sometimes draws neither layer for the first drag write from rest (the content or
        // the header stays at rest 0.3 s on 27.0's preferred path, both cases, also before the lift was grown); a finger
        // writes every frame.
        s.writeDragOffset(CGPoint(x: top.x, y: top.y - 79))
        pump(0.05)
        s.writeDragOffset(CGPoint(x: top.x, y: top.y - 80))
        check("pulled 80", height: R + L + 80)
        s.writeDragOffset(CGPoint(x: top.x, y: top.y + L / 2))
        check("up L/2", height: R + L / 2)
        s.writeDragOffset(CGPoint(x: top.x, y: top.y + L + 40))
        check("up L + 40", height: R - 40, compressed: true)
        s.writeDragOffset(top)
        check("back", height: R + L)
        s.endTracking()
        pump(0.5)
        r.rows.n = 10
        check("overflowing", height: R)
    }

    /// Rows inserted and removed, animated (5 → 10 → 5: across the fit / overflow kink, where a layout-interpolated lift
    /// was 25 pt off): the grown header's top edge stays, its bottom edge is the content's top every drawn frame, and it
    /// moves on the change's curve; no content body runs but the rows' own.
    @Test(arguments: OSPath.allCases, [ZTronHeaderStretchContent.keepTextMagnified, .keepTextSize])
    func aStretchingHeaderFollowsRowChangesAcrossTheKink(path: OSPath, content: ZTronHeaderStretchContent) async {
        for change in Change.allCases {
        let r = host(path, .headerFollows, change: change, setup: Self.stretchSetup(content))
        defer { r.sampler.stop(); unhost(r.window) }
        let tag = "\(path) \(content) \(change)"
        let pad5 = pad(r.state, contentHeight: 300)
        for (to, name) in [(10, "grow"), (5, "shrink")] {
            await drainMainQueue()
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = to }
            pump(0.8)
            let xs = r.sampler.since(t0)
            let tops = xs.compactMap { x in x.headerTop.map { (x.t, $0) } }
            let c = Self.motion(contentTops(xs)), h = Self.motion(headerBottoms(xs)), t = Self.motion(tops), sm = seams(xs)
            print("D75 stretch rows \(tag) \(name): content \(c); header \(h); top \(t); \(seamText(sm))")
            #expect(abs(h.total - pad5) < 0.5 && h.movesIn500 >= 20 && h.maxStepFraction <= 0.25, "\(tag) \(name): header \(h)")
            #expect(t.range < 0.5, "\(tag) \(name): the top edge stays (\(t))")
            #expect(!sm.isEmpty && sm.allSatisfy { abs($0) <= 1 }, "\(tag) \(name): \(seamText(sm))")
        }
        }
    }

    /// Rows inserted while a refresh hold retracts (clock-driven writes of `o′` every frame, the common case): the lift's
    /// carriers keep the rows' curve (they do not share the consumers' attribute), the seam stays and the indicator is
    /// never drawn over the content.
    /// `follow`: the s9 baseline (`.preserve` `.followContent`, the lifted header without a stretch).
    enum HoldRows: String, CaseIterable, Sendable { case magnified, size, follow }

    @Test(arguments: OSPath.allCases, HoldRows.allCases)
    func aStretchingHeaderKeepsRowsCurveDuringAHoldRelease(path: OSPath, rows: HoldRows) async {
        var setup = Self.stretchSetup(rows == .size ? .keepTextSize : .keepTextMagnified)
        if rows == .follow { setup.behavior = .preserve; setup.pull = .followContent }
        let content = rows
        let r = host(path, .headerFollows, hold: true, setup: setup)
        defer { r.sampler.stop(); unhost(r.window) }
        let tag = "\(path) \(content)"
        let s = r.state
        await drainMainQueue()
        let t0 = CACurrentMediaTime()
        r.sampler.tick(nil)
        s.beginRefreshing()
        pump(1.2)
        let pad5 = pad(s, contentHeight: 300)
        s.endRefreshing()
        pump(0.05)
        withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = 10 }
        pump(1.2)
        let xs = r.sampler.since(t0)
        var over = 0
        for x in xs {
            if let i = x.indicator, !i.isNull, i.height > 0.5, let c = x.content, i.maxY > c + 0.5 { over += 1 }
        }
        let tops = xs.compactMap { x in x.headerTop.map { (x.t, $0) } }
        let h = Self.motion(headerBottoms(xs)), t = Self.motion(tops), sm = seams(xs)
        print("D75 stretch hold release + rows \(tag): header \(h); top \(t); over \(over); \(seamText(sm)) (pad \(pad5))")
        #expect(over == 0, "\(tag): the indicator is never over the content")
        // `.preserve` `.followContent` rides down on the lift (its top moves); a stretching header's top edge stays.
        if rows != .follow { #expect(t.range < 0.5, "\(tag): the top edge stays (\(t))") }
        #expect(!sm.isEmpty && sm.allSatisfy { abs($0) <= 1 }, "\(tag): \(seamText(sm))")
        #expect(h.maxStep < 0.5 * max(pad5, 1), "\(tag): no step >= 0.5 of the change (\(h))")
    }

    /// An animated option change into and out of `.headerFollows` with `.stretch`: the header grows by `L` from its top
    /// edge (which stays) as the content moves down, on the change's curve, seam ≤ 1 pt every frame.
    @Test(arguments: OSPath.allCases, [ZTronHeaderStretchContent.keepTextMagnified, .keepTextSize])
    func aStretchingHeaderGrowsWithAnAnimatedOptionChange(path: OSPath, content: ZTronHeaderStretchContent) async {
        let r = host(path, .topAligned, setup: Self.stretchSetup(content))
        defer { r.sampler.stop(); unhost(r.window) }
        let tag = "\(path) \(content)"
        let pad5 = pad(r.state, contentHeight: 300)
        for (to, name) in [(ZTronHeaderFittingContent.headerFollows, "top -> follows"), (.headerPinned, "follows -> pinned"),
                           (.headerFollows, "pinned -> follows"), (.topAligned, "follows -> top")] {
            await drainMainQueue()
            let t0 = CACurrentMediaTime()
            r.sampler.tick(nil)
            withAnimation(.easeInOut(duration: 0.5)) { r.option.fitting = to }
            pump(0.8)
            let xs = r.sampler.since(t0)
            let tops = xs.compactMap { x in x.headerTop.map { (x.t, $0) } }
            let h = Self.motion(headerBottoms(xs)), t = Self.motion(tops), sm = seams(xs)
            print("D75 stretch option \(tag) \(name): header \(h); top \(t); \(seamText(sm))")
            #expect(abs(h.total - pad5) < 0.5 && h.movesIn500 >= 20 && h.maxStepFraction <= 0.25, "\(tag) \(name): header \(h)")
            #expect(t.range < 0.5, "\(tag) \(name): the top edge stays (\(t))")
            if !name.contains("pinned") { #expect(sm.allSatisfy { abs($0) <= 1 }, "\(tag) \(name): \(seamText(sm))") }
        }
    }
}
