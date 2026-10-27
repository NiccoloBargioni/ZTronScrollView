import SwiftUI
import Testing
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
}
