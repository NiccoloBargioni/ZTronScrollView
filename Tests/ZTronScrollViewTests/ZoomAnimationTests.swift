import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// D22 (user report 2026-10-19: "double tap to zoom animates, then snaps before the interpolation completes"): the
/// progress spring (0…1) was settled with the point thresholds (0.5 pt, 10 pt/s) read as progress units, i.e. at about
/// 50 % after ~150 ms, and the settle branch then wrote the end values at once. The animation now is native's
/// fixed-duration ease-in-out (`ZoomTiming`, docs/design/PHYSICS-calibration.md "Programmatic zoom").
@MainActor
@Suite(.serialized)
struct ZoomAnimationTests {
    @Test(arguments: OSPath.allCases) func animatedZoomGlidesToTheEndWithoutASnap(path: OSPath) {
        let s = makeState(path)
        var t: TimeInterval = 100
        s.now = { t }
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(8))
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 300, height: 360), contentSize: CGSize(width: 600, height: 600), displayScale: 2))
        s.track(offset: .zero, zoom: 1)
        // The double tap's zoom(to:) for 8x around the content point (300, 322.5): a 37.5 x 45 rect.
        s.zoom(to: CGRect(x: 300 - 18.75, y: 322.5 - 22.5, width: 37.5, height: 45), animated: true)
        #expect(s.phase == .animating && s.isClockRunning)
        var zooms: [CGFloat] = [s.zoomScale]
        while s.isClockRunning && t < 110 {
            t += 1.0 / 60
            s.step(to: Date(timeIntervalSinceReferenceDate: t))
            zooms.append(s.zoomScale)
        }
        let z1 = zooms[zooms.count - 1], delta = z1 - 1
        #expect(abs(z1 - 8) < 1e-9 && s.phase == .idle, "ends at the target: \(z1)")
        var maxStep: CGFloat = 0
        for i in 1..<zooms.count {
            #expect(zooms[i] >= zooms[i - 1] - 1e-12, "monotonic")
            maxStep = max(maxStep, zooms[i] - zooms[i - 1])
        }
        #expect(maxStep < 0.1 * delta, "no frame jumps more than 10 % of the way (the snap was ~50 %, ease-in-out peaks at 6.3 %): \(maxStep / delta)")
        #expect(zooms[zooms.count - 1] - zooms[zooms.count - 2] < 0.02 * delta, "the last frame is a glide, not a snap")
        #expect((22...26).contains(zooms.count - 1), "native: 0.40 s for an 8× ratio = 24 frames: \(zooms.count - 1)")
        #expect(abs(zooms[12] - (1 + delta * 0.5)) < 0.05 * delta, "ease-in-out: half way at half time")
    }

    /// Back out with `setZoomScale(1, animated: true)` from 8× (0.40 s) and a 2× zoom (0.32 s): native durations.
    @Test(arguments: OSPath.allCases) func zoomDurationsFollowTheNativeRatioLaw(path: OSPath) {
        let s = makeState(path)
        var t: TimeInterval = 100
        s.now = { t }
        s.zoomLimits = ZoomLimits(min: .absolute(1), max: .absolute(8))
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 300, height: 360), contentSize: CGSize(width: 600, height: 600), displayScale: 2))
        s.track(offset: CGPoint(x: 1050, y: 1260), zoom: 8)
        func frames(_ run: () -> Void) -> Int {
            run()
            var n = 0
            while s.isClockRunning && t < 110 { t += 1.0 / 60; s.step(to: Date(timeIntervalSinceReferenceDate: t)); n += 1 }
            return n
        }
        let back = frames { s.setZoomScale(1, animated: true) }
        #expect((22...26).contains(back) && s.zoomScale == 1 && s.phase == .idle, "8 -> 1: \(back) frames")
        let twice = frames { s.setZoomScale(2, animated: true) }
        #expect((18...21).contains(twice) && s.zoomScale == 2 && s.phase == .idle, "1 -> 2: 0.32 s = \(twice) frames")
    }
}
