import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// D78 (open item 15 (b), M8b-s8 s5; design `docs/design/M8b-s8-i15b-15path-resize.md`): the 15–16 header resolves its
/// frame from its own slot. `HeaderSlotReader`'s cold `GeometryReader` gives `HeaderFallbackFrame` the slot's `W × H` in
/// the layout pass of an app-animated resize (U0), so the header is laid out at its final `R(W, H)` there and the
/// unanimated viewport commit (U1) re-sets nothing, as 16+'s `HeaderSlotLayout` (before D78 the 15 path read `R` from the
/// committed metrics: a limited `R`, `.fixed` under a limit and `.fit` inside the band landed at U1, up to 115 pt in one
/// frame on the forced lane). Both OS paths: 16+ is the reference. A hosted layout log (`HeaderReviewD16Tests.LogProbe`)
/// records every size the header content is laid out at: a layout at the new width (or after a height change) with a
/// stale height is the landing.
@MainActor
@Suite(.serialized)
struct HeaderFallbackSlotTests {
    typealias Log = HeaderReviewD16Tests.Log
    typealias LogProbe = HeaderReviewD16Tests.LogProbe

    final class Model: ObservableObject {
        @Published var short = false
        @Published var narrow = false
    }

    /// The seam lab's resize, hosted: the scroll view's height to 0.4 (`short`, top-pinned) or its width to 0.6
    /// (`narrow`), app-animated.
    struct Host: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let log: Log
        let size: ZTronHeaderSize
        let overflow: ZTronHeaderOverflow
        let counts: BodyCount
        var body: some View {
            GeometryReader { g in
                ZTronScrollView(.vertical, state: state) { StatefulContent(counts: counts) }
                    .withScalingHeader(size: size, overflow: overflow) { _ in LogProbe(log: log) }
                    .frame(width: model.narrow ? g.size.width * 0.6 : g.size.width,
                           height: model.short ? g.size.height * 0.4 : g.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    func window<V: View>(_ view: V, size: CGSize = CGSize(width: 402, height: 874)) -> UIWindow {
        let w = UIWindow(frame: CGRect(origin: .zero, size: size))
        w.rootViewController = UIHostingController(rootView: view)
        w.makeKeyAndVisible()
        pump(0.4)
        return w
    }

    /// Waits for the header's first metrics and closes the hosting turn (a synchronous test never drains the state's
    /// end-of-turn hop, D16).
    func settle(_ s: ZTronScrollState) {
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        pump(0.3)
        s.endOfTurn()
    }

    func host(_ path: OSPath, size: ZTronHeaderSize, overflow: ZTronHeaderOverflow, model: Model, log: Log,
              counts: BodyCount) -> (ZTronScrollState, UIWindow) {
        let s = makeState(path)
        let w = withOSPath(path) {
            window(Host(model: model, state: s, log: log, size: size, overflow: overflow, counts: counts))
        }
        settle(s)
        return (s, w)
    }

    /// The overflow container the committed metrics were resolved against (`HeaderMath.containerHeight`).
    func committedContainer(_ s: ZTronScrollState) -> CGFloat {
        let m = s.peek.metrics
        return HeaderMath.containerHeight(viewport: m.viewportSize, safe: m.safeAreaInsets,
                                          adjusted: s.contentInsetAdjustmentBehavior.edges(for: s.scrollAxes),
                                          keyboard: m.keyboardExtension)
    }

    // MARK: Overflow-limited R and `.fixed` (the slot)

    /// F6 (item 15 (b)): an app-animated top-pinned height change engages `.capped(0.5)`: every layout of the header
    /// after the change began has the final `R` (16+ by `HeaderSlotLayout`, 15 by the slot), none at the old one.
    @Test(arguments: OSPath.allCases, [ZTronHeaderSize.aspectRatio(16.0 / 9.0, min: 64), .fixed(min: 64, max: 240)])
    func aCappedHeightChangeIsFinalInTheAnimatedPass(path: OSPath, size: ZTronHeaderSize) {
        let log = Log(), model = Model(), counts = BodyCount()
        let (s, w) = host(path, size: size, overflow: .capped(fraction: 0.5), model: model, log: log, counts: counts)
        defer { unhost(w) }
        for short in [true, false] {
            let r0 = s.peek.metrics.header?.resting ?? -1
            log.sizes.removeAll()
            withAnimation(.linear(duration: 0.5)) { model.short = short }
            for _ in 0..<40 { pump(1.0 / 60) }
            pump(0.4)
            s.endOfTurn()
            let r1 = s.peek.metrics.header?.resting ?? -1
            #expect(abs(r1 - r0) > 10, "\(path) \(size) short \(short): the limit changed R (\(r0) -> \(r1))")
            let stale = log.sizes.filter { abs($0.height - r1) > 0.5 }
            #expect(stale.isEmpty, "\(path) \(size) short \(short): laid out at a stale height \(stale) (all \(log.sizes))")
            print("D78 height \(path) \(size) short \(short): R \(r0) -> \(r1), sizes \(log.sizes)")
        }
    }

    /// S-RS-2: `.capped(0.25)` (engaged at 402 pt, off at 241 pt), half collapsed, the width 402 → 241 pt and back: no
    /// layout at a stale height for the width it is laid out at.
    @Test(arguments: OSPath.allCases)
    func aWidthChangeThatTurnsTheLimitOffIsFinalInTheAnimatedPass(path: OSPath) {
        let log = Log(), model = Model(), counts = BodyCount()
        let (s, w) = host(path, size: .aspectRatio(16.0 / 9.0, min: 64), overflow: .capped(fraction: 0.25), model: model,
                          log: log, counts: counts)
        defer { unhost(w) }
        s.snapHeader(to: .progress(0.5), animated: false)
        pump(0.3)
        s.endOfTurn()
        for narrow in [true, false] {
            log.sizes.removeAll()
            withAnimation(.linear(duration: 0.5)) { model.narrow = narrow }
            for _ in 0..<40 { pump(1.0 / 60) }
            pump(0.4)
            s.endOfTurn()
            let h = s.headerGeometry?.height ?? -1
            let W = s.peek.metrics.viewportSize.width
            #expect(abs((s.headerGeometry?.progress ?? -1) - 0.5) < 0.01, "\(path) narrow \(narrow): progress kept")
            let stale = log.sizes.filter { abs($0.width - W) < 0.5 && abs($0.height - h) > 0.5 }
            #expect(stale.isEmpty, "\(path) narrow \(narrow): laid out at \(W) with a stale height \(stale), final \(h) (all \(log.sizes))")
            #expect(log.sizes.contains { abs($0.width - W) < 0.5 }, "\(path) narrow \(narrow): laid out at the new width")
            print("D78 width \(path) narrow \(narrow): h \(h) at \(W), sizes \(log.sizes)")
        }
    }

    // MARK: S4

    /// A header content that counts its body runs (S4: a resize re-lays it out, never re-evaluates it).
    struct HeaderBodyProbe: View {
        let counts: BodyCount
        var body: some View {
            counts.bodies += 1
            return Color.blue
        }
    }

    /// S4: the slot reader's closure never runs while the content scrolls, collapses the header or pulls it (90 steps);
    /// no builder run, no content body.
    @Test(arguments: OSPath.allCases, [ZTronHeaderSize.fixed(min: 64, max: 240), .fit(min: 64)])
    func theSlotReaderRunsOnResizesOnlyNeverPerFrame(path: OSPath, size: ZTronHeaderSize) {
        let log = Log(), model = Model(), counts = BodyCount()
        let (s, w) = host(path, size: size, overflow: .capped(fraction: 0.5), model: model, log: log, counts: counts)
        defer { unhost(w) }
        guard s.peek.metrics.header != nil else { Issue.record("\(path) \(size): unresolved"); return }
        let bodies = counts.bodies
        ZTronRenderCounters.reset()
        let steps = (1...60).map { CGFloat($0) * 3 } + (1...30).map { -CGFloat($0) * 2 }
        for x in steps {
            s.track(offset: CGPoint(x: 0, y: x - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.02)
        }
        pump(0.1)
        #expect(ZTronRenderCounters.value("header.slot") == 0,
                "\(path) \(size): the slot reader ran \(ZTronRenderCounters.value("header.slot")) times during motion")
        #expect(ZTronRenderCounters.value("header.builder") == 0, "\(path) \(size): builder 0 during motion")
        #expect(counts.bodies == bodies, "\(path) \(size): content.body 0 during motion")
        #expect(ZTronRenderCounters.value("header.frame") > 0, "\(path) \(size): the leaf followed the motion")
        print("D78 motion \(path) \(size): leaf bodies \(ZTronRenderCounters.value("header.frame")) for \(steps.count) steps")
    }

    /// S4, resize: the container is the window's root view (no parent body runs for a window resize): the slot reader
    /// runs (15 / forced; there is none on 16+), the header's builder does not, no content body (the scroll content's
    /// nor the header content's) is re-evaluated.
    @Test(arguments: OSPath.allCases, [ZTronHeaderSize.fixed(min: 64, max: 240), .fit(min: 64)])
    func aWindowResizeRunsTheSlotReaderNotTheBuilder(path: OSPath, size: ZTronHeaderSize) {
        let counts = BodyCount(), hcounts = BodyCount()
        let s = makeState(path)
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: size, overflow: .capped(fraction: 0.5)) { _ in
                    HeaderBodyProbe(counts: hcounts).aspectRatio(16.0 / 9.0, contentMode: .fit)
                })
        }
        defer { unhost(w) }
        settle(s)
        guard s.peek.metrics.header != nil else { Issue.record("\(path) \(size): unresolved"); return }
        let bodies = counts.bodies, hbodies = hcounts.bodies
        ZTronRenderCounters.reset()
        w.frame = CGRect(x: 0, y: 0, width: 402, height: 520)
        pump(0.8)
        let runs = ZTronRenderCounters.value("header.slot")
        #expect(path == .preferred ? runs == 0 : runs >= 1, "\(path) \(size): the slot reader ran \(runs) times for one resize")
        #expect(ZTronRenderCounters.value("header.builder") == 0, "\(path) \(size): no builder run for a resize")
        #expect(counts.bodies == bodies, "\(path) \(size): content.body 0 for a resize")
        #expect(hcounts.bodies == hbodies, "\(path) \(size): the header content's body ran \(hcounts.bodies - hbodies) times")
        let R = s.peek.metrics.header?.resting ?? -1
        let L = committedContainer(s) * 0.5
        let expected = size.isFit ? min(402 * 9 / 16, L) : min(240, L)
        #expect(abs(R - expected) < 0.5, "\(path) \(size): R \(R) at 402 x 520, expected \(expected)")
        print("D78 window resize \(path) \(size): R \(R), slot runs \(runs), leaf bodies \(ZTronRenderCounters.value("header.frame"))")
    }

    // MARK: C16, the slot height

    /// Plan C16: at rest the slot's height IS the committed overflow container (`HeaderMath.containerHeight`), in both
    /// orientations and on both paths (the 15 path's `HeaderSlotReader`, 16+'s `HeaderSlotLayout`): D75's lift
    /// reconstructs the viewport as `slot + dv`, and the `.fit` box keeps the height fit only while they agree.
    @Test(arguments: OSPath.allCases, [CGSize(width: 402, height: 874), CGSize(width: 874, height: 402)])
    func theSlotIsTheCommittedContainerAtRest(path: OSPath, windowSize: CGSize) {
        for size in [ZTronHeaderSize.fixed(min: 64, max: 240), .fit(min: 64)] {
            let counts = BodyCount()
            let s = makeState(path)
            ZTronRenderCounters.reset()
            let w = withOSPath(path) {
                window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                    .withScalingHeader(size: size) { _ in Color.blue.aspectRatio(16.0 / 9.0, contentMode: .fit) },
                       size: windowSize)
            }
            settle(s)
            let tag = "\(path) \(size) \(windowSize)"
            let note = ZTronRenderCounters.notes["header.slot.size"] ?? ""
            let parts = note.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2, s.peek.metrics.header != nil else {
                Issue.record("\(tag): no slot note '\(note)' or unresolved"); unhost(w); continue
            }
            let container = committedContainer(s)
            #expect(abs(CGFloat(parts[1]) - container) <= 0.5, "\(tag): slot H \(parts[1]) vs committed container \(container)")
            #expect(abs(CGFloat(parts[0]) - s.peek.metrics.viewportSize.width) <= 0.5,
                    "\(tag): slot W \(parts[0]) vs viewport \(s.peek.metrics.viewportSize.width)")
            print("D78 C16 \(tag): slot \(note), container \(container)")
            unhost(w)
        }
    }
}
