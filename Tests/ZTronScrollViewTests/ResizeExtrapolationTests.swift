import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// M8b-s6 close (verifier probes vspring / vretarget): SwiftUI interpolates the container and the header's slot in one
/// curve value that leaves [0, 1] — a spring overshoots the target, a retargeted change (a second `withAnimation` while the
/// first runs) is composed additively and first keeps moving past the second commit's snapshot. The drawn content must
/// follow the same line (`ResizeMath.progress` extrapolates); clamped, it sat at the end geometry while the header overshot
/// (seam lab: 14.5 pt seam, 13 pt lateral) or froze at the snapshot while the header kept moving (23 pt).
@MainActor
@Suite
struct ResizeExtrapolationTests {
    /// The seam lab at rest, `.aspectRatio(16/9, min: 64)`, width 402 -> 241 pt (content as wide as the viewport).
    static let top0: CGFloat = 62
    static func r(_ w: CGFloat) -> CGFloat { w * 9 / 16 }
    static func snap(_ w: CGFloat) -> ResizeCommit.Snapshot {
        .init(viewport: CGSize(width: w, height: 874), contentSize: CGSize(width: w, height: 4000),
              insets: EdgeInsets(top: top0 + r(w), leading: 0, bottom: 34, trailing: 0),
              header: HeaderResize(base: top0 + r(w), band: r(w) - 64))
    }

    static func commit(from a: ResizeCommit.Snapshot, to b: ResizeCommit.Snapshot, intent: ResizeIntent) -> ResizeCommit {
        var c = ResizeCommit()
        c.previous = a; c.current = b; c.intent = intent; c.isOpen = true
        return c
    }

    /// The drawn content's top edge and width at `width` (x_v = s·x_c + pad − o).
    static func drawn(_ c: ResizeCommit, width: CGFloat) -> (top: CGFloat, left: CGFloat, width: CGFloat) {
        let size = CGSize(width: width, height: 874)
        let r = ResizeMath.resolve(size: size, offset: .zero, scale: 1, insetsAnimated: c.current.insets, commit: c,
                                   limits: ZoomLimits(), alignment: .center, paging: [])
        let k = ResizeMath.presented(c, size: size).contentSize
        return (r.pad.y - r.offset.y, r.pad.x - r.offset.x, k.width * r.scale)
    }

    /// The header's bottom edge as SwiftUI draws it at `width`: its slot top at `top0`, its height interpolated linearly
    /// (R is linear in W here, so the curve value and the width give the same line).
    static func headerBottom(width: CGFloat) -> CGFloat { top0 + r(width) }

    static let intent = ResizeMath.intent(offset: CGPoint(x: 0, y: -(top0 + r(402))), scale: 1, in: snap(402), header: 0,
                                          focus: .center, alignment: .center)

    @Test func aSpringOvershootKeepsTheContentOnTheHeader() {
        #expect(Self.intent.header == .top(0))
        let c = Self.commit(from: Self.snap(402), to: Self.snap(241), intent: Self.intent)
        // t = 1.08 and 1.2 (narrower than the target), and -0.1 (a spring's first frames never go below 0; kept anyway).
        for w in [CGFloat(228), 208.8, 418.1, 321.5, 241, 402] {
            let d = Self.drawn(c, width: w)
            #expect(abs(d.top - Self.headerBottom(width: w)) < 1e-6, "w \(w): content top \(d.top) vs header bottom \(Self.headerBottom(width: w))")
            #expect(abs(d.left) < 1e-6 && abs(d.width - w) < 1e-6, "w \(w): content x \(d.left) width \(d.width)")
        }
    }

    @Test func aRetargetedChangeKeepsTheContentOnTheHeaderPastTheSnapshot() {
        let first = Self.commit(from: Self.snap(402), to: Self.snap(241), intent: Self.intent)
        // Toggled back after 30 % of the first change: the snapshot is the presented geometry at that size; SwiftUI's
        // additive composition then first keeps narrowing (t < 0 of the second commit) before it turns back.
        let w0: CGFloat = 402 - 0.3 * 161
        let snapshot = ResizeMath.presented(first, size: CGSize(width: w0, height: 874))
        let second = Self.commit(from: snapshot, to: Self.snap(402), intent: Self.intent)
        for w in [w0, w0 - 10, w0 - 60, 260, w0 + 20, 402] {
            let d = Self.drawn(second, width: w)
            #expect(abs(d.top - Self.headerBottom(width: w)) < 1e-6, "w \(w): content top \(d.top) vs header bottom \(Self.headerBottom(width: w))")
            #expect(abs(d.left) < 1e-6 && abs(d.width - w) < 1e-6, "w \(w): content x \(d.left) width \(d.width)")
        }
    }

    @Test func progressIsNotClamped() {
        let a = CGSize(width: 402, height: 874), b = CGSize(width: 241, height: 874)
        #expect(abs(ResizeMath.progress(size: CGSize(width: 228, height: 874), from: a, to: b) - 174.0 / 161) < 1e-12)
        #expect(abs(ResizeMath.progress(size: CGSize(width: 418.1, height: 874), from: a, to: b) + 0.1) < 1e-12)
        #expect(ResizeMath.progress(size: a, from: a, to: a) == 1)
    }
}
