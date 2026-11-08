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
/// `.headerFollows` draws as `.headerPinned` until its lift is built (M8b-s8 s9); this suite covers `.topAligned` and
/// `.headerPinned`.
@MainActor
@Suite(.serialized)
struct HeaderFittingContentTests {
    static let headerMarker = (r: 0.13, g: 0.26, b: 0.39)
    static let contentMarker = (r: 0.47, g: 0.11, b: 0.23)
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

        var body: some View {
            let inner = inner, bodies = bodies, ext = ext.n
            let view = ZTronScrollView(.vertical, state: state) {
                if let inner { Inner(rows: inner, bodies: bodies) } else { RowStack(n: ext, bodies: bodies) }
            }
            .defaultScrollAnchor(.center, for: .alignment)
            .withScalingHeader(size: .fixed(min: 64, max: 240), fittingContent: option.fitting) { _ in
                HeaderFittingContentTests.color(HeaderFittingContentTests.headerMarker)
            }
            return Group {
                if hold {
                    view.refresher(refreshView: { _ in Color.clear.frame(width: 20, height: 20) }) {
                        try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                    }
                } else {
                    view
                }
            }
        }
    }

    /// The drawn header bottom and content top every display frame.
    @MainActor final class Sampler: NSObject {
        struct S { var t: CFTimeInterval; var header: CGFloat?; var content: CGFloat? }
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
            samples.append(S(t: CACurrentMediaTime(),
                             header: HeaderFittingContentTests.frames(of: HeaderFittingContentTests.headerMarker, in: w).first?.maxY,
                             content: HeaderFittingContentTests.frames(of: HeaderFittingContentTests.contentMarker, in: w).first?.minY))
        }
        func stop() { link?.invalidate(); link = nil }
        func since(_ t: CFTimeInterval) -> [S] { samples.filter { $0.t >= t } }
    }

    /// The window frames of the layers filled with `marker`, as drawn now (the presentation tree).
    static func frames(of marker: (r: Double, g: Double, b: Double), in window: UIWindow) -> [CGRect] {
        var out: [CGRect] = []
        let root = window.layer.presentation() ?? window.layer
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
              hold: Bool = false) -> Rig {
        let s = makeState(path), ext = Rows(rows), option = Option(fitting), bodies = Bodies()
        let inner: Rows? = change == .internal ? Rows(rows) : nil
        let w = withOSPath(path) {
            hostDriven(Host(ext: ext, option: option, inner: inner, state: s, bodies: bodies, hold: hold))
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
        // From the first frame that draws the pull (the finger's write is a one-frame step of its own).
        let drawnPull = r.sampler.samples.firstIndex { $0.t >= t0 - 2.5 && ($0.content ?? 0) >= rest + 79 } ?? 0
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
}
