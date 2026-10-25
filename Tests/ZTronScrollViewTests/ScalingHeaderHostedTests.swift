import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Body counts of the header's children (each test owns one; the render counters are global).
@MainActor
final class HeaderCounts {
    var runs: [String: Int] = [:]
    var ids = Set<UUID>()
    var labels: [String] = []
    func hit(_ key: String) { runs[key, default: 0] += 1 }
    func n(_ key: String) -> Int { runs[key] ?? 0 }
}

/// (b) a child without a reader that holds `@State`.
struct StaticHeaderChild: View {
    let counts: HeaderCounts
    var label = ""
    @State private var id = UUID()
    var body: some View {
        counts.hit("b")
        counts.ids.insert(id)
        counts.labels.append(label)
        return Color.blue.frame(height: 20)
    }
}

/// (c)–(f): readers with the identity form, a rounded height, `quantizedProgress(steps: 10)` and the resting height.
struct HeaderReaderChildren: View {
    let header: ZTronHeaderProxy
    let counts: HeaderCounts
    var body: some View {
        VStack(spacing: 0) {
            ZTronHeaderGeometryReader(header) { _ in
                let _ = counts.hit("c")
                Color.clear.frame(width: 1, height: 1)
            }
            ZTronHeaderGeometryReader(header, of: { $0.height.rounded() }) { _ in
                let _ = counts.hit("d")
                Color.clear.frame(width: 1, height: 1)
            }
            ZTronHeaderGeometryReader(header, of: ZTronHeaderGeometry.quantizedProgress(steps: 10)) { _ in
                let _ = counts.hit("e")
                Color.clear.frame(width: 1, height: 1)
            }
            ZTronHeaderGeometryReader(header, of: \.restingHeight) { _ in
                let _ = counts.hit("f")
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }
}

/// Design M8b §3 tests 7, 11, 12 (+ the reader tier) through the real container, both OS paths.
@MainActor
@Suite(.serialized)
struct ScalingHeaderHostedTests {
    func window<V: View>(_ view: V, size: CGSize = CGSize(width: 402, height: 874)) -> UIWindow {
        let w = UIWindow(frame: CGRect(origin: .zero, size: size))
        w.rootViewController = UIHostingController(rootView: view)
        w.makeKeyAndVisible()
        pump(0.3)
        return w
    }

    func oPrime(_ s: ZTronScrollState) -> CGFloat {
        let p = s.peek
        return HeaderMath.headerOffset(offset: p.presentationOffset, zoom: p.presentationZoom, metrics: p.metrics)
    }

    func track(_ s: ZTronScrollState, oPrime x: CGFloat) {
        s.track(offset: CGPoint(x: 0, y: x - HeaderMath.base(s.peek.metrics)), zoom: 1)
    }

    /// How often `key(geometry)` changed along `path` (from rest).
    func transitions<T: Equatable>(_ path: [CGFloat], _ m: HeaderMetrics, _ key: (ZTronHeaderGeometry) -> T) -> Int {
        var last = key(HeaderMath.geometry(o: 0, m: m)), n = 0
        for o in path {
            let k = key(HeaderMath.geometry(o: o, m: m))
            if k != last { n += 1; last = k }
        }
        return n
    }

    func profile(_ s: ZTronScrollState, counts: BodyCount, header: HeaderCounts,
                 behavior: ZTronHeaderScalingBehavior = .stretch) -> some View {
        ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
            .withScalingHeader(size: .fixed(min: 64, max: 240), scalingBehavior: behavior) { proxy in
                ZStack(alignment: .bottom) {
                    Color.red
                    VStack(spacing: 0) {
                        StaticHeaderChild(counts: header)
                        HeaderReaderChildren(header: proxy, counts: header)
                    }
                }
            }
    }

    @Test(arguments: OSPath.allCases) func collapseAndStretchRunNoContentOrHeaderBodyAndOneFramePerFrame(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount(), header = HeaderCounts()
        let w = withOSPath(path) { window(profile(s, counts: counts, header: header)) }
        let m = try! #require(s.peek.metrics.header)
        #expect(m.resting == 240 && m.band == 176)
        #expect(s.adjustedContentInset.top == HeaderMath.top0(s.peek.metrics) + 240, "the resting height is reserved")
        #expect(oPrime(s) == 0, "the content starts below the header")
        let contentBodies = counts.bodies
        let before = header.runs
        #expect(header.n("b") <= 2, "the static child ran with the builder at install (twice on 17+: cold)")
        #expect(header.n("f") <= 2, "(f) at most the unresolved geometry, then the resting height")
        let installF = header.n("f")
        ZTronRenderCounters.reset()
        let collapse = (1...120).map { CGFloat($0) * 1.5 }
        let stretch = (1...60).map { -CGFloat($0) }
        for x in collapse { track(s, oPrime: x); pump(0.02) }
        for x in stretch { track(s, oPrime: x); pump(0.02) }
        pump(0.1)
        let path = collapse + stretch
        #expect(counts.bodies == contentBodies, "content.body 0")
        #expect(ZTronRenderCounters.value("header.builder") == 0, "the builder never runs while scrolling")
        #expect(ZTronRenderCounters.value("header.frame") == path.count, "one frame-leaf body per drawn frame")
        #expect(header.n("b") == before["b"], "(b) a child without a reader never runs")
        #expect(header.n("c") - (before["c"] ?? 0) == transitions(path, m, { $0 }), "(c) once per distinct geometry")
        #expect(header.n("d") - (before["d"] ?? 0) == transitions(path, m, { $0.height.rounded() }), "(d) distinct rounded heights")
        let quantized = header.n("e") - (before["e"] ?? 0)
        #expect(quantized == transitions(path, m, ZTronHeaderGeometry.quantizedProgress(steps: 10)))
        #expect(transitions(collapse, m, ZTronHeaderGeometry.quantizedProgress(steps: 10)) <= 11, "(e) ≤ steps + 1 per collapse")
        #expect(header.n("f") == installF, "(f) the resting height never changed")
        #expect(s.headerGeometry?.height == 300 && s.headerGeometry?.stretch == 60)
        // A transaction: the frame leaf runs once inside it, SwiftUI interpolates.
        ZTronRenderCounters.reset()
        withAnimation(.linear(duration: 0.2)) { s.scroll(to: CGPoint(x: 0, y: -HeaderMath.base(s.peek.metrics) + 100)) }
        pump(0.6)
        #expect(ZTronRenderCounters.value("header.frame") == 1, "one frame-leaf body per transaction")
        #expect(ZTronRenderCounters.value("header.builder") == 0 && counts.bodies == contentBodies)
        #expect(abs(oPrime(s) - 100) < 0.5)
        // A discrete inset change (metrics) re-lays out the header, it never re-runs the builder.
        ZTronRenderCounters.reset()
        s.contentInset = EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 0)
        pump(0.2)
        #expect(ZTronRenderCounters.value("header.builder") == 0 && counts.bodies == contentBodies)
        #expect(ZTronRenderCounters.value("header.frame") >= 1)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theHeaderKeepsItsStateAcrossARebuildAndASizeChange(path: OSPath) {
        @MainActor final class Model: ObservableObject {
            @Published var label = "one"
            @Published var size = ZTronHeaderSize.fixed(min: 0, max: 200)
        }
        struct Parent: View {
            @ObservedObject var model: Model
            let state: ZTronScrollState
            let counts: BodyCount
            let header: HeaderCounts
            var body: some View {
                ZTronScrollView(.vertical, state: state) { StatefulContent(counts: counts) }
                    .withScalingHeader(size: model.size) { _ in StaticHeaderChild(counts: header, label: model.label) }
            }
        }
        let s = makeState(path)
        let model = Model()
        let counts = BodyCount(), header = HeaderCounts()
        let w = withOSPath(path) { window(Parent(model: model, state: s, counts: counts, header: header)) }
        track(s, oPrime: 300); pump(0.1)
        track(s, oPrime: -40); pump(0.1)
        track(s, oPrime: 0); pump(0.1)
        ZTronRenderCounters.reset()
        model.label = "two"
        pump(0.2)
        #expect(ZTronRenderCounters.value("header.builder") == 1, "a parent rebuild runs the builder once")
        #expect(header.labels.last == "two", "the new closure is the one that runs (R7)")
        model.size = .fixed(min: 0, max: 300)
        pump(0.2)
        #expect(s.peek.metrics.header?.resting == 300)
        #expect(header.ids.count == 1, "the header's @State survived collapse, stretch, rebuild and size change")
        #expect(counts.ids.count == 1 && counts.appears == 1)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aHorizontalViewHasAFixedBannerStackedAbove(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            window(ZTronScrollView(.horizontal, state: s) { Color.green.frame(width: 2000) }
                .withScalingHeader(size: .fixed(min: 0, max: 100), scalingBehavior: .stretch) { _ in Color.red })
        }
        let m = s.peek.metrics
        #expect(m.header?.vertical == false)
        #expect(m.adjustedContentInset.top == HeaderMath.top0(m) + 100, "the content lays out below the banner")
        s.setContentOffset(CGPoint(x: 300, y: 250), animated: false)
        pump(0.1)
        #expect(s.headerGeometry?.height == 100 && s.headerGeometry?.progress == 0, "any o.y: a fixed banner")
        s.setContentOffset(CGPoint(x: 300, y: -400), animated: false)
        pump(0.1)
        #expect(s.headerGeometry?.height == 100 && s.headerGeometry?.stretch == 0, ".stretch is inert")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func bothAxesAreDrivenByTheVerticalOffset(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            window(ZTronScrollView([.horizontal, .vertical], state: s) { Color.green.frame(width: 2000, height: 3000) }
                .withScalingHeader(size: .fixed(min: 0, max: 100)) { _ in Color.red })
        }
        track(s, oPrime: 40)
        pump(0.1)
        #expect(s.headerGeometry?.height == 60)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aReaderWithoutAProxyReadsTheEnclosingScrollView(path: OSPath) {
        let s = makeState(path)
        final class Seen { var heights: [CGFloat] = [] }
        let seen = Seen()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 3000) }
                .withScalingHeader(size: .fixed(min: 0, max: 200)) { _ in
                    ZTronHeaderGeometryReader(of: \.height) { h in
                        let _ = seen.heights.append(h)
                        Color.red
                    }
                })
        }
        track(s, oPrime: 50)
        pump(0.1)
        #expect(seen.heights.contains(200) && seen.heights.last == 150, "\(seen.heights)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aViewWithoutAHeaderIsUnchanged(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) { window(ZTronScrollView(.vertical, state: s) { Color.green.frame(height: 3000) }) }
        #expect(s.peek.metrics.header == nil && s.headerGeometry == nil && s.geometry.header == nil)
        #expect(s.adjustedContentInset.top == s.peek.metrics.safeAreaInsets.top)
        unhost(w)
    }
}
