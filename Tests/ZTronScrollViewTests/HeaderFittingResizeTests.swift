import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// M8b-s8 fixer r2 (R1-RC1-1, -2, -3): a D75 shape animation that an app-animated resize opens mid-flight. Rows 5 -> 10
/// and back (0.5 s each), and an app-animated `WidthWrap` width change (0.6 s) on each leg. The width change does not
/// move the content vertically (rows of fixed height), so the content's drawn top moves on the rows' curve only: no
/// step at the resize's first frame, no reversal, no hold, and the same end as without the resize (the hosted rig's
/// pure curve: 21 frames, the largest step 0.071 of the change); a `.headerFollows` header rides on the content's top.
///
/// - `later`: the width change 0.15 s into the rows animation, in a later run-loop turn (the app's case). Before the fix
///   on 27.0 the resize's unanimated reflow cancelled the shape animation: 0.90 of the change in one frame on the grow
///   leg, the whole change on the shrink leg (the seam lab's `rtw0p15`). 17.5 composes it additively and passed.
/// - `sameTurnLater`: the same timing in the rows change's turn (the hosted rig does not drain the main queue during
///   `pump`, so the turn's origin is still the one from before the rows change): the resize's track interpolated the
///   content size the shape effects already animate, +145 pt (1.2 of the change) at the resize's first frame on both OSes.
/// - `sameTurn`: both changes in one turn, no delay.
extension HeaderFittingContentTests {
    enum Turn: String, CaseIterable, Sendable { case later, sameTurnLater, sameTurn }

    @Test(arguments: OSPath.allCases, Turn.allCases)
    func aResizeOpenedDuringARowsAnimationKeepsItsCurve(path: OSPath, turn: Turn) async {
        let delay = turn == .sameTurn ? 0 : 0.15
        for fitting in [ZTronHeaderFittingContent.headerPinned, .headerFollows] {
            let box = WidthBox()
            var setup = Setup()
            setup.width = box
            let r = host(path, fitting, setup: setup)
            defer { r.sampler.stop(); unhost(r.window) }
            pump(0.3)
            let pad5 = pad(r.state, contentHeight: 300)
            for (to, narrow) in [(10, true), (5, false)] {
                await drainMainQueue()
                let t0 = CACurrentMediaTime()
                r.sampler.tick(nil)
                withAnimation(.easeInOut(duration: 0.5)) { r.rows.n = to }
                if delay > 0 { pump(delay) }
                if turn == .later { await drainMainQueue() }
                withAnimation(.easeInOut(duration: 0.6)) { box.narrow = narrow }
                pump(1.2)
                let xs = r.sampler.since(t0)
                let tops = contentTops(xs)
                let c = Self.motion(tops)
                var steps: [String] = []
                for i in 1..<tops.count where abs(tops[i].v - tops[i - 1].v) > 0.05 {
                    steps.append(String(format: "%.0fms:%.1f", (tops[i].t - t0) * 1000, tops[i].v - tops[i - 1].v))
                }
                // The rows' direction: up while they grow (the slack shrinks), down while they shrink.
                let sign: CGFloat = to == 10 ? -1 : 1
                let reversals = zip(tops, tops.dropFirst()).filter { ($1.v - $0.v) * sign < -0.5 }.count
                let tag = "\(path) \(fitting) \(turn) rows->\(to)"
                #expect(c.maxStepFraction <= 0.15, "\(tag): content \(c); steps \(steps.joined(separator: " "))")
                #expect(reversals == 0, "\(tag): \(reversals) reversals; steps \(steps.joined(separator: " "))")
                #expect(abs(c.total - pad5) < 0.5, "\(tag): total \(c.total) vs \(pad5)")
                if fitting == .headerFollows {   // the lift's carriers take the same base: the header rides on the content
                    let seam = xs.compactMap { s in s.header.flatMap { h in s.content.map { abs(h - $0) } } }.max() ?? 0
                    #expect(seam <= 1, "\(tag): seam \(seam)")
                }
            }
        }
    }
}
