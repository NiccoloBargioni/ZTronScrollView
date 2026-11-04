import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Open item 34 (M8b-s8 s2): a SwiftUI animation inside the content (the user's own `withAnimation(.easeInOut(duration:
/// 0.5))` change of the content) runs on every display frame inside a `ZTronScrollView`, as in plain SwiftUI: an
/// `Animatable` modifier driven by the change (`uval`), an effect on the rows' animated frame (`uframe`), an `Animatable`
/// inside the header builder driven by the same change (`hval`), and the drawn height of a bar whose height follows the
/// change (`drawn`: the presentation tree, sampled every display frame).
///
/// Two contents: `insert` (5 -> 10 rows, the new rows fade in: an animated insertion) and `grow` (5 rows whose height grows
/// 60 -> 120 pt: no insertion). Two rigs (`AppFrameDriver`): driven (the app's per-frame main-thread pass supplied by a
/// running `TimelineView` beside the hosted view: the gates) and undriven (this app-less process as it is).
///
/// Measured (2026-11-04, 27.0 and 17.5, preferred and forced; Orchestration open item 34): undriven, an animated insertion
/// stops after its first frame in plain SwiftUI as much as inside a `ZTronScrollView` (SwiftUI draws that frame off the main
/// thread and the main-thread pass that must follow never comes without the app's update cycle); a frame that grows runs
/// off the main thread to the end, except under a `geometryGroup()` on 27.0 (17.5 runs it there too), which the library
/// puts above the content and the header (`ContentLayerGroup`, `HeaderLayerGroup`). A native `ScrollView` ticks undriven
/// in every case, on the main thread: its content is hosted in a `UIScrollView`, whose layout passes run here. The app runs
/// every frame (seam lab `rows`: the rows' own animation drawn on every display frame, three lanes), so the gates run
/// driven; the undriven test pins that the library adds no stall of its own to the asynchronous path.
@MainActor
@Suite(.serialized)
struct ContentAnimationTickTests {
    /// Lock-protected: `GeometryEffect.effectValue` may run off the main thread (SwiftUI's asynchronous renderer).
    final class Probe: @unchecked Sendable {
        struct Sample { var t: TimeInterval; var v: CGFloat; var main = true }
        private let lock = NSLock()
        private var store: [String: [Sample]] = [:]
        static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
        func record(_ key: String, _ v: CGFloat) {
            let main = Thread.isMainThread
            lock.lock(); store[key, default: []].append(Sample(t: Self.now(), v: v, main: main)); lock.unlock()
        }
        func reset() { lock.lock(); store = [:]; lock.unlock() }
        func samples(_ key: String) -> [Sample] { lock.lock(); defer { lock.unlock() }; return store[key] ?? [] }
        /// Body runs of the rows, by index (bodies run on the main thread).
        var rowBodies: [Int: Int] = [:]
    }

    final class Rows: ObservableObject {
        @Published var n: Int
        init(_ n: Int) { self.n = n }
    }

    /// The bar's color (found in the presentation tree by it).
    static let marker = (r: 0.41, g: 0.17, b: 0.29)

    /// An animatable value driven by the change.
    struct UVal: GeometryEffect {
        let key: String
        var v: CGFloat
        let probe: Probe
        var animatableData: CGFloat {
            get { v }
            set { v = newValue }
        }
        func effectValue(size: CGSize) -> ProjectionTransform { probe.record(key, v); return ProjectionTransform() }
    }

    /// The size it is laid out at (the rows' animated frame).
    struct UFrame: GeometryEffect {
        let key: String
        let probe: Probe
        var animatableData: EmptyAnimatableData {
            get { EmptyAnimatableData() }
            set {}
        }
        func effectValue(size: CGSize) -> ProjectionTransform { probe.record(key, size.height); return ProjectionTransform() }
    }

    enum Content: String, CaseIterable, Sendable {
        /// 5 -> 10 rows of 60 pt: the new rows fade in (SwiftUI's default `.opacity` transition).
        case insert
        /// 5 rows growing from 60 to 120 pt: no insertion.
        case grow
    }

    /// One row; counts its body runs (S4: a row change re-runs no row that kept its inputs).
    struct Row: View {
        let i: Int
        let height: CGFloat
        let probe: Probe
        var body: some View {
            probe.rowBodies[i, default: 0] += 1
            return (i % 2 == 0 ? Color.green : Color.yellow).frame(height: height)
        }
    }

    /// The user's content: rows and a bar of `10 n` pt (n = the row count, or the growth step for `grow`).
    struct RowsContent: View {
        let n: Int
        let content: Content
        let probe: Probe
        var body: some View {
            VStack(spacing: 0) {
                switch content {
                case .insert:
                    ForEach(0..<n, id: \.self) { Row(i: $0, height: 60, probe: probe) }
                case .grow:
                    ForEach(0..<5, id: \.self) { Row(i: $0, height: 12 * CGFloat(n), probe: probe) }
                }
            }
            .overlay(alignment: .topTrailing) {
                Color(red: marker.r, green: marker.g, blue: marker.b).frame(width: 40, height: 10 * CGFloat(n))
            }
            .modifier(UFrame(key: "uframe", probe: probe))
            .modifier(UVal(key: "uval", v: CGFloat(n), probe: probe))
        }
    }

    /// The content's own view observing the model: an internal change re-evaluates only this view.
    struct Inner: View {
        @ObservedObject var rows: Rows
        let content: Content
        let probe: Probe
        var body: some View { RowsContent(n: rows.n, content: content, probe: probe) }
    }

    /// The header's own content, driven by the same change.
    struct HeaderContent: View {
        @ObservedObject var rows: Rows
        let probe: Probe
        var body: some View {
            Color.blue.modifier(UVal(key: "hval", v: CGFloat(rows.n), probe: probe))
        }
    }

    enum HeaderCase: String, CaseIterable, Sendable { case none, compress, slideBehind }

    enum Change: String, CaseIterable, Sendable {
        /// The content observes the model (only its own view re-runs).
        case `internal`
        /// The container's parent passes the count (the parent's body and the container's run).
        case external
    }

    struct Host: View {
        @ObservedObject var ext: Rows
        let internalRows: Rows?
        let state: ZTronScrollState
        let header: HeaderCase
        let content: Content
        let probe: Probe
        var body: some View {
            let base = ZTronScrollView(.vertical, state: state) {
                if let internalRows {
                    Inner(rows: internalRows, content: content, probe: probe)
                } else {
                    RowsContent(n: ext.n, content: content, probe: probe)
                }
            }
            let rows = internalRows ?? ext
            let probe = probe
            switch header {
            case .none:
                return base
            case .compress:
                return base.withScalingHeader(size: .fixed(min: 64, max: 240), collapse: .compress) { _ in
                    HeaderContent(rows: rows, probe: probe)
                }
            case .slideBehind:
                return base.withScalingHeader(size: .fixed(min: 64, max: 240), collapse: .slideBehind()) { _ in
                    HeaderContent(rows: rows, probe: probe)
                }
            }
        }
    }

    /// The bar's drawn height every display frame.
    @MainActor final class Sampler: NSObject {
        var samples: [(t: TimeInterval, h: CGFloat)] = []
        weak var window: UIWindow?
        private var link: CADisplayLink?
        func start(_ w: UIWindow) {
            window = w
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        @objc func tick(_ l: CADisplayLink?) {
            guard let w = window, let h = ContentAnimationTickTests.drawnHeight(in: w) else { return }
            samples.append((Probe.now(), h))
        }
        func stop() { link?.invalidate(); link = nil }
    }

    /// The drawn (presentation) height of the layer filled with `marker`.
    static func drawnHeight(in window: UIWindow) -> CGFloat? {
        func visit(_ layer: CALayer) -> CGFloat? {
            let l = layer.presentation() ?? layer
            if let c = l.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - marker.r) < 0.02, abs(g - marker.g) < 0.02, abs(b - marker.b) < 0.02 {
                    return l.bounds.height
                }
            }
            for s in layer.sublayers ?? [] { if let h = visit(s) { return h } }
            return nil
        }
        return visit(window.layer)
    }

    /// One animated change's numbers in its first 0.5 s.
    struct Run: CustomStringConvertible {
        /// Distinct values each probe was evaluated at (an animation that runs: one per display frame, ~30).
        var uval = 0, uframe = 0, hval = 0
        /// Distinct drawn heights of the bar.
        var drawn = 0
        /// The largest drawn step as a fraction of the drawn change (one frame carrying the whole change is 1).
        var drawnMaxStep: CGFloat = 0
        /// Evaluations of `uval` off the main thread (SwiftUI's asynchronous renderer).
        var offMain = 0
        /// The bar's last drawn height 0.8 s after the change (its end value once the animation has landed).
        var last: CGFloat = -1
        /// Body runs of the rows that existed before the change (S4: 0) and of the header builder (`header.builder`).
        var keptRowBodies = 0, headerBuilds = 0
        var description: String {
            String(format: "uval %d uframe %d hval %d drawn %d (max step %.2f) last %.2f offMain %d keptRowBodies %d headerBuilds %d",
                   uval, uframe, hval, drawn, drawnMaxStep, last, offMain, keptRowBodies, headerBuilds)
        }
    }

    static func distinct(_ xs: [Probe.Sample], from t0: TimeInterval, within d: TimeInterval) -> Int {
        Set(xs.filter { $0.t >= t0 && $0.t <= t0 + d }.map { Int(($0.v * 100).rounded()) }).count
    }

    /// The change's end values: `insert` 5 -> 10 rows, `grow` 5 -> 10 (60 -> 120 pt rows).
    static let from = 5, to = 10

    /// Hosts `view` (driven or not), then runs `change` in `withAnimation(.easeInOut(duration: 0.5))`.
    func measure<V: View>(_ path: OSPath, _ view: V, probe: Probe, driven: Bool, prepare: () -> Void = {},
                          change: () -> Void) -> Run {
        let w = withOSPath(path) { hostDriven(view, driven: driven) }
        defer { unhost(w) }
        prepare()
        pump(0.4)
        let sampler = Sampler()
        sampler.start(w)
        pump(0.1)
        probe.reset()
        probe.rowBodies = [:]
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        let t0 = Probe.now()
        withAnimation(.easeInOut(duration: 0.5)) { change() }
        pump(0.8)
        sampler.stop()
        var run = Run()
        run.uval = Self.distinct(probe.samples("uval"), from: t0, within: 0.5)
        run.uframe = Self.distinct(probe.samples("uframe"), from: t0, within: 0.5)
        run.hval = Self.distinct(probe.samples("hval"), from: t0, within: 0.5)
        run.offMain = probe.samples("uval").filter { !$0.main }.count
        let window = sampler.samples.filter { $0.t >= t0 && $0.t <= t0 + 0.5 }
        run.drawn = Set(window.map { Int(($0.h * 100).rounded()) }).count
        run.last = sampler.samples.last?.h ?? -1
        let hs = sampler.samples.filter { $0.t >= t0 - 0.05 }.map(\.h)
        if let a = hs.first, let b = hs.last, abs(b - a) > 0.5 {
            run.drawnMaxStep = zip(hs, hs.dropFirst()).map { abs($1 - $0) }.max().map { $0 / abs(b - a) } ?? 0
        }
        run.keptRowBodies = (0..<Self.from).reduce(0) { $0 + (probe.rowBodies[$1] ?? 0) }
        #if DEBUG
        run.headerBuilds = ZTronRenderCounters.value("header.builder")
        #endif
        return run
    }

    /// The library rig: a `ZTronScrollView` around the content, with or without a header.
    func measure(_ path: OSPath, header: HeaderCase, change: Change, content: Content, driven: Bool = true,
                 shrink: Bool = false) -> Run {
        let probe = Probe()
        let state = makeState(path), ext = Rows(Self.from)
        let inner: Rows? = change == .internal ? Rows(Self.from) : nil
        let rows = inner ?? ext
        let host = Host(ext: ext, internalRows: inner, state: state, header: header, content: content, probe: probe)
        return measure(path, host, probe: probe, driven: driven, prepare: {
            if shrink { rows.n = Self.to }
        }, change: { rows.n = shrink ? Self.from : Self.to })
    }

    /// The SwiftUI references, the same content: the window's root view (`plain`), the same under the layer group the
    /// library puts above the content (`grouped`: `geometryGroup()` on 17+, `compositingGroup()` on the forced path, the
    /// group `ContentLayerGroup` applies with a header), and a native `ScrollView` around it (`native`, the parity target).
    enum Reference: String, CaseIterable, Sendable { case plain, grouped, native }

    struct ReferenceHost: View {
        let reference: Reference
        let forced: Bool
        let inner: Inner
        var body: some View {
            switch reference {
            case .plain:
                inner
            case .grouped:
                if !forced, #available(iOS 17, *) { inner.geometryGroup() } else { inner.compositingGroup() }
            case .native:
                ScrollView { inner }
            }
        }
    }

    func reference(_ path: OSPath, content: Content, driven: Bool, _ reference: Reference = .plain) -> Run {
        let probe = Probe(), rows = Rows(Self.from)
        let inner = Inner(rows: rows, content: content, probe: probe)
        let forced = withOSPath(path) { !ZTronAvailability.isAvailable(.geometryGroup) }
        return measure(path, ReferenceHost(reference: reference, forced: forced, inner: inner), probe: probe,
                       driven: driven, change: { rows.n = Self.to })
    }

    // MARK: The gates (driven: every frame drawn, as in the app)

    /// The rig itself: plain SwiftUI ticks when driven.
    @Test(arguments: OSPath.allCases, Content.allCases)
    func referenceTicksDriven(path: OSPath, content: Content) {
        let r = reference(path, content: content, driven: true)
        print("TICK \(path) reference \(content) driven: \(r)")
        #expect(r.uval >= 20)
        #expect(r.uframe >= 20)
        #expect(r.drawn >= 20)
        #expect(r.drawnMaxStep < 0.5)
    }

    /// The user's own row change inside a `ZTronScrollView`, without a header and with one (both collapse modes), grown and
    /// shrunk, internal and external: every probe on >= 20 frames in 0.5 s, no drawn step >= 0.5 of the change.
    @Test(arguments: OSPath.allCases, HeaderCase.allCases)
    func rowChangeTicks(path: OSPath, header: HeaderCase) {
        for change in Change.allCases {
        for content in Content.allCases {
            for shrink in [false, true] {
                let r = measure(path, header: header, change: change, content: content, shrink: shrink)
                let tag = "\(content) \(shrink ? "shrink" : "grow")"
                print("TICK \(path) \(header) \(change) \(tag) driven: \(r)")
                #expect(r.uval >= 20, "\(tag): \(r)")
                #expect(r.uframe >= 20, "\(tag): \(r)")
                #expect(r.drawn >= 20, "\(tag): \(r)")
                #expect(r.drawnMaxStep < 0.5, "\(tag): \(r)")
                if header != .none { #expect(r.hval >= 20, "\(tag): \(r)") }
                // S4: the rows that kept their inputs (`insert`: the first five) never re-run; an internal change never
                // runs the header builder.
                if content == .insert { #expect(r.keptRowBodies == 0, "\(tag): \(r)") }
                if change == .internal { #expect(r.headerBuilds == 0, "\(tag): \(r)") }
            }
        }
        }
    }

    // MARK: The asynchronous renderer (undriven): no worse than plain SwiftUI in the same rig

    /// Without the driver: wherever SwiftUI's asynchronous renderer runs the same content under the library's own layer
    /// group (17+ `geometryGroup()`; 15–16 `compositingGroup()` with a header, none without one) to the end, it runs to the
    /// end inside a `ZTronScrollView` too: the library adds no main-thread dependency of its own to the content's
    /// animations. All three references are printed (the native `ScrollView` for the record: it ticks here on the main
    /// thread, through `UIScrollView` layout passes).
    @Test(arguments: OSPath.allCases, HeaderCase.allCases)
    func undrivenNoStallBeyondTheLayerGroup(path: OSPath, header: HeaderCase) {
        let forced = withOSPath(path) { !ZTronAvailability.isAvailable(.geometryGroup) }
        for content in Content.allCases {
            let refs = Reference.allCases.map { ($0, reference(path, content: content, driven: false, $0)) }
            let r = measure(path, header: header, change: .internal, content: content, driven: false)
            let line = refs.map { "\($0.0) [\($0.1)]" }.joined(separator: " | ")
            print("TICK \(path) \(header) internal \(content) undriven: \(r) || \(line)")
            let own = refs.first { $0.0 == (forced && header == .none ? .plain : .grouped) }!.1
            if own.uval >= 20 {
                #expect(r.uval >= 20, "\(content): \(r) vs the same group \(own)")
                #expect(r.uframe >= 20, "\(content): \(r) vs the same group \(own)")
                if header != .none { #expect(r.hval >= 20, "\(content): \(r) vs the same group \(own)") }
            }
        }
    }
}
