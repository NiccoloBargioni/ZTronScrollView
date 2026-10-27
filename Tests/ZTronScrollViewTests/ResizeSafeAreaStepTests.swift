import SwiftUI
import Testing
@testable import ZTronScrollView

/// M8b-s6 close (verifier probe vbottom): a bottom-pinned animated height change moves the scroll view's TOP off the top
/// safe area. SwiftUI reports the change in stages (seam lab, 27.0, height to 0.4 of the safe area's): the animated layout
/// with the new height and the OLD top inset (874 -> 373.3 pt, top 62, bottom 34 -> 0), then, in the first animated frame,
/// the top inset alone (373.3 -> 311.3, top 62 -> 0), drawn as a step of the extended frame (874 -> 812 at once), and the
/// bottom inset back as the animation ends (311.3 -> 345.3). The step is committed as a shift of the open transition
/// (`ZTronScrollState.isSafeAreaStep`, `ResizeMath.shifted`); as a new transition from the drawn snapshot the content
/// kept the old top inset under a frame that had lost it: 62 pt below the header, closing over the animation.
@MainActor
@Suite(.serialized)
struct ResizeSafeAreaStepTests {
    static func vp(_ h: CGFloat, top: CGFloat, bottom: CGFloat) -> ViewportMetrics {
        ViewportMetrics(size: CGSize(width: 402, height: h), safeArea: EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
    }

    func make(_ path: OSPath, overflow: ZTronHeaderOverflow, height: CGFloat = 874, top: CGFloat = 62) -> ZTronScrollState {
        let s = makeState(path)
        s.headerSpec = HeaderSizing(size: .aspectRatio(16.0 / 9.0, min: 64), behavior: .preserve, snap: .disabled, overflow: overflow)
        s.setViewport(Self.vp(height, top: top, bottom: 34))
        s.setContentSize(CGSize(width: 402, height: 2480))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        s.endOfTurn()
        return s
    }

    /// The drawn content's top edge in the drawn (extended) frame at `size`.
    func contentTop(_ s: ZTronScrollState, height: CGFloat) -> CGFloat {
        let c = s.peek.metrics.resize
        let r = ResizeMath.resolve(size: CGSize(width: 402, height: height), offset: s.peek.targetOffset, scale: s.peek.targetZoom,
                                   insetsAnimated: c.current.insets, commit: c, limits: s.zoomLimits,
                                   alignment: s.contentAlignment, paging: [])
        return r.pad.y - r.offset.y
    }

    @Test(arguments: OSPath.allCases, [ZTronHeaderOverflow.uncapped, .capped(fraction: 0.5)])
    func aTopSafeAreaStepDuringABottomPinnedHeightChangeKeepsTheContentOnTheHeader(path: OSPath, overflow: ZTronHeaderOverflow) {
        let s = make(path, overflow: overflow)
        let r0 = s.peek.metrics.header?.resting ?? -1
        // The animated layout: the new height with the old top inset.
        s.setViewport(Self.vp(373.3, top: 62, bottom: 0))
        #expect(s.peek.metrics.resize.isOpen)
        // The first animated frame: the top extension is dropped at once (a step of the drawn frame).
        s.setViewport(Self.vp(311.3, top: 0, bottom: 0))
        #expect(s.peek.metrics.resize.isOpen)
        let r1 = s.peek.metrics.header?.resting ?? -1
        let tag = "\(path) \(overflow)"
        #expect(overflow == .uncapped ? r1 == r0 : abs(r1 - 311.3 * 0.5) < 1e-9, "\(tag): R \(r0) -> \(r1)")
        // The drawn frame: its top is the safe-area frame's top from now on (no extension); its height runs from
        // 778 + 34 (the bottom extension animates away with the change) to 311.3, and the header (laid out at the
        // safe-area top) from R0 to R1 with the same curve value u.
        for u in [CGFloat(0), 0.001, 0.25, 0.5, 0.9, 1] {
            let drawn = 778 + (311.3 - 778) * u + 34 * (1 - u)
            let header = r0 + (r1 - r0) * u
            let top = contentTop(s, height: drawn)
            #expect(abs(top - header) < 1e-6, "\(tag) u \(u): content top \(top) vs header bottom \(header)")
        }
        // The bottom extension comes back as the animation ends (another step): the content stays.
        s.setViewport(Self.vp(345.3, top: 0, bottom: 34))
        #expect(abs(contentTop(s, height: 345.3) - r1) < 1e-6, "\(tag): after the end step \(contentTop(s, height: 345.3))")
    }

    /// 17.5 reports the bottom inset coming back at the end while the frame is still drawn without it (drawn at 303.85,
    /// then at 337.67 the next frame): that size keeps the track before the step (`ResizeCommit.stepFallback`), the
    /// next one is on the shifted track. Without the fallback the undrawn frame extrapolated past the end (t 1.07): a
    /// capped header's content 4.7 pt above it for one frame (seam lab, 17.5).
    @Test(arguments: OSPath.allCases)
    func aStepReportedBeforeItIsDrawnKeepsTheUndrawnFrameOnItsTrack(path: OSPath) {
        let s = make(path, overflow: .capped(fraction: 0.5))
        let r0 = s.peek.metrics.header?.resting ?? -1
        s.setViewport(Self.vp(373.3, top: 62, bottom: 0))
        s.setViewport(Self.vp(311.3, top: 0, bottom: 0))
        let r1 = s.peek.metrics.header?.resting ?? -1
        // The last frames of the animation, drawn without the bottom extension.
        for h in [CGFloat(313.0), 312.07, 311.52] { s.probe.record(s.peek.targetOffset, 1, size: CGSize(width: 402, height: h)) }
        s.setViewport(Self.vp(345.3, top: 0, bottom: 34))
        #expect(s.peek.metrics.resize.stepFallback?.size.height == 311.52)
        let u = (311.52 - 812) / (311.3 - 812)
        let undrawn = contentTop(s, height: 311.52), header = r0 + (r1 - r0) * u
        #expect(abs(undrawn - header) < 1e-6, "undrawn step frame: content top \(undrawn) vs header bottom \(header)")
        #expect(abs(contentTop(s, height: 345.3) - r1) < 1e-6, "drawn step: \(contentTop(s, height: 345.3)) vs \(r1)")
    }

    @Test func whetherTheLastDrawnSizeHoldsTheStep() {
        func sz(_ h: [CGFloat]) -> [CGSize] { h.map { CGSize(width: 402, height: $0) } }
        // 27.0, first animated frame: drawn 874 -> 811.82, then the top inset 62 -> 0 is reported (drawn).
        #expect(ZTronScrollState.stepDrawn(recent: sz([874, 811.82]), step: CGSize(width: 0, height: -62)))
        // 17.5, end of the change: 304.39 -> 303.85, then the bottom inset 0 -> 34.1 (not drawn yet).
        #expect(!ZTronScrollState.stepDrawn(recent: sz([305.1, 304.39, 303.85]), step: CGSize(width: 0, height: 34.1)))
        // 17.5, reverse: 3.9 pt bottom steps while the frame moves 8.6 pt per frame (not drawn yet), and the top
        // extension at the end (drawn).
        #expect(!ZTronScrollState.stepDrawn(recent: sz([717.9, 726.53, 735.12]), step: CGSize(width: 0, height: 3.9)))
        #expect(ZTronScrollState.stepDrawn(recent: sz([789.93, 791.71, 851.85]), step: CGSize(width: 0, height: 59.7)))
        #expect(ZTronScrollState.stepDrawn(recent: sz([874]), step: CGSize(width: 0, height: -62)), "no motion known: drawn")
    }

    /// The reverse change: the extended frame grows back to the full height, the top extension returns as a step at the
    /// end (811.8 -> 874, top 0 -> 62): the content is at the extension plus the header at once.
    @Test(arguments: OSPath.allCases)
    func theTopExtensionReturningAtTheEndIsAStep(path: OSPath) {
        let s = make(path, overflow: .uncapped, height: 345.3, top: 0)
        let r = s.peek.metrics.header?.resting ?? -1
        s.setViewport(Self.vp(778, top: 0, bottom: 0))
        #expect(abs(contentTop(s, height: 345.3) - r) < 1e-6)
        #expect(abs(contentTop(s, height: 600) - r) < 1e-6)
        s.setViewport(Self.vp(811.8, top: 0, bottom: 33.8))
        s.setViewport(Self.vp(874, top: 62, bottom: 34))
        #expect(abs(contentTop(s, height: 874) - (62 + r)) < 1e-6, "end: \(contentTop(s, height: 874)) vs \(62 + r)")
    }

    @Test func aRealResizeIsNotASafeAreaStep() {
        var a = ScrollMetrics(), b = ScrollMetrics()
        a.viewportSize = CGSize(width: 402, height: 373.3); a.safeAreaInsets = EdgeInsets(top: 62, leading: 0, bottom: 0, trailing: 0)
        b.viewportSize = CGSize(width: 402, height: 311.3); b.safeAreaInsets = EdgeInsets()
        #expect(ZTronScrollState.isSafeAreaStep(old: a, new: b, edges: .vertical))
        #expect(!ZTronScrollState.isSafeAreaStep(old: a, new: b, edges: []))
        b.viewportSize.height = 300
        #expect(!ZTronScrollState.isSafeAreaStep(old: a, new: b, edges: .vertical))
    }
}
