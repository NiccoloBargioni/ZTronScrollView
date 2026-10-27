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

    /// The drawn content offsets (the transform effect's, one per frame it is evaluated at) while the inset toggles, and
    /// the run loop's clock when each was seen (`seen`, seconds since the toggle). `stallEvery` > 0 blocks the main thread
    /// for 50 ms before every n-th sample: the sampler overrunning under host load, made deterministic.
    func toggle(path: OSPath, animated: Bool, stallEvery: Int = 0)
        -> (before: CGFloat, after: CGFloat, drawn: [CGFloat], seen: [TimeInterval], r: (CGFloat, CGFloat), top: CGFloat,
            container: CGFloat) {
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
        var drawn: [CGFloat] = [], seen: [TimeInterval] = []
        let t0 = ProcessInfo.processInfo.systemUptime
        for i in 0..<90 {
            if stallEvery > 0, i % stallEvery == stallEvery - 1 { Thread.sleep(forTimeInterval: 0.05) }
            pump(1.0 / 60)
            if let p = s.probe.pending?.offset.y, drawn.last != p {
                drawn.append(p)
                seen.append(ProcessInfo.processInfo.systemUptime - t0)
            }
        }
        // D64: an app-provided safe area is not the keyboard (the probe stays 0), so it still limits `R` (below).
        #expect(s.peek.metrics.keyboardExtension == 0, "\(path): keyboard probe \(s.peek.metrics.keyboardExtension)")
        return (before, s.peek.targetOffset.y, drawn, seen, (r0, s.peek.metrics.header?.resting ?? -1), top, container)
    }

    /// Drawn with the animation: many frames, none moving more than a few points per frame (37.5 pt over 1.2 s, about
    /// 0.8 pt per 60 Hz frame at the curve's steepest), landing at the new rest. The animation runs on the render clock,
    /// the samples on `pump(1/60)`, a wall-clock spin that overruns under host load: several frames drawn between two
    /// samples gave steps of 2.3-2.7 pt next to 0.8 pt ones on a continuous curve (a raw `< 2` per sample failed about
    /// half of the 27.0 runs). A sample right after a stall can also still show the frame that was in flight when it
    /// began, and the next one catches up (27.0 at load: 5.6 pt over a 26-frame stall, then 16.8 pt in one frame, both
    /// on the easeInOut curve). So a step is judged against the 60 Hz frames of its own interval and the one before it
    /// (1 pt per frame: 2 pt for two one-frame intervals, the former bound), and a step with no stall around it (both
    /// intervals within 3 frames) may not carry half of the whole change (the seam lab's PASS rule; the unanimated write
    /// this suite guards against moved all of it in one frame).
    func expectDrawnWithTheCurve(_ r: (before: CGFloat, after: CGFloat, drawn: [CGFloat], seen: [TimeInterval],
                                       r: (CGFloat, CGFloat), top: CGFloat, container: CGFloat), _ label: String) {
        let steps = zip(r.drawn.dropFirst(), r.drawn).map { abs($0 - $1) }
        let frames = zip(r.seen.dropFirst(), r.seen).map { max(1, ($0 - $1) * 60) }
        let window = frames.indices.map { frames[$0] + ($0 > 0 ? frames[$0 - 1] : 1) }
        let perFrame = zip(steps, window).map { $0 / $1 }
        let change = abs(r.after - r.before)
        let unstalled = steps.indices.filter { window[$0] <= 3 }.map { steps[$0] }
        #expect(r.drawn.count > 30, "\(label): drawn \(r.drawn)")
        #expect((perFrame.max() ?? 0) < 1, "\(label): worst step per frame \(perFrame.max() ?? 0), steps \(steps), frames \(frames)")
        #expect((unstalled.max() ?? 0) < 0.5 * change, "\(label): worst step \(unstalled.max() ?? 0) of \(change) in \(r.drawn)")
        #expect(abs((r.drawn.last ?? 0) - r.after) < 0.5, "\(label): lands at \(r.drawn.last ?? .nan) vs \(r.after)")
    }

    @Test(arguments: OSPath.allCases)
    func anAnimatedSafeAreaChangeMovesTheContentWithTheHeader(path: OSPath) {
        let r = toggle(path: path, animated: true)
        // The limit is engaged: 0.25 of the container (778 -> 628 pt on 27.0) is below the 16:9 height (226 pt).
        #expect(abs(r.r.0 - 0.25 * r.container) < 0.5 && abs(r.r.1 - 0.25 * (r.container - 150)) < 0.5,
                "\(path): R \(r.r), container \(r.container)")
        #expect(abs(r.before + r.top + r.r.0) < 0.5 && abs(r.after + r.top + r.r.1) < 0.5, "\(path): rest \(r.before) -> \(r.after)")
        expectDrawnWithTheCurve(r, "\(path)")
    }

    /// The check above under a sampler that overruns (50 ms stalls every 7th sample, the host-load flake made
    /// deterministic): the frames drawn in between land in one sample (27.0: raw steps up to 4.1-4.3 pt, which the former
    /// raw `< 2` check failed), and the curve still passes; the stalls are seen (a sample interval of 2.5 frames or more).
    @Test(arguments: OSPath.allCases)
    func aStalledSamplerJudgesTheDrawnCurve(path: OSPath) {
        let r = toggle(path: path, animated: true, stallEvery: 7)
        let frames = zip(r.seen.dropFirst(), r.seen).map { ($0 - $1) * 60 }
        #expect((frames.max() ?? 0) >= 2.5, "\(path): sample intervals \(frames)")
        expectDrawnWithTheCurve(r, "\(path) stalled")
    }

    /// Unanimated, the content lands at once (the header's slot does too).
    @Test func anUnanimatedSafeAreaChangeStaysUnanimated() {
        let r = toggle(path: .preferred, animated: false)
        #expect(r.drawn.count <= 2, "drawn \(r.drawn)")
        #expect(abs((r.drawn.last ?? 0) - r.after) < 0.5, "lands at \(r.drawn.last ?? .nan) vs \(r.after)")
    }
}
