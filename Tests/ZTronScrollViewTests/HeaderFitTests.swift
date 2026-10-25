import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Design M8b §3 test 9 (`.fit`: `HeaderLayout` on 16+, the measuring pass on 15 / forced, the same resting height as
/// `.aspectRatio`; `header.measure` ≤ 1 per width change and 0 per frame) and test 13's `.refreshable` on a header view.
/// The measurement is reported with `DispatchQueue.main.async` (never from inside a layout pass): the `.fit` test is
/// `async` and waits with `Task.sleep`, because a synchronous test is itself a main-queue job and `pump` cannot drain it.
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

    func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    @Test(arguments: OSPath.allCases) func fitMeasuresTheIdealHeightAtTheViewportWidth(path: OSPath) async {
        let s = makeState(path)
        let counts = BodyCount()
        ZTronRenderCounters.reset()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fit()) { _ in Picture() }, size: CGSize(width: 402, height: 874))
        }
        var waited = 0
        while s.peek.metrics.header == nil, waited < 20 { await wait(0.1); waited += 1 }
        guard let m = s.peek.metrics.header else {
            Issue.record("never resolved: natural=\(String(describing: s.headerNatural)) vp=\(s.peek.metrics.viewportSize) measure=\(ZTronRenderCounters.value("header.measure")) spec=\(String(describing: s.headerSpec)) frame=\(ZTronRenderCounters.value("header.frame")) builder=\(ZTronRenderCounters.value("header.builder"))")
            unhost(w)
            return
        }
        let width = s.peek.metrics.viewportSize.width
        #expect(abs(m.resting - width / (16.0 / 9.0)) < 0.5, ".fit of a 16:9 picture == .aspectRatio(16/9): \(m.resting) at \(width)")
        #expect(ZTronRenderCounters.value("header.measure") == 1, "one measurement at install")
        #expect(s.adjustedContentInset.top == HeaderMath.top0(s.peek.metrics) + m.resting)
        // Scrolling never measures.
        ZTronRenderCounters.reset()
        let base = HeaderMath.base(s.peek.metrics)
        for i in 1...60 { s.track(offset: CGPoint(x: 0, y: CGFloat(i) * 3 - base), zoom: 1); await wait(0.02) }
        await wait(0.2)
        #expect(ZTronRenderCounters.value("header.measure") == 0, "0 per frame")
        #expect(s.peek.metrics.header?.resting == m.resting)
        // A width change re-measures once; the inset changes discretely.
        s.setContentOffset(CGPoint(x: 0, y: -base), animated: false)
        await wait(0.1)
        w.frame = CGRect(x: 0, y: 0, width: 600, height: 874)
        await wait(0.8)
        guard let wide = s.peek.metrics.header else { Issue.record("lost the header"); unhost(w); return }
        let w2 = s.peek.metrics.viewportSize.width
        #expect(abs(wide.resting - w2 / (16.0 / 9.0)) < 0.5, "re-measured at the new width: \(wide.resting) at \(w2)")
        #expect(ZTronRenderCounters.value("header.measure") == 1, "one measurement per width change")
        #expect(s.headerGeometry?.progress == 0, "at rest stays at rest")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func refreshableOnAHeaderViewResolvesToTheTopEdge(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            window(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
                .withScalingHeader(size: .fixed(max: 200), scalingBehavior: .stretch) { _ in Color.red }
                .refreshable { }, size: CGSize(width: 402, height: 874))
        }
        #expect(s.refresh?.specs.keys.sorted { "\($0)" < "\($1)" } == [.top] && s.refresh?.specs[.top]?.style == .system)
        unhost(w)
    }
}
