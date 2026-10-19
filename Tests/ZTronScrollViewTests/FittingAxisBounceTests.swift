import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// `.ztronScrollBounceBehavior(.always, axes: .horizontal)` on a zoom-enabled view whose content is exactly as wide as
/// the viewport (the user's 16:9 image tree: `Image.resizable().aspectRatio(contentMode: .fit).frame(width: proxy.size.width)`
/// inside a 16:9 box): a horizontal drag must rubber-band and the release must spring back (SPEC S6 "Bounce").
@MainActor
@Suite(.serialized)
struct FittingAxisBounceTests {
    @Test(arguments: OSPath.allCases) func alwaysBouncesAnAxisTheContentFits(path: OSPath) {
        let s = makeState(path)
        let d = ZoomDelegate()
        s.delegate = d
        var t: TimeInterval = 100
        s.now = { t }
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 390, height: 219),
                                   contentSize: CGSize(width: 390, height: 585), displayScale: 3))
        let c = withOSPath(path) { PanCoordinator(state: s, axes: [.horizontal, .vertical]) }
        c.settings.bounceX = .always                     // what the adapter writes from the environment key
        let o0 = s.contentOffset
        let env = c.environment()
        #expect(env.bouncesX && !env.boundsX.isScrollable && env.axes.contains(.horizontal), "\(env)")
        let start = CGPoint(x: 200, y: 100)
        c.handle(.touchDown(location: start, time: t, touchCount: 1))
        c.handle(.dragChanged(translation: CGSize(width: 60, height: 0), startLocation: start, time: t))
        #expect(s.contentOffset.x < o0.x - 10, "rubber band on the fitting axis: \(s.contentOffset) from \(o0)")
        #expect(s.contentOffset.y == o0.y)
        t += 0.3
        c.handle(.dragEnded(translation: CGSize(width: 60, height: 0), time: t, fallbackVelocity: nil))
        c.handle(.touchesEnded(time: t))
        #expect(s.isDecelerating, "spring back runs on the clock")
        while s.isClockRunning && t < 105 { t += 1.0 / 60; s.step(to: Date(timeIntervalSinceReferenceDate: t)) }
        #expect(abs(s.contentOffset.x - o0.x) < 1e-6 && s.phase == .idle, "\(s.contentOffset)")
    }

    /// Same tree with the default behavior: the fitting axis also bounces (`.automatic` = native: an enabled axis
    /// bounces even when its content fits), and `.basedOnSize` does not.
    @Test(arguments: OSPath.allCases) func automaticBouncesAndBasedOnSizeDoesNot(path: OSPath) {
        for (behavior, bounces) in [(BounceBehavior.automatic, true), (.basedOnSize, false)] {
            let s = makeState(path)
            s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(4))
            s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 390, height: 219),
                                       contentSize: CGSize(width: 390, height: 585), displayScale: 3))
            let c = withOSPath(path) { PanCoordinator(state: s, axes: [.horizontal, .vertical]) }
            c.settings.bounceX = behavior
            let o0 = s.contentOffset
            let start = CGPoint(x: 200, y: 100)
            c.handle(.touchDown(location: start, time: 100, touchCount: 1))
            c.handle(.dragChanged(translation: CGSize(width: 60, height: 0), startLocation: start, time: 100))
            #expect((s.contentOffset.x != o0.x) == bounces, "\(behavior): \(s.contentOffset) from \(o0)")
        }
    }
}
