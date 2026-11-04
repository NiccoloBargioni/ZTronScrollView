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

    // MARK: Launch

    /// The `.fit` header is drawn from the first frame at launch on both paths: it resolves and is laid out at the
    /// state's height within the first 60 Hz frame after the window shows (the measuring pass takes the first
    /// measurement while there are no metrics; its launch-time re-arming stays, D78: without it the 15 header was missing
    /// for 1–5 frames at launch, i15b spike C).
    @Test(arguments: OSPath.allCases, [ZTronHeaderSize.fit(min: 64), .fit(), .aspectRatio(16.0 / 9.0, min: 64)])
    func theHeaderIsLaidOutFromTheFirstFrames(path: OSPath, size: ZTronHeaderSize) {
        let log = Log(), counts = BodyCount()
        let s = makeState(path)
        ZTronRenderCounters.reset()
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
        var first: Int?
        for frame in 0..<30 {
            pump(1.0 / 60)
            if let g = s.headerGeometry, let m = s.peek.metrics.header, g.height > 0.5,
               abs(log.last.height - g.height) < 0.5, abs(log.last.width - s.peek.metrics.viewportSize.width) < 0.5 {
                #expect(abs(m.resting - 402 * 9 / 16) < 0.5, "\(path) \(size): R \(m.resting)")
                first = frame
                break
            }
        }
        #expect(first == 0, "\(path) \(size): the header laid out at its height at frame \(String(describing: first)) (log \(log.sizes.prefix(6)), frames \(ZTronRenderCounters.value("header.frame")))")
        print("D78 launch \(path) \(size): first frame \(String(describing: first)), sizes \(log.sizes.prefix(6))")
    }
}
