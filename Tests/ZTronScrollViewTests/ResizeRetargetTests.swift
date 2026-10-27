import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// Core check of M8b-s6 (unclamped `ResizeMath.progress`): a retarget of an animated resize while the first change is
/// still drawn in motion (a second `withAnimation` while the first runs) is composed by SwiftUI additively, so the drawn
/// size first keeps moving on the OLD track, past the snapshot the retarget commit starts from. When the new target is
/// near the drawn size, the commit's own chord has almost no viewport delta and the unclamped progress explodes (t down
/// to -175): every field that is not collinear with the old track (the bottom inset 34 -> 0 of a top-pinned height
/// change, a capped header's height) was extrapolated by hundreds of points. Outside its own span a retarget now
/// follows the old track (`ResizeCommit.outer`). These tests drive the real state (`setViewport`, the probe box the
/// effect records into) and SwiftUI's additive composition, simulated at 60 Hz with `.easeInOut(duration: 1.2)`.
@MainActor
@Suite(.serialized)
struct ResizeRetargetTests {
    /// SwiftUI's `.easeInOut` (cubic Bézier 0.42, 0, 0.58, 1) at the time fraction `x`.
    static func ease(_ x: Double) -> CGFloat {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var lo = 0.0, hi = 1.0
        for _ in 0..<60 {
            let s = (lo + hi) / 2
            let xs = 3 * (1 - s) * (1 - s) * s * 0.42 + 3 * (1 - s) * s * s * 0.58 + s * s * s
            if xs < x { lo = s } else { hi = s }
        }
        let s = (lo + hi) / 2
        return CGFloat(3 * (1 - s) * s * s + s * s * s)
    }

    static func vp(_ h: CGFloat, w: CGFloat = 402, top: CGFloat = 62, bottom: CGFloat) -> ViewportMetrics {
        ViewportMetrics(size: CGSize(width: w, height: h), safeArea: EdgeInsets(top: top, leading: 0, bottom: bottom, trailing: 0))
    }

    /// What the effect draws at `size`, recorded in the probe box as `ContentTransform.effectValue` does.
    @discardableResult
    static func draw(_ s: ZTronScrollState, _ size: CGSize) -> (offset: CGPoint, pad: CGPoint, presented: ResizeCommit.Snapshot) {
        let c = s.peek.metrics.resize
        let r = ResizeMath.resolve(size: size, offset: s.peek.targetOffset, scale: s.peek.targetZoom,
                                   insetsAnimated: c.current.insets, commit: c, limits: s.zoomLimits,
                                   alignment: s.contentAlignment, paging: [])
        s.probe.record(r.offset, r.scale, size: size)
        return (r.offset, r.pad, ResizeMath.presented(c, size: size))
    }

    /// A top-pinned height change 874 -> 373.2 (its bottom leaves the home indicator: inset 34 -> 0), retargeted `tr`
    /// seconds in to the drawn height + `eps` (inset 0 there); no header, content scrolled to the middle. Returns the
    /// worst offset error against the sticky intent realised in SwiftUI's additive geometry, the worst one-frame step of
    /// the drawn offset, and the presented bottom inset's range.
    func nearReversal(eps: CGFloat, tr: Double) -> (err: CGFloat, step: CGFloat, refStep: CGFloat, bottom: ClosedRange<CGFloat>) {
        let s = makeState(.preferred)
        s.setViewport(Self.vp(874, bottom: 34))
        s.setContentSize(CGSize(width: 402, height: 4000))
        s.track(offset: CGPoint(x: 0, y: 1500), zoom: 1)
        s.endOfTurn()
        let a: CGFloat = 874, b: CGFloat = 0.4 * 778 + 62
        let intent = ResizeMath.intent(offset: CGPoint(x: 0, y: 1500), scale: 1,
                                       in: .init(viewport: CGSize(width: 402, height: a), contentSize: CGSize(width: 402, height: 4000),
                                                 insets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)),
                                       header: 0, focus: .center, alignment: s.contentAlignment)
        Self.draw(s, CGSize(width: 402, height: a))
        s.setViewport(Self.vp(b, bottom: 0))
        var c: CGFloat?, k0 = 0
        var err: CGFloat = 0, step: CGFloat = 0, refStep: CGFloat = 0
        var last: CGFloat?, lastRef: CGFloat?
        var lo = CGFloat.infinity, hi = -CGFloat.infinity
        for k in 1...150 {
            let u1 = Self.ease(Double(k) / 60 / 1.2)
            var drawn = b + (a - b) * (1 - u1)
            if c == nil, Double(k) / 60 >= tr {
                c = drawn + eps; k0 = k
                s.setViewport(Self.vp(c!, bottom: 0))
            }
            if let c {
                let u2 = Self.ease(Double(k - k0) / 60 / 1.2)
                drawn = c + (b - c) * (1 - u2) + (a - b) * (1 - u1)
            }
            // The inset is 34 at `a` and 0 at `b` and `c`: additively, 34 (1 - u1).
            let d = Self.draw(s, CGSize(width: 402, height: drawn))
            let ref = ResizeMath.realize(intent, viewport: CGSize(width: 402, height: drawn),
                                         content: CGSize(width: 402, height: 4000),
                                         insets: EdgeInsets(top: 62, leading: 0, bottom: 34 * (1 - u1), trailing: 0),
                                         header: 0, focus: .center, limits: s.zoomLimits, alignment: s.contentAlignment)
            err = max(err, abs(d.offset.y - ref.offset.y))
            if let last { step = max(step, abs(d.offset.y - last)) }
            if let lastRef { refStep = max(refStep, abs(ref.offset.y - lastRef)) }
            last = d.offset.y; lastRef = ref.offset.y
            lo = min(lo, d.presented.insets.bottom); hi = max(hi, d.presented.insets.bottom)
        }
        return (err, step, refStep, lo...hi)
    }

    /// 810d101: t down to -175, the presented bottom inset to 3555 pt and errors of 194–654 pt (steps of 116 pt per frame
    /// in the hosted run). Main's clamp to [0, 1]: 10.9–15.5 pt; now 4.7–15.5 pt. The residual is the chord model inside
    /// the span (its far end is the new model value, not the drawn one).
    @Test(arguments: [(CGFloat(1), 0.5), (0.5, 0.25), (8, 0.5), (60, 0.5), (-0.5, 0.75)])
    func aRetargetNearTheDrawnSizeFollowsTheOldTrackWithoutAHeader(eps: CGFloat, tr: Double) {
        let r = nearReversal(eps: eps, tr: tr)
        print("RETARGET no header eps \(eps) tr \(tr): err \(r.err) step \(r.step) (SwiftUI \(r.refStep)) bottom \(r.bottom)")
        #expect(r.err < 20, "eps \(eps) tr \(tr): worst offset error \(r.err)")
        // The retarget's first frame inside its span takes the chord to the new model value (12.7 pt for a retarget 0.25 s
        // in, against SwiftUI's 2.9): the chord model's residual, as with main's clamp.
        #expect(r.step < 16, "eps \(eps) tr \(tr): worst one-frame step \(r.step) (SwiftUI's \(r.refStep))")
        #expect(r.bottom.lowerBound > -0.5 && r.bottom.upperBound < 34.5, "eps \(eps) tr \(tr): presented bottom inset \(r.bottom)")
    }

    /// The same change under a `.capped(0.5)` header (`.aspectRatio(16/9, min: 64)`, resting at the top): the content's
    /// top edge against the header's drawn bottom (SwiftUI's additive interpolation of the slot's R). 810d101: 448–516 pt;
    /// main's clamp: 45.6 pt; now 25.2 pt (14.7 pt for a retarget 60 pt from the drawn size, 810d101: 66 pt).
    @Test(arguments: [(CGFloat(1), 0.5), (0.5, 0.5), (60, 0.5)])
    func aRetargetNearTheDrawnSizeKeepsTheContentNearACappedHeader(eps: CGFloat, tr: Double) {
        let s = makeState(.preferred)
        s.headerSpec = HeaderSizing(size: .aspectRatio(16.0 / 9.0, min: 64), behavior: .preserve, snap: .disabled,
                                    overflow: .capped(fraction: 0.5))
        s.setViewport(Self.vp(874, bottom: 34))
        s.setContentSize(CGSize(width: 402, height: 2480))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        s.endOfTurn()
        func rr(_ h: CGFloat, bottom: CGFloat) -> CGFloat { min(402 * 9 / 16, 0.5 * (h - 62 - bottom)) }
        let a: CGFloat = 874, b: CGFloat = 0.4 * 778 + 62
        Self.draw(s, CGSize(width: 402, height: a))
        s.setViewport(Self.vp(b, bottom: 0))
        var c: CGFloat?, k0 = 0, worst: CGFloat = 0
        for k in 1...150 {
            let u1 = Self.ease(Double(k) / 60 / 1.2)
            var drawn = b + (a - b) * (1 - u1)
            var header = rr(b, bottom: 0) + (rr(a, bottom: 34) - rr(b, bottom: 0)) * (1 - u1)
            if c == nil, Double(k) / 60 >= tr {
                c = drawn + eps; k0 = k
                s.setViewport(Self.vp(c!, bottom: 0))
            }
            if let c {
                let u2 = Self.ease(Double(k - k0) / 60 / 1.2)
                drawn = c + (b - c) * (1 - u2) + (a - b) * (1 - u1)
                header = rr(c, bottom: 0) + (rr(b, bottom: 0) - rr(c, bottom: 0)) * (1 - u2)
                    + (rr(a, bottom: 34) - rr(b, bottom: 0)) * (1 - u1)
            }
            let d = Self.draw(s, CGSize(width: 402, height: drawn))
            worst = max(worst, abs(d.pad.y - d.offset.y - (62 + header)))
        }
        print("RETARGET capped eps \(eps) tr \(tr): worst seam \(worst)")
        #expect(worst < 30, "eps \(eps) tr \(tr): worst seam \(worst)")
    }

    /// The case the unclamped progress was made for (seam lab vretarget): the width change toggled back mid-flight is
    /// collinear with the first one, so its frames past the snapshot (t down to -47.6 for a toggle 0.05 s in) are exact,
    /// through the state's own commit path.
    @Test(arguments: [0.05, 0.1, 0.25, 0.5, 0.9])
    func aToggleBackMidFlightKeepsTheContentOnTheHeader(tr: Double) {
        let s = makeState(.preferred)
        s.headerSpec = HeaderSizing(size: .aspectRatio(16.0 / 9.0, min: 64), behavior: .preserve, snap: .disabled,
                                    overflow: .uncapped)
        s.setViewport(Self.vp(874, w: 402, bottom: 34))
        s.setContentSize(CGSize(width: 402, height: 4000))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        s.endOfTurn()
        func header(_ w: CGFloat) -> CGFloat { 62 + w * 9 / 16 }
        let a: CGFloat = 402, b: CGFloat = 241
        Self.draw(s, CGSize(width: a, height: 874))
        s.setViewport(Self.vp(874, w: b, bottom: 34))
        // The content takes the viewport's width (a reflow in the same transaction).
        s.setContentSize(CGSize(width: b, height: 4000))
        var k0: Int?, worst: CGFloat = 0
        for k in 1...200 {
            let u1 = Self.ease(Double(k) / 60 / 1.2)
            var w = b + (a - b) * (1 - u1)
            if k0 == nil, Double(k) / 60 >= tr {
                k0 = k
                s.setViewport(Self.vp(874, w: a, bottom: 34))
                s.setContentSize(CGSize(width: a, height: 4000))
            }
            if let k0 {
                let u2 = Self.ease(Double(k - k0) / 60 / 1.2)
                w = a + (b - a) * (1 - u2) + (a - b) * (1 - u1)
            }
            let d = Self.draw(s, CGSize(width: w, height: 874))
            worst = max(worst, abs(d.pad.y - d.offset.y - header(w)))
        }
        #expect(worst < 1e-6, "toggle back at \(tr) s: worst seam \(worst)")
    }

    /// Three retargets in a row, each to the drawn size + 1 pt: the old track is carried from commit to commit (the slope
    /// drawn at the retarget), never a 1 pt chord of the previous retarget.
    @Test func chainedRetargetsNearTheDrawnSizeStayOnTheTrack() {
        let s = makeState(.preferred)
        s.setViewport(Self.vp(874, bottom: 34))
        s.setContentSize(CGSize(width: 402, height: 4000))
        s.track(offset: CGPoint(x: 0, y: 1500), zoom: 1)
        s.endOfTurn()
        let a: CGFloat = 874, b: CGFloat = 0.4 * 778 + 62
        Self.draw(s, CGSize(width: 402, height: a))
        s.setViewport(Self.vp(b, bottom: 0))
        // Model values and start frames of the stacked animations (additive): drawn = last target + Σ residuals.
        var targets: [CGFloat] = [a, b], starts: [Int] = [0]
        var lo = CGFloat.infinity, hi = -CGFloat.infinity, step: CGFloat = 0, last: CGFloat?
        for k in 1...180 {
            var drawn = targets.last!
            for (i, k0) in starts.enumerated() {
                drawn += (targets[i] - targets[i + 1]) * (1 - Self.ease(Double(k - k0) / 60 / 1.2))
            }
            if [20, 30, 40].contains(k) {
                targets.append(drawn + 1); starts.append(k)
                s.setViewport(Self.vp(drawn + 1, bottom: 0))
                drawn = targets.last!
                for (i, k0) in starts.enumerated() {
                    drawn += (targets[i] - targets[i + 1]) * (1 - Self.ease(Double(k - k0) / 60 / 1.2))
                }
            }
            let d = Self.draw(s, CGSize(width: 402, height: drawn))
            lo = min(lo, d.presented.insets.bottom); hi = max(hi, d.presented.insets.bottom)
            if let last { step = max(step, abs(d.offset.y - last)) }
            last = d.offset.y
        }
        #expect(lo > -0.5 && hi < 34.5, "presented bottom inset \(lo)...\(hi)")
        #expect(step < 20, "worst one-frame step \(step)")
    }

    /// Outside its span a commit with an outer track continues from the nearer end along the old track's slope;
    /// inside it interpolates its own chord; both meet at the ends.
    @Test func theOuterTrackContinuesFromTheNearerEnd() {
        func snap(_ h: CGFloat, bottom: CGFloat, content: CGFloat) -> ResizeCommit.Snapshot {
            .init(viewport: CGSize(width: 402, height: h), contentSize: CGSize(width: 402, height: content),
                  insets: EdgeInsets(top: 62, leading: 0, bottom: bottom, trailing: 0))
        }
        var c = ResizeCommit()
        c.previous = snap(600, bottom: 20, content: 3000)
        c.current = snap(602, bottom: 0, content: 3000)
        c.outer = .init(previous: snap(874, bottom: 34, content: 4000), current: snap(374, bottom: 0, content: 2000))
        c.isOpen = true
        let at = { (h: CGFloat) in ResizeMath.presented(c, size: CGSize(width: 402, height: h)) }
        #expect(at(600).insets.bottom == 20 && at(602).insets.bottom == 0)
        #expect(abs(at(601).insets.bottom - 10) < 1e-9)                      // the chord inside the span
        #expect(abs(at(500).insets.bottom - (20 - 34 * 100 / 500)) < 1e-9)   // from `previous` on the old slope
        #expect(abs(at(500).contentSize.height - (3000 - 2000 * 100 / 500)) < 1e-9)
        #expect(abs(at(702).insets.bottom - (0 + 34 * 100 / 500)) < 1e-9)    // from `current` on the old slope
        // Past the end the line leaves the snapshots' range (a negative inset): kept within it.
        #expect(at(300).insets.bottom == 0 && at(4000).insets.bottom == 34 && at(4000).contentSize.height == 4000)
        // Without the outer track the 2 pt chord extrapolates: t = -50 there.
        c.outer = nil
        #expect(at(500).insets.bottom > 1000)
    }

    /// A sub-pixel track is not extrapolated: the effect is handed a pixel-rounded size (874.0 for 873.92).
    @Test func aSubPixelTrackIsNotExtrapolated() {
        let a = CGSize(width: 402, height: 873.9), b = CGSize(width: 402, height: 873.92)
        #expect(ResizeMath.progress(size: CGSize(width: 402, height: 874), from: a, to: b) == 1)
        #expect(ResizeMath.progress(size: CGSize(width: 402, height: 873), from: a, to: b) == 0)
        #expect(ResizeMath.rawProgress(size: CGSize(width: 402, height: 874), from: a, to: b) > 4.9)
    }
}

/// Core check of M8b-s6: the commit is copied into the transform effect (and the refresh indicator's resize effect) on
/// every evaluation and compared by SwiftUI. The M8b-s6 tracks (`stepFallback`, `outer`) are rare and sit behind one
/// immutable reference, so its inline layout is the one before them plus one pointer, with nothing after `isOpen` (D43:
/// no new inner padding in a value SwiftUI compares).
@Suite
struct ResizeCommitLayoutTests {
    @Test func theTracksAreOnePointerAndNothingFollowsIsOpen() {
        #expect(MemoryLayout<ResizeCommit.Tracks?>.size == MemoryLayout<Int>.size)
        let focus = MemoryLayout.offset(of: \ResizeCommit.focus)!
        let isOpen = MemoryLayout.offset(of: \ResizeCommit.isOpen)!
        #expect(isOpen == focus + MemoryLayout<UnitPoint>.size + MemoryLayout<Int>.size, "focus at \(focus), isOpen at \(isOpen)")
        #expect(MemoryLayout<ResizeCommit>.size == isOpen + 1, "size \(MemoryLayout<ResizeCommit>.size), isOpen at \(isOpen)")
        // Computed, not stored.
        #expect(MemoryLayout.offset(of: \ResizeCommit.stepFallback) == nil && MemoryLayout.offset(of: \ResizeCommit.outer) == nil)
    }

    @Test func theTracksAreValuesAndEqualByContents() {
        var a = ResizeCommit(), b = ResizeCommit()
        let s = ResizeCommit.Snapshot(viewport: CGSize(width: 1, height: 2))
        a.outer = .init(previous: s, current: s)
        #expect(a != b)
        b.outer = .init(previous: s, current: s)
        #expect(a == b)                         // two boxes, equal contents
        var c = a
        c.outer = nil
        #expect(c.outer == nil && a.outer != nil && c == ResizeCommit())   // a write never reaches a copy
        a.stepFallback = .init(size: .zero, previous: s, current: s, outer: nil)
        a.outer = nil
        #expect(a.stepFallback != nil && a.outer == nil)
    }
}
