import Foundation
import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// D22 (user report 2026-10-19: "double tap to zoom animates, then snaps before the interpolation completes"): the
/// progress spring (0…1) was settled with the point thresholds (0.5 pt, 10 pt/s) read as progress units, i.e. at about
/// 50 % after ~150 ms, and the settle branch then wrote the end values at once. The thresholds now scale with the
/// animation's screen travel, so the zoom glides to the end.
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
        #expect(maxStep < 0.15 * delta, "no frame jumps more than 15 % of the way (the snap was ~50 %): \(maxStep / delta)")
        #expect(zooms[zooms.count - 1] - zooms[zooms.count - 2] < 0.01 * delta, "the last frame is a glide, not a snap")
        #expect(zooms.count >= 19, "the animation lasts at least 0.3 s: \(zooms.count - 1) frames")
    }
}
