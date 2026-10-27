import SwiftUI
import Testing
@testable import ZTronScrollView

/// D64 (lead, 2026-10-27): the header's overflow container excludes the keyboard, so the system keyboard never changes `R`
/// or `min` (it did: a landscape `.capped(0.5)` header went 190.5 -> 89 pt with the keyboard up, and its dismissal opened
/// an 85-95 pt seam: the header's slot animated in the keyboard's animation, which never reaches the container's
/// `.transaction` hook, while the content's inset landed at once). The content's adjusted inset still includes the
/// keyboard (S8). Hosted tests cannot show a keyboard (the test host has no window scene), so these drive the state with
/// the reports `ViewportObserver` makes: the viewport (the frame ends at the keyboard's top, the bottom inset is the
/// keyboard's) and the keyboard probe (how far the keyboard reaches above the keyboard-free safe area). The seam lab
/// (`kbreal`, `kbrotate`) covers the real keyboard.
@MainActor
@Suite(.serialized)
struct HeaderKeyboardTests {
    static let landscape = ViewportMetrics(size: CGSize(width: 874, height: 402),
                                           safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62))
    /// The keyboard up in landscape: 224 pt from the bottom, 203 pt above the 21 pt keyboard-free safe area.
    static let keyboard = ViewportMetrics(size: CGSize(width: 874, height: 402),
                                          safeArea: EdgeInsets(top: 0, leading: 62, bottom: 224, trailing: 62))
    static let ext: CGFloat = 203

    func make(_ path: OSPath, overflow: ZTronHeaderOverflow = .capped(fraction: 0.5)) -> ZTronScrollState {
        let s = makeState(path)
        s.headerSpec = HeaderSizing(size: .aspectRatio(16.0 / 9.0, min: 64), behavior: .preserve, snap: .disabled,
                                    overflow: overflow)
        s.setViewport(Self.landscape)
        s.setContentSize(CGSize(width: 874, height: 3000))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        return s
    }

    /// 16+: the probe reports before the viewport in the same update (`ViewportObserver`); 15 / forced: one preference
    /// carries both (`ViewportMetrics.keyboard`).
    func report(_ s: ZTronScrollState, _ v: ViewportMetrics, keyboard k: CGFloat, combined: Bool) {
        if combined {
            var v = v
            v.keyboard = k
            s.setViewport(v)
        } else {
            s.setKeyboardExtension(k)
            s.setViewport(v)
        }
    }

    @Test(arguments: [(ZTronHeaderOverflow.capped(fraction: 0.5), CGFloat(190.5)), (.refit, 381), (.uncapped, 491.625)],
          [false, true])
    func theKeyboardNeverChangesTheRestingHeight(policy: (ZTronHeaderOverflow, CGFloat), combined: Bool) {
        let s = make(.preferred, overflow: policy.0)
        let r = policy.1
        #expect(s.peek.metrics.header?.resting == r)
        let rest = s.peek.targetOffset
        report(s, Self.keyboard, keyboard: Self.ext, combined: combined)
        let m = s.peek.metrics
        #expect(m.header?.resting == r && m.header?.min == 64, "R \(String(describing: m.header?.resting)) with the keyboard up")
        #expect(m.keyboardExtension == Self.ext)
        #expect(m.adjustedContentInset.bottom == 224, "the content's inset still lifts above the keyboard (S8)")
        #expect(m.adjustedContentInset.top == r)
        #expect(s.peek.targetOffset == rest, "at rest the content stays: \(s.peek.targetOffset) vs \(rest)")
        report(s, Self.landscape, keyboard: 0, combined: combined)
        #expect(s.peek.metrics.header?.resting == r && s.peek.metrics.adjustedContentInset.bottom == 21)
        #expect(s.peek.targetOffset == rest)
    }

    /// A probe report that reaches the state AFTER the viewport's (the order the 16+ observer does not rely on): the
    /// viewport commit resolves with the old extension, then the turn's end commits the probe and `R` is back.
    @Test func aLateProbeReportIsCommittedAtTheTurnsEnd() {
        let s = make(.preferred)
        s.setViewport(Self.keyboard)
        #expect(s.peek.metrics.header?.resting == 89, "the stale extension: the old container (402 - 224)")
        s.setKeyboardExtension(Self.ext)
        pump(0.05)
        #expect(s.peek.metrics.header?.resting == 190.5 && s.peek.metrics.keyboardExtension == Self.ext)
        #expect(s.peek.metrics.adjustedContentInset.bottom == 224)
    }

    /// The probe alone (no viewport report in the turn, e.g. a keyboard change that leaves the container's safe area):
    /// committed at the turn's end against the committed safe area.
    @Test func aProbeReportAloneIsCommitted() {
        let s = make(.preferred)
        s.setKeyboardExtension(10)
        #expect(s.peek.metrics.keyboardExtension == 0, "recorded only: the viewport report of the same update commits it")
        pump(0.05)
        #expect(s.peek.metrics.keyboardExtension == 10 && s.peek.metrics.header?.resting == 195.5)
    }

    /// App-provided safe areas (`.safeAreaInset`, bars) still count: the probe stays 0, so `R` follows them.
    @Test(arguments: [false, true]) func anAppSafeAreaStillCounts(combined: Bool) {
        let s = make(.preferred)
        var v = Self.landscape
        v.safeArea.bottom = 171
        report(s, v, keyboard: 0, combined: combined)
        #expect(s.peek.metrics.header?.resting == 115.5, "0.5 x (402 - 171)")
    }

    /// A rotation with the keyboard up (both reports change with the size): `R` is the new orientation's keyboard-free one.
    @Test(arguments: OSPath.allCases, [false, true]) func aRotationWithTheKeyboardUpResolvesWithoutIt(path: OSPath, combined: Bool) {
        let s = makeState(path)
        s.headerSpec = HeaderSizing(size: .aspectRatio(16.0 / 9.0, min: 64), behavior: .preserve, snap: .disabled,
                                    overflow: .capped(fraction: 0.5))
        let portrait = ViewportMetrics(size: CGSize(width: 402, height: 874),
                                       safeArea: EdgeInsets(top: 62, leading: 0, bottom: 336, trailing: 0))
        report(s, portrait, keyboard: 302, combined: combined)
        s.setContentSize(CGSize(width: 402, height: 3000))
        #expect(s.peek.metrics.header?.resting == 226.125, "portrait: 16:9 of 402 fits under 0.5 x 778")
        report(s, Self.keyboard, keyboard: Self.ext, combined: combined)
        #expect(s.peek.metrics.header?.resting == 190.5, "landscape: 0.5 x 381, the keyboard excluded")
        #expect(s.peek.metrics.adjustedContentInset.bottom == 224)
    }
}
