import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// M8b-s6: a refresh indicator during an open app-driven animated resize is moved from the committed placement to the
/// presented one at the drawn size (`RefreshResizeEffect`); the seam lab measures the frames (`-ZTronSeamHold 1`).
@Suite
struct RefreshResizeEffectTests {
    /// The seam lab's `.stretch` hold, width 402 → 241 pt: `aci.top` = 62 + R + 60 with R = W · 9/16.
    static func commit(open: Bool = true) -> ResizeCommit {
        var c = ResizeCommit()
        c.previous = .init(viewport: CGSize(width: 402, height: 874), contentSize: CGSize(width: 402, height: 4000),
                           insets: EdgeInsets(top: 62 + 226.125 + 60, leading: 0, bottom: 34, trailing: 0))
        c.current = .init(viewport: CGSize(width: 241, height: 874), contentSize: CGSize(width: 241, height: 4000),
                          insets: EdgeInsets(top: 62 + 135.5625 + 60, leading: 0, bottom: 34, trailing: 0))
        c.isOpen = open
        return c
    }

    @Test func theTopIndicatorFollowsThePresentedWidthAndHeaderInset() {
        let c = Self.commit()
        // At the drawn start size the committed placement is moved back to where the old geometry put it.
        let start = RefreshResizeEffect.delta(commit: c, edge: .top, baseFollowsInset: true, size: c.previous.viewport)
        #expect(abs(start.x - 80.5) < 1e-9 && abs(start.y - 90.5625) < 1e-9, "start: \(start)")
        let half = RefreshResizeEffect.delta(commit: c, edge: .top, baseFollowsInset: true,
                                             size: CGSize(width: 321.5, height: 874))
        #expect(abs(half.x - 40.25) < 1e-9 && abs(half.y - 45.28125) < 1e-9, "half way: \(half)")
        #expect(RefreshResizeEffect.delta(commit: c, edge: .top, baseFollowsInset: true, size: c.current.viewport) == .zero)
        // The leaf's move (region and box) is the cross term only; the region's the inset change along the edge.
        #expect(RefreshResizeEffect.crossDelta(commit: c, edge: .top, size: c.previous.viewport) == CGPoint(x: 80.5, y: 0))
        let region = RefreshResizeEffect.regionDelta(commit: c, edge: .top, baseFollowsInset: true, size: c.previous.viewport)
        #expect(region.x == 0 && abs(region.y - 90.5625) < 1e-9, "region: \(region)")
    }

    @Test func aPreservedHeadersBaseStaysAndAClosedCommitIsIdentity() {
        let c = Self.commit()
        let start = RefreshResizeEffect.delta(commit: c, edge: .top, baseFollowsInset: false, size: c.previous.viewport)
        #expect(start.y == 0 && abs(start.x - 80.5) < 1e-9, ".preserve .followContent: top0 kept, centred in the drawn width: \(start)")
        #expect(RefreshResizeEffect.delta(commit: Self.commit(open: false), edge: .top, baseFollowsInset: true,
                                          size: CGSize(width: 402, height: 874)) == .zero)
        #expect(RefreshResizeEffect.delta(commit: c, edge: .top, baseFollowsInset: true, size: .zero) == .zero)
    }

    /// A top-pinned height change 874 → 374 pt (the bottom inset 34 → 0): at the drawn start size the bottom edge is
    /// 500 pt lower, its base 34 pt higher.
    @Test func theBottomIndicatorFollowsThePresentedHeight() {
        var c = Self.commit()
        c.previous.viewport = CGSize(width: 241, height: 874)
        c.current.viewport = CGSize(width: 241, height: 374)
        c.current.insets.bottom = 0
        let start = RefreshResizeEffect.delta(commit: c, edge: .bottom, baseFollowsInset: true,
                                              size: CGSize(width: 241, height: 874))
        #expect(abs(start.y - 466) < 1e-9 && start.x == 0, "bottom: \(start)")
    }

    /// Open item 21: a headerless hold (`aci.top` = 62 + 60), the height animated 874 → 349.6 pt top-pinned. S7 keeps the
    /// visible centre, so at the committed (short) size the content's top edge is far above the base; at the drawn start
    /// size it is still in the gap. The box's far edge follows the drawn content edge (`boxDelta`, its region the base:
    /// `regionDelta` 0 here), at any drawn size; identity at the committed size and once closed.
    @Test func theBoxFollowsTheDrawnContentEdgeAndTheRegionTheBase() {
        var c = ResizeCommit()
        let insets = EdgeInsets(top: 62 + 60, leading: 0, bottom: 34, trailing: 0)
        c.previous = .init(viewport: CGSize(width: 402, height: 874), contentSize: CGSize(width: 402, height: 3000), insets: insets)
        c.current = .init(viewport: CGSize(width: 402, height: 349.6), contentSize: CGSize(width: 402, height: 3000), insets: insets)
        c.isOpen = true
        c.intent = ResizeMath.intent(offset: CGPoint(x: 0, y: -122), scale: 1, in: c.previous, header: 0, focus: .center,
                                     alignment: .top)
        let r = ResizeMath.resolve(size: c.current.viewport, offset: .zero, scale: 1, insetsAnimated: insets, commit: c,
                                   limits: ZoomLimits(), alignment: .top, paging: [])
        let draw = RefreshContentDraw(offset: r.offset, zoom: 1, limits: ZoomLimits(), alignment: .top, paging: [])
        func edgeAt(_ h: CGFloat) -> CGFloat {
            RefreshResizeEffect.contentEdge(.top, commit: c, draw: draw, size: CGSize(width: 402, height: h))
        }
        #expect(abs(edgeAt(874) - 122) < 1e-6, "drawn start: the content's top edge at the hold's rest (\(edgeAt(874)))")
        #expect(edgeAt(349.6) < 0, "committed: S7 took the gap off the viewport (\(edgeAt(349.6)))")
        for h in [874, 700, 500, 349.6] as [CGFloat] {
            let size = CGSize(width: 402, height: h)
            let box = RefreshResizeEffect.boxDelta(commit: c, edge: .top, baseFollowsInset: true, overlay: false, draw: draw,
                                                   size: size)
            #expect(abs(box.y - (edgeAt(h) - edgeAt(349.6))) < 1e-6 && box.x == 0, "\(h): box \(box)")
            #expect(RefreshResizeEffect.regionDelta(commit: c, edge: .top, baseFollowsInset: true, size: size) == .zero)
            // An overlay rests on its base: no move along the edge.
            #expect(RefreshResizeEffect.boxDelta(commit: c, edge: .top, baseFollowsInset: true, overlay: true, draw: draw,
                                                 size: size).y == 0)
        }
        var closed = c
        closed.isOpen = false
        #expect(RefreshResizeEffect.boxDelta(commit: closed, edge: .top, baseFollowsInset: true, overlay: false, draw: draw,
                                             size: CGSize(width: 402, height: 874)) == .zero)
    }

    /// The end edges: the region is the drawn viewport (its far side moves by layout), so its own move is the inset change
    /// only, and the box's move inside it is the rest of the base's.
    @Test func theRegionMovesByTheInsetChangeOnly() {
        var c = Self.commit()
        c.previous.viewport = CGSize(width: 241, height: 874)
        c.current.viewport = CGSize(width: 241, height: 374)
        c.current.insets.bottom = 0
        let size = CGSize(width: 241, height: 874)
        let region = RefreshResizeEffect.regionDelta(commit: c, edge: .bottom, baseFollowsInset: true, size: size)
        #expect(abs(region.y + 34) < 1e-9 && region.x == 0, "bottom region: the base 34 pt higher (\(region))")
        let overlay = RefreshResizeEffect.boxDelta(commit: c, edge: .bottom, baseFollowsInset: true, overlay: true, draw: nil,
                                                   size: size)
        #expect(abs(overlay.y - 500) < 1e-9, "bottom overlay box: with the drawn bottom (\(overlay))")
    }
}
