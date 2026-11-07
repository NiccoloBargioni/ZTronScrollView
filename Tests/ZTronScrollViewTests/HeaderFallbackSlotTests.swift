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
        @Published var tall = false
        @Published var relaxed = false
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


    // MARK: `.fit` (the ideal-ratio box)

    /// A `.fit` header content: ideal height `W · 9 / 16` (or `W · 3 / 4` when `tall`) at the proposed width, fills its
    /// live frame, logs it.
    struct FitProbe: View {
        @ObservedObject var model: Model
        let log: Log
        var body: some View {
            Color.clear.aspectRatio(model.tall ? 4.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .overlay(LogProbe(log: log))
        }
    }

    struct FitHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let log: Log
        let overflow: ZTronHeaderOverflow
        let counts: BodyCount
        var body: some View {
            GeometryReader { g in
                ZTronScrollView(.vertical, state: state) { StatefulContent(counts: counts) }
                    .withScalingHeader(size: .fit(min: 64), overflow: overflow) { _ in FitProbe(model: model, log: log) }
                    .frame(width: model.narrow ? g.size.width * 0.6 : g.size.width,
                           height: model.short ? g.size.height * 0.4 : g.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    func hostFit(_ path: OSPath, overflow: ZTronHeaderOverflow, model: Model, log: Log, counts: BodyCount)
        -> (ZTronScrollState, UIWindow) {
        let s = makeState(path)
        let w = withOSPath(path) { window(FitHost(model: model, state: s, log: log, overflow: overflow, counts: counts)) }
        settle(s)
        return (s, w)
    }

    /// Item 15 (b), `.fit` inside the band: an app-animated width change lays the header out at the new width with its
    /// final height in the animated pass (16+ by `HeaderSlotLayout`'s ideal-size query, 15 by the box's width fit), never
    /// at a stale height (before D78 the measuring pass's flip re-set it at the commit: lateral 159 pt on the forced lane),
    /// uncapped and `.capped(0.25)` (engaged at 402 pt, off at 241 pt), half and fully collapsed.
    @Test(arguments: OSPath.allCases, [(ZTronHeaderOverflow.uncapped, CGFloat(0.5)), (.capped(fraction: 0.25), 0.5),
                                       (.uncapped, 1), (.capped(fraction: 0.25), 1)])
    func aFitWidthChangeInTheBandIsFinalInTheAnimatedPass(path: OSPath, c: (ZTronHeaderOverflow, CGFloat)) {
        let (overflow, progress) = c
        let log = Log(), model = Model(), counts = BodyCount()
        let (s, w) = hostFit(path, overflow: overflow, model: model, log: log, counts: counts)
        defer { unhost(w) }
        guard s.peek.metrics.header != nil else { Issue.record("\(path) \(overflow): unresolved"); return }
        s.snapHeader(to: .progress(progress), animated: false)
        pump(0.3)
        s.endOfTurn()
        let limit = HeaderMath.overflowLimit(overflow, containerHeight: committedContainer(s))
        for narrow in [true, false] {
            log.sizes.removeAll()
            ZTronRenderCounters.reset()
            let bodies = counts.bodies
            withAnimation(.linear(duration: 0.5)) { model.narrow = narrow }
            for _ in 0..<40 { pump(1.0 / 60) }
            pump(0.4)
            s.endOfTurn()
            let h = s.headerGeometry?.height ?? -1
            let W = s.peek.metrics.viewportSize.width
            let R = s.peek.metrics.header?.resting ?? -1
            let tag = "\(path) \(overflow) q \(progress) narrow \(narrow)"
            let stale = log.sizes.filter { abs($0.width - W) < 0.5 && abs($0.height - h) > 0.5 }
            #expect(stale.isEmpty, "\(tag): laid out at \(W) with a stale height \(stale), final \(h) (all \(log.sizes))")
            #expect(log.sizes.contains { abs($0.width - W) < 0.5 }, "\(tag): laid out at the new width")
            let expected = min(W * 9 / 16, limit)
            #expect(abs(R - expected) < 0.5, "\(tag): R \(R) at \(W), expected \(expected)")
            #expect(abs((s.headerGeometry?.progress ?? -1) - progress) < 0.01, "\(tag): progress kept")
            #expect(counts.bodies == bodies, "\(tag): content.body 0")
            print("D78 fit \(tag): R \(R) h \(h) at \(W), sizes \(log.sizes), events \(ZTronRenderCounters.eventsJoined.suffix(600))")
        }
    }

    // MARK: As drawn (the presentation tree)

    /// The header marker filling the live frame; under `.fit` a 16:9 ideal height at any width (the seam lab's red header).
    struct DrawnHeader: View {
        let size: ZTronHeaderSize
        var body: some View {
            let marker = HeaderStretchScaleTests.color(HeaderStretchScaleTests.headerMarker)
            if size.isFit {
                Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .background(marker)
            } else {
                marker
            }
        }
    }

    /// The seam lab's width change, hosted: the scroll view's width to 0.6, centred, app-animated; the content's top is a
    /// marker strip (`HeaderStretchScaleTests.Content`).
    struct DrawnHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let size: ZTronHeaderSize
        let overflow: ZTronHeaderOverflow
        let counts: BodyCount
        var body: some View {
            GeometryReader { g in
                ZTronScrollView(.vertical, state: state) { HeaderStretchScaleTests.Content(counts: counts) }
                    .withScalingHeader(size: size, overflow: overflow) { _ in DrawnHeader(size: size) }
                    .frame(width: model.narrow ? g.size.width * 0.6 : g.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// Item 15 (b) as drawn (the seam lab's `fit-half-preserve-width-capped25` row and its neighbours, hosted): an
    /// app-animated width change interpolates the drawn header with the drawn content in every sampled frame: its bottom
    /// edge on the content's top (|seam| < 1), its sides on the content's (lateral < 1), its height in steps (no frame
    /// moves it by half the change). Read from the presentation tree (`HeaderStretchScaleTests.frames`): a layout that is
    /// final in both passes is not enough. d89c745 offered the overflow limit to a single `.fit` box as an ideal height
    /// (`frame(idealHeight:)`): the narrowing that leaves the limit (402 → 241 pt, `.capped(0.25)`, half collapsed) drew
    /// the header at its final size from the first frame on the forced path (seam 29.3 pt, lateral 160.7 pt, one step;
    /// the seam lab measured the same), with the same layout as now (the layout logs above saw nothing). Now the limit
    /// clamps an outer layout box (`HeaderFallbackFrame`).
    @Test(arguments: OSPath.allCases, [(ZTronHeaderSize.fit(min: 64), ZTronHeaderOverflow.capped(fraction: 0.25), CGFloat(0.5)),
                                       (.fit(min: 64), .uncapped, 0.5), (.fit(min: 64), .uncapped, 0),
                                       (.aspectRatio(16.0 / 9.0, min: 64), .capped(fraction: 0.25), 0.5)])
    func aWidthChangeIsDrawnWithTheContent(path: OSPath, c: (ZTronHeaderSize, ZTronHeaderOverflow, CGFloat)) {
        let (size, overflow, progress) = c
        let model = Model(), counts = BodyCount()
        let s = makeState(path)
        let w = withOSPath(path) { window(DrawnHost(model: model, state: s, size: size, overflow: overflow, counts: counts)) }
        defer { unhost(w) }
        settle(s)
        guard s.peek.metrics.header != nil else { Issue.record("\(path) \(size): unresolved"); return }
        if progress > 0 {
            s.snapHeader(to: .progress(progress), animated: false)
            pump(0.3)
            s.endOfTurn()
        }
        func sample() -> (header: CGRect, content: CGRect)? {
            guard let h = HeaderStretchScaleTests.frames(of: HeaderStretchScaleTests.headerMarker, in: w, presented: true).first,
                  let c = HeaderStretchScaleTests.frames(of: HeaderStretchScaleTests.contentMarker, in: w, presented: true).first
            else { return nil }
            return (h, c)
        }
        for narrow in [true, false] {
            let tag = "\(path) \(size) \(overflow) q \(progress) narrow \(narrow)"
            guard let start = sample() else { Issue.record("\(tag): no marker layers at rest"); return }
            withAnimation(.linear(duration: 0.5)) { model.narrow = narrow }
            var frames: [(header: CGRect, content: CGRect)] = []
            for _ in 0..<40 {
                pump(1.0 / 60)
                if let f = sample() { frames.append(f) }
            }
            pump(0.4)
            s.endOfTurn()
            guard let end = sample() else { Issue.record("\(tag): no marker layers at the end"); return }
            let seam = frames.map { abs($0.header.maxY - $0.content.minY) }.max() ?? .infinity
            let lateral = frames.map { max(abs($0.header.minX - $0.content.minX), abs($0.header.maxX - $0.content.maxX)) }
                .max() ?? .infinity
            let heights = [start.header.height] + frames.map(\.header.height) + [end.header.height]
            let change = abs(end.header.height - start.header.height)
            let step = zip(heights, heights.dropFirst()).map { abs($1 - $0) }.max() ?? 0
            #expect(frames.count >= 20, "\(tag): sampled \(frames.count) frames")
            #expect(seam < 1, "\(tag): header bottom vs content top, worst \(seam)")
            #expect(lateral < 1, "\(tag): header sides vs content sides, worst \(lateral)")
            #expect(change < 1 || step < 0.5 * change, "\(tag): the header's height moved \(step) of \(change) in one frame")
            let fmt = { (r: CGRect) in String(format: "%.2f,%.2f %.2fx%.2f", r.minX, r.minY, r.width, r.height) }
            print("D78 drawn \(tag): seam \(seam) lateral \(lateral) step \(step) of \(change); start \(fmt(start.header)) "
                  + "end \(fmt(end.header)); first frames \(frames.prefix(4).map { fmt($0.header) + " | " + fmt($0.content) })")
        }
    }

    /// A header content that logs each size it is laid out at with the state's committed `R` at that moment.
    struct CommitLogProbe: View {
        let log: CommitLog
        let state: ZTronScrollState
        var body: some View {
            GeometryReader { g in
                let _ = log.entries.append((g.size, state.peek.metrics.header?.resting ?? -1))
                Color.red
            }
        }
    }

    final class CommitLog { var entries: [(size: CGSize, committed: CGFloat)] = [] }

    struct GrowHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let log: CommitLog
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fit(min: 64)) { _ in GrowContent(model: model, log: log, state: state) }
        }
    }

    struct GrowContent: View {
        @ObservedObject var model: Model
        let log: CommitLog
        let state: ZTronScrollState
        var body: some View {
            Color.clear.aspectRatio(model.tall ? 4.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .overlay(CommitLogProbe(log: log, state: state))
        }
    }

    /// A `.fit` header content change inside the band (16:9 → 4:3 and back in an app animation; seam lab `grow`): the
    /// header keeps the committed `R`'s live height until the state commits the new `R`, in the content's own transaction
    /// with the inset (16+ `layoutResting`'s rule at the committed viewport; the 15 box's height fit), so header and
    /// content move together; then `R = W · 3 / 4` on both paths (before D78 the 15 path did not re-measure in the band).
    /// The commit keeps the drawn collapse (`R_new − q · (R_old − min)`) and the offset then restores the progress: the
    /// header's layouts go from that height to the new live height without a step back, the same sequence on both paths.
    @Test(arguments: OSPath.allCases, [CGFloat(0), 0.5])
    func aFitContentChangeInTheBandMovesWithTheCommit(path: OSPath, progress: CGFloat) {
        let log = CommitLog(), model = Model(), counts = BodyCount()
        let s = makeState(path)
        let w = withOSPath(path) { window(GrowHost(model: model, state: s, log: log, counts: counts)) }
        defer { unhost(w) }
        settle(s)
        guard s.peek.metrics.header != nil else { Issue.record("\(path): unresolved"); return }
        s.snapHeader(to: .progress(progress), animated: false)
        pump(0.3)
        s.endOfTurn()
        let W = s.peek.metrics.viewportSize.width
        for tall in [true, false] {
            log.entries.removeAll()
            let bodies = counts.bodies
            let old = s.peek.metrics.header?.resting ?? -1
            withAnimation(.easeInOut(duration: 0.5)) { model.tall = tall }
            for _ in 0..<40 { pump(1.0 / 60) }
            pump(0.4)
            s.endOfTurn()
            let tag = "\(path) q \(progress) tall \(tall)"
            let R = s.peek.metrics.header?.resting ?? -1
            #expect(abs(R - W * (tall ? 3.0 / 4.0 : 9.0 / 16.0)) < 0.5, "\(tag): R \(R) at \(W)")
            #expect(abs((s.headerGeometry?.progress ?? -1) - progress) < 0.01, "\(tag): progress kept")
            // Before the state commits the new R: the old R's live height (the header is never ahead of the commit).
            let before = (1 - progress) * old + progress * 64
            let ahead = log.entries.filter { abs($0.committed - R) > 0.5 && abs($0.size.height - before) > 0.5 }
            #expect(ahead.isEmpty, "\(tag): laid out ahead of the commit \(ahead) (all \(log.entries))")
            // From the commit: its height (the drawn collapse kept), then monotonic to the new live height.
            let commit = R - progress * (old - 64), end = (1 - progress) * R + progress * 64
            let after = log.entries.filter { abs($0.committed - R) <= 0.5 }.map(\.size.height)
            let stepBack = zip(after, after.dropFirst()).filter { end >= commit ? $1 < $0 - 0.5 : $1 > $0 + 0.5 }
            #expect(after.first.map { abs($0 - commit) < 0.5 } == true && after.last.map { abs($0 - end) < 0.5 } == true
                    && stepBack.isEmpty, "\(tag): \(commit) → \(end) expected, laid out \(after), steps back \(stepBack)")
            #expect(counts.bodies == bodies, "\(tag): content.body 0")
            print("D78 grow \(tag): R \(R), entries \(log.entries.map { "\($0.size.height)@\($0.committed)" })")
        }
    }

    // MARK: A runtime overflow change

    struct RelaxHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let log: CommitLog
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fit(min: 64), overflow: model.relaxed ? .uncapped : .capped(fraction: 0.25)) { _ in
                    GrowContent(model: model, log: log, state: state)
                }
        }
    }

    /// A runtime overflow change on a limited `.fit` header (`.capped(0.25)` ↔ `.uncapped` in an app animation, at rest and
    /// half collapsed): the state resolves the new `R` from its stored natural height in the spec change, and the header
    /// is laid out at the new `R`'s live height at once, on both paths (the 15 box reports the natural height unlimited,
    /// as 16+'s ideal-size query; with a limited report the relaxed `R` waited for the box's next report and was adopted
    /// as a content change, the drawn collapse kept, then animated back: 160.9 → 145.1 pt on 15, 145.0 at once on 16+).
    @Test(arguments: OSPath.allCases, [CGFloat(0), 0.5])
    func aRuntimeOverflowChangeFollowsTheSameSequence(path: OSPath, progress: CGFloat) {
        let log = CommitLog(), model = Model(), counts = BodyCount()
        let s = makeState(path)
        let w = withOSPath(path) { window(RelaxHost(model: model, state: s, log: log, counts: counts)) }
        defer { unhost(w) }
        settle(s)
        guard s.peek.metrics.header != nil else { Issue.record("\(path): unresolved"); return }
        s.snapHeader(to: .progress(progress), animated: false)
        pump(0.3)
        s.endOfTurn()
        let W = s.peek.metrics.viewportSize.width
        for relaxed in [true, false] {
            log.entries.removeAll()
            var rs: [CGFloat] = []
            withAnimation(.easeInOut(duration: 0.5)) { model.relaxed = relaxed }
            for _ in 0..<40 { pump(1.0 / 60); rs.append(s.peek.metrics.header?.resting ?? -1) }
            pump(0.4)
            s.endOfTurn()
            let tag = "\(path) q \(progress) relaxed \(relaxed)"
            let R = s.peek.metrics.header?.resting ?? -1
            let expected = relaxed ? W * 9 / 16 : 0.25 * committedContainer(s)
            #expect(abs(R - expected) < 0.5, "\(tag): R \(R), expected \(expected)")
            let firstNew = rs.firstIndex { abs($0 - R) < 0.5 }
            #expect(firstNew == 0, "\(tag): R adopted at frame \(String(describing: firstNew)) (\(rs.prefix(4)))")
            let end = (1 - progress) * R + progress * 64
            let atNew = log.entries.filter { abs($0.committed - R) <= 0.5 }.map(\.size.height)
            #expect(!atNew.isEmpty && atNew.allSatisfy { abs($0 - end) < 0.5 },
                    "\(tag): laid out at the new R's live height \(end) at once: \(atNew)")
            print("D78 relax \(tag): R \(R), first frame at R \(String(describing: firstNew)), Rs \(rs.prefix(4)), entries \(log.entries.prefix(3).map { "\($0.size.height)@\($0.committed)" }) … \(log.entries.suffix(2).map { "\($0.size.height)@\($0.committed)" }) (\(log.entries.count))")
        }
    }

    // MARK: Launch

    /// Samples at the end of every main run-loop turn, after Core Animation's commit (a `beforeWaiting` observer ordered
    /// after it): what that turn committed to the screen.
    @MainActor final class TurnSampler {
        var samples: [(height: CGFloat, width: CGFloat, resolved: Bool)] = []
        private let sample: () -> (CGFloat, CGFloat, Bool)
        private var observer: CFRunLoopObserver?
        init(_ sample: @escaping () -> (CGFloat, CGFloat, Bool)) {
            self.sample = sample
            observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 2_100_000) {
                [weak self] _, _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        private func tick() {
            let s = sample()
            samples.append((s.0, s.1, s.2))
        }
        func stop() { if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) } }
    }

    /// The header is in the FIRST committed frame at launch on both paths: at the end of every run-loop turn from the
    /// header's first layout on (after Core Animation's commit), the state has the header's metrics (the content's inset)
    /// and the header its height. The 15 measuring pass adopts its first measurement at once (deferred to the next
    /// run-loop turn, the first committed turn had neither the header nor its inset, at 7206175 too; seam lab, forced, one
    /// recording's first frame).
    @Test(arguments: OSPath.allCases, [ZTronHeaderSize.fit(min: 64), .fit(), .aspectRatio(16.0 / 9.0, min: 64)])
    func everyCommittedFrameFromTheFirstHasTheHeader(path: OSPath, size: ZTronHeaderSize) {
        let log = Log(), counts = BodyCount()
        let s = makeState(path)
        let sampler = TurnSampler { (log.last.height, log.last.width, s.peek.metrics.header != nil) }
        defer { sampler.stop() }
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 402, height: 874)))
            w.rootViewController = UIHostingController(rootView:
                ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                    .withScalingHeader(size: size) { _ in
                        Color.clear.aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .overlay(LogProbe(log: log))
                    })
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        pump(0.5)
        let drawn = sampler.samples.drop { $0.width <= 0 }
        let bad = drawn.filter { !$0.resolved || abs($0.height - 402 * 9 / 16) > 0.5 }
        #expect(!drawn.isEmpty && bad.isEmpty, "\(path) \(size): turns without the header \(bad.count) of \(drawn.count): \(drawn.prefix(8))")
        print("D78 turns \(path) \(size): \(drawn.count) turns, first \(drawn.prefix(4).map { "\($0.height)x\($0.resolved)" })")
    }

    // MARK: D76 `.keepTextSize` on the `.fit` box (M8b-s8 s7, i28 §4.8)

    /// A `.stretch` `.fit` header with `.keepTextSize` (16:9 content: `N(W) = W · 9 / 16`; 4:3 when `tall`), the header
    /// marker drawn by a size probe, under the content strip of `HeaderStretchScaleTests`.
    struct GrowFitHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let size: ZTronHeaderSize
        let overflow: ZTronHeaderOverflow
        let box: HeaderStretchScaleTests.Box
        let counts: BodyCount
        var refresher = false
        var body: some View {
            let v = ZTronScrollView(.vertical, state: state) { HeaderStretchScaleTests.Content(counts: counts) }
                .withScalingHeader(size: size, pull: .stretch, overflow: overflow, stretchContent: .keepTextSize) { _ in
                    GrowFitContent(model: model, box: box)
                }
            if refresher {
                v.refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20) }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
            } else {
                v
            }
        }
    }

    struct GrowFitContent: View {
        @ObservedObject var model: Model
        let box: HeaderStretchScaleTests.Box
        var body: some View {
            Color.clear.aspectRatio(model.tall ? 4.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .overlay(HeaderStretchScaleTests.SizeProbe(box: box))
        }
    }

    /// i28 §4.8, the four regimes of a pulled `.fit` (`N < m′`, `m′ ≤ N ≤ L`, `L < N ≤ s·L`, `N > s·L`): held at a 60 pt
    /// pull with `.keepTextSize`, the header content is laid out at 16+'s grown rect `(W · s, R + g)`, `s = (R + g) / R`,
    /// with `R` the committed one, and the natural height is still measured at the SLOT width (`N(402) = 226.125`, the
    /// state's natural and the synchronous record), never at the grown width; `R` does not change. Both paths (16+: the
    /// slot layout's ideal query; 15: the box's flexible ideal width).
    @Test(arguments: OSPath.allCases, [(ZTronHeaderSize.fit(min: 300), ZTronHeaderOverflow.uncapped),
                                       (.fit(min: 64), .uncapped), (.fit(min: 64), .capped(fraction: 0.25)),
                                       (.fit(min: 64), .capped(fraction: 0.15))])
    func aFitHeaderPulledMeasuresAtTheSlotWidth(path: OSPath, c: (ZTronHeaderSize, ZTronHeaderOverflow)) {
        let (size, overflow) = c
        let model = Model(), counts = BodyCount(), box = HeaderStretchScaleTests.Box()
        let s = makeState(path)
        let w = withOSPath(path) {
            window(GrowFitHost(model: model, state: s, size: size, overflow: overflow, box: box, counts: counts))
        }
        defer { unhost(w) }
        settle(s)
        guard let R = s.peek.metrics.header?.resting else { Issue.record("\(path) \(size): unresolved"); return }
        let tag = "\(path) \(size) \(overflow)"
        // The natural height at 402 pt; the 15 box reports it floored at `min` (D78: `max(N, m′)`), 16+ the raw `N`.
        let N: CGFloat = s.usesLayoutProtocol ? 402 * 9 / 16 : max(402 * 9 / 16, size.minimum)
        #expect(abs((s.headerNatural ?? -1) - N) < 0.5, "\(tag): natural \(String(describing: s.headerNatural)) at rest")
        let bodies = counts.bodies
        for g in [30, 60, 60] as [CGFloat] {
            s.track(offset: CGPoint(x: 0, y: -g - HeaderMath.base(s.peek.metrics)), zoom: 1)
            pump(0.15)
            let laid = CGSize(width: 402 * (R + g) / R, height: R + g)
            #expect(abs(box.size.width - laid.width) < 0.5 && abs(box.size.height - laid.height) < 0.5,
                    "\(tag) g \(g): laid out at \(box.size), 16+'s grown rect \(laid) (R \(R))")
            #expect(abs(box.global.midX - 201) < 0.5, "\(tag) g \(g): centred \(box.global)")
            #expect(abs((s.headerNatural ?? -1) - N) < 0.5, "\(tag) g \(g): natural \(String(describing: s.headerNatural))")
            if let live = s.headerNaturalLive {
                #expect(abs(live.width - 402) < 0.5 && abs(live.height - N) < 0.5,
                        "\(tag) g \(g): measured \(live) at the slot width")
            }
            #expect(abs((s.peek.metrics.header?.resting ?? -1) - R) < 0.01, "\(tag) g \(g): R kept")
            #expect(abs((s.headerGeometry?.stretch ?? -1) - g) < 0.5,
                    "\(tag) g \(g): stretch \(String(describing: s.headerGeometry)) resize open \(s.peek.metrics.resize.isOpen)")
        }
        s.track(offset: CGPoint(x: 0, y: -HeaderMath.base(s.peek.metrics)), zoom: 1)
        s.endOfTurn()
        pump(0.3)
        #expect(abs(box.size.width - 402) < 0.5 && abs(box.size.height - R) < 0.5, "\(tag): back to rest \(box.size)")
        #expect(abs((s.headerNatural ?? -1) - N) < 0.5, "\(tag): natural after \(String(describing: s.headerNatural))")
        #expect(counts.bodies == bodies, "\(tag): content.body 0")
        print("D76 fit pulled \(tag): R \(R) natural \(String(describing: s.headerNatural)) live \(String(describing: s.headerNaturalLive))")
    }

    /// i28 §4.8 / C7: a `.fit` header content change (16:9 → 4:3 and back, app-animated) during a 60 pt refresh hold with
    /// `.keepTextSize` is measured in layout (no measuring pass, no adoption at release): `R` and the natural height follow
    /// it while held, every drawn frame keeps the header's bottom edge on the content's top and the header at the slot's
    /// width, and the header is laid out at the grown rect of the new `R`. Both paths, no content body.
    @Test(arguments: OSPath.allCases)
    func aFitContentChangeDuringAHoldIsMeasuredInLayout(path: OSPath) {
        let model = Model(), counts = BodyCount(), box = HeaderStretchScaleTests.Box()
        let s = makeState(path)
        let w = withOSPath(path) {
            hostDriven(GrowFitHost(model: model, state: s, size: .fit(min: 64), overflow: .uncapped, box: box,
                                   counts: counts, refresher: true))
        }
        defer { unhost(w) }
        settle(s)
        s.beginRefreshing()
        pump(1.0)
        guard let g = s.headerGeometry?.stretch, g > 30 else {
            Issue.record("\(path): no hold (\(String(describing: s.headerGeometry)))"); return
        }
        let bodies = counts.bodies
        for tall in [true, false] {
            let tag = "\(path) tall \(tall)"
            withAnimation(.easeInOut(duration: 0.5)) { model.tall = tall }
            var worstSeam: CGFloat = 0, worstSide: CGFloat = 0, samples = 0
            for _ in 0..<45 {
                pump(1.0 / 60)
                let hf = HeaderStretchScaleTests.drawnFrames(of: HeaderStretchScaleTests.headerMarker, in: w, presented: true)
                let cf = HeaderStretchScaleTests.frames(of: HeaderStretchScaleTests.contentMarker, in: w, presented: true)
                guard let f = hf.first, let c = cf.first else { continue }
                samples += 1
                worstSeam = max(worstSeam, abs(f.maxY - c.minY))
                worstSide = max(worstSide, abs(f.minX), abs(f.maxX - 402))
            }
            pump(0.5)
            let N = 402 * (tall ? 3.0 / 4.0 : 9.0 / 16.0)
            let R = s.peek.metrics.header?.resting ?? -1
            #expect(abs(R - N) < 0.5, "\(tag): R \(R) follows the content while held")
            #expect(abs((s.headerNatural ?? -1) - N) < 0.5, "\(tag): natural \(String(describing: s.headerNatural))")
            #expect(abs((s.headerGeometry?.stretch ?? -1) - g) < 0.5, "\(tag): the hold kept")
            #expect(samples >= 30 && worstSeam < 1, "\(tag): seam \(worstSeam) over \(samples) frames")
            #expect(worstSide < 0.5, "\(tag): drawn at the slot's width (sides \(worstSide))")
            let laid = CGSize(width: 402 * (R + g) / R, height: R + g)
            #expect(abs(box.size.width - laid.width) < 0.5 && abs(box.size.height - laid.height) < 0.5,
                    "\(tag): laid out at \(box.size), the grown rect \(laid)")
            print("D76 fit hold grow \(tag): R \(R) seam \(worstSeam) sides \(worstSide) samples \(samples)")
        }
        #expect(counts.bodies == bodies, "\(path): content.body 0")
    }

    /// C18 (M8b-s8 s7): a text `.fit` header at a Dynamic Type size picked by the model.
    struct DynamicTypeHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let box: HeaderStretchScaleTests.Box
        let counts: BodyCount
        var body: some View {
            ZTronScrollView(.vertical, state: state) { HeaderStretchScaleTests.Content(counts: counts) }
                .withScalingHeader(size: .fit(min: 64), pull: .stretch, stretchContent: .keepTextSize) { _ in
                    Text("Header text that wraps over a few lines at the larger sizes of Dynamic Type")
                        .font(.body)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)   // the probe marks the header's whole rect
                        .background(HeaderStretchScaleTests.SizeProbe(box: box))
                }
                .refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20) }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
                .environment(\.sizeCategory, model.tall ? .accessibilityExtraLarge : .large)
        }
    }

    /// C18 (M8b-s8 s7): after the first metrics the measuring pass no longer re-arms on Dynamic Type: the box (D78, 15
    /// path) and the slot layout (16+) measure the new ideal height in layout, at rest and during a 60 pt `.keepTextSize`
    /// refresh hold (where the pass would measure at the grown width). `R` follows the text, the header is drawn at `R` at rest
    /// and at the grown rect of the new `R` while held, its bottom edge on the content's top. Both paths, no content body.
    @Test(arguments: OSPath.allCases)
    func aDynamicTypeChangeIsMeasuredInLayout(path: OSPath) {
        let model = Model(), counts = BodyCount(), box = HeaderStretchScaleTests.Box()
        let s = makeState(path)
        let w = withOSPath(path) { hostDriven(DynamicTypeHost(model: model, state: s, box: box, counts: counts)) }
        defer { unhost(w) }
        settle(s)
        guard let R0 = s.peek.metrics.header?.resting else { Issue.record("\(path): unresolved"); return }
        let bodies = counts.bodies
        // At rest.
        model.tall = true
        pump(0.5)
        let R1 = s.peek.metrics.header?.resting ?? -1
        #expect(R1 > R0 + 20, "\(path): R \(R0) -> \(R1) follows the larger text")
        #expect(abs((s.headerNatural ?? -1) - R1) < 0.5, "\(path): natural \(String(describing: s.headerNatural)) = R \(R1)")
        #expect(abs(box.size.width - 402) < 0.5 && abs(box.size.height - R1) < 0.5, "\(path): drawn \(box.size) at R \(R1)")
        // Back, then during a hold.
        model.tall = false
        pump(0.5)
        #expect(abs((s.peek.metrics.header?.resting ?? -1) - R0) < 0.5, "\(path): back to R \(R0)")
        s.beginRefreshing()
        pump(1.0)
        guard let g = s.headerGeometry?.stretch, g > 30 else {
            Issue.record("\(path): no hold (\(String(describing: s.headerGeometry)))"); return
        }
        model.tall = true
        var worstSeam: CGFloat = 0, samples = 0
        for _ in 0..<20 {
            pump(1.0 / 60)
            let hf = HeaderStretchScaleTests.drawnFrames(of: HeaderStretchScaleTests.headerMarker, in: w, presented: true)
            let cf = HeaderStretchScaleTests.frames(of: HeaderStretchScaleTests.contentMarker, in: w, presented: true)
            guard let f = hf.first, let c = cf.first else { continue }
            samples += 1
            worstSeam = max(worstSeam, abs(f.maxY - c.minY))
        }
        pump(0.3)
        let R2 = s.peek.metrics.header?.resting ?? -1
        #expect(abs(R2 - R1) < 0.5, "\(path): held, R \(R2) = the larger text's \(R1)")
        #expect(samples >= 10 && worstSeam < 1, "\(path): held, seam \(worstSeam) over \(samples) frames")
        let laid = CGSize(width: 402 * (R2 + g) / R2, height: R2 + g)
        #expect(abs(box.size.width - laid.width) < 0.5 && abs(box.size.height - laid.height) < 0.5,
                "\(path): held, laid out at \(box.size), the grown rect \(laid)")
        #expect(counts.bodies == bodies, "\(path): content.body 0")
        print("C18 dynamic type \(path): R \(R0) -> \(R1), held \(R2) seam \(worstSeam)")
    }
}
