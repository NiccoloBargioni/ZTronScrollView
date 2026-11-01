import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Design M8b §3 test 9 (`.fit`: `HeaderLayout` on 16+, the measuring pass on 15 / forced, the same resting height as
/// `.aspectRatio`; `header.measure` ≤ 1 per width change and 0 per frame) and test 13's `.refreshable` on a header view.
/// Synchronous on purpose: an async test suspends and lets other suites run while its hosted window renders, which
/// disturbed their global counters (ChromeLeafTests, 17.5 full run); the report is a run-loop block, so `pump` drains it.
@MainActor
@Suite(.serialized)
struct HeaderFitTests {
    func window<V: View>(_ view: V, size: CGSize) -> UIWindow {
        let w = UIWindow(frame: CGRect(origin: .zero, size: size))
        w.rootViewController = UIHostingController(rootView: view)
        w.makeKeyAndVisible()
        pump(0.4)
        return w
    }

    /// A 16:9 picture's stand-in: an ideal height at any width, flexible otherwise.
    struct Picture: View {
        var body: some View {
            Color.purple.aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @Test(arguments: OSPath.allCases) func fitMeasuresTheIdealHeightAtTheViewportWidth(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fit()) { _ in Picture() }, size: CGSize(width: 402, height: 874))
        }
        var waited = 0
        while s.peek.metrics.header == nil, waited < 20 { pump(0.1); waited += 1 }
        guard let m = s.peek.metrics.header else {
            Issue.record("never resolved: natural=\(String(describing: s.headerNatural)) vp=\(s.peek.metrics.viewportSize) measure=\(ZTronRenderCounters.value("header.measure")) spec=\(String(describing: s.headerSpec)) frame=\(ZTronRenderCounters.value("header.frame")) builder=\(ZTronRenderCounters.value("header.builder"))")
            unhost(w)
            return
        }
        let width = s.peek.metrics.viewportSize.width
        #expect(abs(m.resting - width / (16.0 / 9.0)) < 0.5, ".fit of a 16:9 picture == .aspectRatio(16/9): \(m.resting) at \(width)")
        #expect(s.headerMeasurements == 1, "one measurement at install")
        #expect(s.adjustedContentInset.top == HeaderMath.top0(s.peek.metrics) + m.resting)
        // Scrolling never measures. (The state's own count.)
        let base = HeaderMath.base(s.peek.metrics)
        for i in 1...60 { s.track(offset: CGPoint(x: 0, y: CGFloat(i) * 3 - base), zoom: 1); pump(0.02) }
        pump(0.2)
        #expect(s.headerMeasurements == 1, "0 per frame")
        #expect(s.peek.metrics.header?.resting == m.resting)
        // A width change re-measures once; the inset changes discretely.
        s.setContentOffset(CGPoint(x: 0, y: -base), animated: false)
        pump(0.1)
        w.frame = CGRect(x: 0, y: 0, width: 600, height: 874)
        pump(0.8)
        guard let wide = s.peek.metrics.header else { Issue.record("lost the header"); unhost(w); return }
        let w2 = s.peek.metrics.viewportSize.width
        #expect(abs(wide.resting - w2 / (16.0 / 9.0)) < 0.5, "re-measured at the new width: \(wide.resting) at \(w2)")
        #expect(s.headerMeasurements == 2, "one measurement per width change")
        #expect(s.headerGeometry?.progress == 0, "at rest stays at rest")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func refreshableOnAHeaderViewResolvesToTheTopEdge(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fixed(max: 200), pull: .stretch) { _ in Color.red }
                .refreshable { }, size: CGSize(width: 402, height: 874))
        }
        #expect(s.refresh?.specs.keys.sorted { "\($0)" < "\($1)" } == [.top] && s.refresh?.specs[.top]?.style == .system)
        unhost(w)
    }
}
