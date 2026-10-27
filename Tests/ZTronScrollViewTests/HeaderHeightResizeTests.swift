import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// M8b-s6 (close of the seamless header): an app-driven animated HEIGHT change that engages the overflow limit (D59).
/// A top-pinned scroll view that gets shorter leaves the home indicator: its bottom safe-area inset goes 34 → 0 in the
/// same layout pass as its new height. The header slot's overflow container must come from that layout (the slot is
/// proposed the region between the safe areas), not from the committed bottom inset: with the committed inset the
/// animated pass resolved `capped(0.5)` against `H − 34` (138.6 pt) and the unanimated resize commit re-set the frame to
/// 155.6 pt without animation (seam lab, review d16: 70 pt one-frame step on 27.0, 17 pt overlap on 17.5).
@MainActor
@Suite(.serialized)
struct HeaderHeightResizeTests {
    typealias Log = HeaderReviewD16Tests.Log
    typealias LogProbe = HeaderReviewD16Tests.LogProbe

    final class Model: ObservableObject {
        @Published var short = false
    }

    /// The seam lab's `-ZTronSeamAnimateHeight <f>`: the scroll view's height animates to `f` of the safe area's,
    /// top-pinned (its top stays under the status bar, its bottom leaves the home indicator).
    struct HeightHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let overflow: ZTronHeaderOverflow
        let factor: CGFloat
        let start: CGFloat
        let log: Log
        var body: some View {
            GeometryReader { g in
                ZTronScrollView(.vertical, state: state) { Color.green.frame(height: 4000) }
                    .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), overflow: overflow) { _ in LogProbe(log: log) }
                    .frame(width: g.size.width, height: g.size.height * (model.short ? factor : start))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    struct Run {
        var log: Log
        var state: ZTronScrollState
        /// The resting heights before and after, and the expected one after (the D59 limit of the new container).
        var before: CGFloat
        var after: CGFloat
    }

    func animateHeight(path: OSPath, overflow: ZTronHeaderOverflow, factor: CGFloat, start: CGFloat = 1) -> Run {
        let log = Log(), model = Model()
        let s = makeState(path)
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: HeightHost(model: model, state: s, overflow: overflow,
                                                                           factor: factor, start: start, log: log))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        pump(0.3)
        s.endOfTurn()
        let before = s.peek.metrics.header?.resting ?? -1
        log.sizes.removeAll()
        withAnimation(.linear(duration: 0.5)) { model.short.toggle() }
        for _ in 0..<40 { pump(1.0 / 60) }
        pump(0.4)
        return Run(log: log, state: s, before: before, after: s.peek.metrics.header?.resting ?? -1)
    }

    /// The committed container after the change and the D59 limit on it.
    func limit(_ s: ZTronScrollState, _ overflow: ZTronHeaderOverflow) -> CGFloat {
        let m = s.peek.metrics
        let container = HeaderMath.containerHeight(viewport: m.viewportSize, safe: m.safeAreaInsets, adjusted: .vertical)
        switch overflow {
        case let .capped(f): return container * f
        case .refit: return container
        case .uncapped: return .infinity
        }
    }

    /// 16+: every frame the header is laid out at after the change is the final, limited `R` (the animated pass already
    /// has it; the commit changes nothing in the layout). 15 / forced: the documented limit F6 (SPEC S10, an
    /// overflow-limited `R` is the state's in the animated pass) is measured in the seam lab, not here: its animated pass
    /// keeps the old frame, which a model-frame log cannot tell from a correct one.
    @Test(arguments: [ZTronHeaderOverflow.capped(fraction: 0.5), .refit], [CGFloat(0.4), 0.25])
    func anAnimatedHeightChangeThatEngagesTheLimitIsFinalInTheAnimatedPass(overflow: ZTronHeaderOverflow, factor: CGFloat) {
        let r = animateHeight(path: .preferred, overflow: overflow, factor: factor)
        let tag = "\(overflow) f \(factor)"
        let expected = min(402 * 9 / 16, limit(r.state, overflow))
        #expect(abs(r.after - expected) < 0.5, "\(tag): committed R \(r.after) vs the limit \(expected)")
        // The bottom safe-area inset left the scroll view with the change (its bottom is far above the home indicator).
        #expect(r.state.peek.metrics.safeAreaInsets.bottom < 0.5, "\(tag): bottom inset \(r.state.peek.metrics.safeAreaInsets.bottom)")
        let stale = r.log.sizes.filter { abs($0.height - r.after) > 0.5 }
        #expect(stale.isEmpty, "\(tag): header laid out at \(stale) before the final \(r.after) (R before \(r.before); all: \(r.log.sizes))")
        #expect(abs(r.log.last.height - r.after) < 0.5, "\(tag): final frame \(r.log.last) vs R \(r.after)")
    }

    /// The reverse change (short → full height: the bottom inset comes back, 0 → 34) is final in the animated pass too,
    /// and a change that does not engage the limit (capped 0.6: 233 pt > 226 pt) never moves the header.
    @Test func theReverseChangeAndAnUnengagedLimitAreFinalInTheAnimatedPass() {
        let back = animateHeight(path: .preferred, overflow: .capped(fraction: 0.5), factor: 1, start: 0.4)
        #expect(abs(back.after - 402 * 9 / 16) < 0.5, "back to full height: R \(back.after)")
        let staleBack = back.log.sizes.filter { abs($0.height - back.after) > 0.5 }
        #expect(staleBack.isEmpty, "back: header laid out at \(staleBack) before \(back.after) (all: \(back.log.sizes))")
        let open = animateHeight(path: .preferred, overflow: .capped(fraction: 0.5), factor: 0.6)
        #expect(abs(open.after - 402 * 9 / 16) < 0.5, "capped 0.6: R \(open.after)")
        let staleOpen = open.log.sizes.filter { abs($0.height - open.after) > 0.5 }
        #expect(staleOpen.isEmpty, "capped 0.6: header laid out at \(staleOpen) (all: \(open.log.sizes))")
    }
}
