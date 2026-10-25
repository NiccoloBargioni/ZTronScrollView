import SwiftUI
import Testing
@testable import ZTronScrollView

/// SPEC S7 "Scaling header: keeps its collapse progress" (design M8b §2.4, test 10's `ResizeCommit.header`): a rotation keeps
/// `o′` at or above rest, the progress inside the band, and a collapsed header collapsed with the visible centre preserved
/// (the header captured at its minimum height). `.aspectRatio`'s new resting height enters the same commit.
@MainActor
@Suite(.serialized)
struct HeaderResizeTests {
    final class Clock { var t: TimeInterval = 100 }
    static let portrait = ViewportMetrics(size: CGSize(width: 402, height: 874), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
    static let landscape = ViewportMetrics(size: CGSize(width: 874, height: 402), safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62))

    func make(_ path: OSPath, size: ZTronHeaderSize, behavior: ZTronHeaderScalingBehavior = .preserve) -> (ZTronScrollState, Clock) {
        let clock = Clock()
        let s = makeState(path)
        s.now = { clock.t }
        s.headerSpec = HeaderSizing(size: size, behavior: behavior, snap: .disabled)
        s.setViewport(Self.portrait)
        s.setContentSize(CGSize(width: 402, height: 3000))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        return (s, clock)
    }

    func oPrime(_ s: ZTronScrollState) -> CGFloat {
        let p = s.peek
        return HeaderMath.headerOffset(offset: p.presentationOffset, zoom: p.presentationZoom, metrics: p.metrics)
    }

    func scroll(_ s: ZTronScrollState, oPrime x: CGFloat) {
        s.setContentOffset(CGPoint(x: 0, y: x - HeaderMath.base(s.peek.metrics)), animated: false)
    }

    /// A rotation as the container sees it: the viewport and the reflowed content in one turn, then frames until the
    /// resize closes (no transform effect renders here, so it closes as "never rendered").
    func rotate(_ s: ZTronScrollState, _ clock: Clock, to v: ViewportMetrics) {
        s.setViewport(v)
        s.setContentSize(CGSize(width: v.size.width, height: 3000))
        var n = 0
        while s.isClockRunning, n < 60 {
            clock.t += 1.0 / 60
            s.step(to: Date(timeIntervalSinceReferenceDate: clock.t))
            n += 1
        }
        s.endOfTurn()
    }

    /// The content point (y, unscaled) at the centre of the unobscured viewport below the live header.
    func visibleCentreY(_ s: ZTronScrollState) -> CGFloat {
        let p = s.peek, m = p.metrics
        let top = m.adjustedContentInset.top + HeaderMath.obscuredDelta(offset: p.presentationOffset, zoom: 1, metrics: m)
        let height = m.viewportSize.height - top - m.adjustedContentInset.bottom
        return p.presentationOffset.y + top + height / 2
    }

    @Test(arguments: OSPath.allCases) func aRotationInsideTheBandKeepsTheProgressAndTheNewRestingHeightJoinsTheCommit(path: OSPath) {
        let (s, clock) = make(path, size: .aspectRatio(16.0 / 9.0))
        #expect(s.peek.metrics.header?.resting == 226.125)
        scroll(s, oPrime: 226.125 * 0.4)
        let before = s.contentOffset
        rotate(s, clock, to: Self.landscape)
        #expect(s.peek.metrics.header?.resting == 491.625 && s.adjustedContentInset.top == 491.625, "R = W / r in the commit")
        #expect(abs((s.headerGeometry?.progress ?? -1) - 0.4) < 1e-9, "progress kept: \(String(describing: s.headerGeometry))")
        rotate(s, clock, to: Self.portrait)
        #expect(abs((s.headerGeometry?.progress ?? -1) - 0.4) < 1e-9)
        #expect(abs(s.contentOffset.y - before.y) < 1e-9, "the sticky intent restores the offset exactly")
    }

    @Test(arguments: OSPath.allCases) func aRotationAtRestStaysAtRest(path: OSPath) {
        let (s, clock) = make(path, size: .fixed(min: 64, max: 240))
        rotate(s, clock, to: Self.landscape)
        #expect(oPrime(s) == 0 && s.headerGeometry?.height == 240, "the header stays expanded, the content at its top")
    }

    @Test(arguments: OSPath.allCases) func aRotationWithTheHeaderCollapsedPreservesTheVisibleCentre(path: OSPath) {
        let (s, clock) = make(path, size: .fixed(min: 64, max: 240))
        scroll(s, oPrime: 1200)
        let centre = visibleCentreY(s)
        rotate(s, clock, to: Self.landscape)
        #expect(s.headerGeometry?.progress == 1, "still collapsed")
        #expect(abs(visibleCentreY(s) - centre) < 1, "the centre below the collapsed header is kept: \(visibleCentreY(s)) vs \(centre)")
    }

    @Test(arguments: OSPath.allCases) func aCollapsedHeaderStaysCollapsedNearTheTop(path: OSPath) {
        let (s, clock) = make(path, size: .fixed(min: 64, max: 240))
        rotate(s, clock, to: Self.landscape)
        scroll(s, oPrime: 180)
        rotate(s, clock, to: Self.portrait)
        #expect(s.headerGeometry?.progress == 1, "the centre rule would land above rest; collapsed is kept: \(oPrime(s))")
    }

    /// While a resize is open the presentation is the drawn offset of the interpolated geometry and the metrics are the new
    /// ones: readers read the target instead (found by a DEBUG rotation probe: a `.stretch` banner reported a 196 pt pull
    /// rotating back to portrait).
    @Test(arguments: OSPath.allCases) func whileAResizeIsOpenReadersSeeWhereItLands(path: OSPath) {
        let (s, clock) = make(path, size: .aspectRatio(16.0 / 9.0), behavior: .stretch)
        rotate(s, clock, to: Self.landscape)
        s.setViewport(Self.portrait)
        s.setContentSize(CGSize(width: 402, height: 3000))
        #expect(s.peek.metrics.resize.isOpen)
        #expect(s.headerGeometry?.stretch == 0 && s.headerGeometry?.height == 226.125, "\(String(describing: s.headerGeometry))")
        rotate(s, clock, to: Self.portrait)
        #expect(s.headerGeometry?.stretch == 0 && s.headerGeometry?.progress == 0)
    }
}
