import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// `FirstUseWarm` (fold review F1): an app's animated change made in its own appear action lands in the same update as the
/// warm-up's zero-duration transaction. The warm-up must not draw it: an ambient `withAnimation` `scroll(to:)` from the
/// app's `onAppear` (the "scroll to the initial item" idiom) runs its whole duration on both paths. Before the fix the
/// warm-up re-ran the content's drawing leaf (`TransformHost`) in its own transaction: the content jumped to the target
/// and the phase was `.idle` at the first sample. (Under a scaling header the same idiom is dropped on every build since
/// the tip: open item 64, so the header leaf's half, F2, has no appear-time row.)
@MainActor
@Suite(.serialized)
struct FirstUseWarmTests {
    /// The reviewer's probe: no header, 3000 pt of content, scrolled to 600 from the app's `onAppear` over 1.2 s.
    @Test(arguments: OSPath.allCases)
    func anAppearTimeAmbientScrollRunsItsDuration(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        var samples: [String] = []
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { Color.yellow.frame(height: 3000) }
                .onAppear { withAnimation(.linear(duration: 1.2)) { s.scroll(to: CGPoint(x: 0, y: 600)) } })
        }
        defer { unhost(w) }
        pump(0.05); samples.append("0.05 \(s.phase) y=\(s.contentOffset.y)")
        pump(0.25); samples.append("0.30 \(s.phase) y=\(s.contentOffset.y)")
        pump(0.30); samples.append("0.60 \(s.phase) y=\(s.contentOffset.y)")
        let mid = s.contentOffset.y
        #expect(s.phase == .animating && mid > 50 && mid < 550, "\(path): mid-animation at 0.6 s of 1.2 s: \(samples)")
        pump(1.2)
        #expect(s.phase == .idle && s.contentOffset.y == 600, "\(path): end \(s.phase) \(s.contentOffset.y)")
    }
}
