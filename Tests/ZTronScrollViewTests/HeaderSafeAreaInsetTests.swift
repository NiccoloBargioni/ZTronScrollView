import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Core check of M8b-s6 (header slot between the safe areas): an app-animated safe-area change (`withAnimation` around a
/// `.safeAreaInset(edge: .bottom)`) under an engaged `.capped` limit. SwiftUI animates the header's slot in the app's
/// transaction, so the header's height follows the change from layout; the state learns of it after that pass, outside
/// the transaction. The content's inset and offset were written unanimated: the content jumped to the new rest in one
/// frame while the header animated (seam lab: 75 pt, closing over the animation). They are now written in the turn's
/// animation (`ZTronScrollState.applyViewport`, inset-only branch), so the transform draws them with the header's curve.
@MainActor
@Suite(.serialized)
struct HeaderSafeAreaInsetTests {
    typealias Log = HeaderReviewD16Tests.Log
    typealias LogProbe = HeaderReviewD16Tests.LogProbe

    final class Model: ObservableObject { @Published var inset = false }

    struct InsetHost: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let log: Log
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Color.green.frame(height: 4000) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), overflow: .capped(fraction: 0.25)) { _ in
                    LogProbe(log: log)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: model.inset ? 150 : 0) }
        }
    }

    /// The drawn content offsets (the transform effect's, one per frame it is evaluated at) while the inset toggles.
    func toggle(path: OSPath, animated: Bool)
        -> (before: CGFloat, after: CGFloat, drawn: [CGFloat], r: (CGFloat, CGFloat), top: CGFloat, container: CGFloat) {
        let log = Log(), model = Model()
        let s = makeState(path)
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: InsetHost(model: model, state: s, log: log))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        pump(0.3)
        s.endOfTurn()
        let r0 = s.peek.metrics.header?.resting ?? -1
        let before = s.peek.targetOffset.y
        let m = s.peek.metrics
        let top = m.safeAreaInsets.top
        let container = HeaderMath.containerHeight(viewport: m.viewportSize, safe: m.safeAreaInsets, adjusted: .vertical)
        if animated {
            withAnimation(.easeInOut(duration: 1.2)) { model.inset = true }
        } else {
            model.inset = true
        }
        var drawn: [CGFloat] = []
        for _ in 0..<90 {
            pump(1.0 / 60)
            if let p = s.probe.pending?.offset.y, drawn.last != p { drawn.append(p) }
        }
        // D64: an app-provided safe area is not the keyboard (the probe stays 0), so it still limits `R` (below).
        #expect(s.peek.metrics.keyboardExtension == 0, "\(path): keyboard probe \(s.peek.metrics.keyboardExtension)")
        return (before, s.peek.targetOffset.y, drawn, (r0, s.peek.metrics.header?.resting ?? -1), top, container)
    }

    @Test(arguments: OSPath.allCases)
    func anAnimatedSafeAreaChangeMovesTheContentWithTheHeader(path: OSPath) {
        let r = toggle(path: path, animated: true)
        // The limit is engaged: 0.25 of the container (778 -> 628 pt on 27.0) is below the 16:9 height (226 pt).
        #expect(abs(r.r.0 - 0.25 * r.container) < 0.5 && abs(r.r.1 - 0.25 * (r.container - 150)) < 0.5,
                "\(path): R \(r.r), container \(r.container)")
        #expect(abs(r.before + r.top + r.r.0) < 0.5 && abs(r.after + r.top + r.r.1) < 0.5, "\(path): rest \(r.before) -> \(r.after)")
        // Drawn with the animation: many frames, none moving more than a few points (37.5 pt over 1.2 s).
        let steps = zip(r.drawn.dropFirst(), r.drawn).map { abs($0 - $1) }
        #expect(r.drawn.count > 30, "\(path): drawn \(r.drawn)")
        #expect((steps.max() ?? 0) < 2, "\(path): worst step \(steps.max() ?? 0) in \(r.drawn)")
        #expect(abs((r.drawn.last ?? 0) - r.after) < 0.5, "\(path): lands at \(r.drawn.last ?? .nan) vs \(r.after)")
    }

    /// Unanimated, the content lands at once (the header's slot does too).
    @Test func anUnanimatedSafeAreaChangeStaysUnanimated() {
        let r = toggle(path: .preferred, animated: false)
        #expect(r.drawn.count <= 2, "drawn \(r.drawn)")
        #expect(abs((r.drawn.last ?? 0) - r.after) < 0.5, "lands at \(r.drawn.last ?? .nan) vs \(r.after)")
    }
}
