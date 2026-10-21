import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// User report 2026-10-21 (D35): "if I pull down slowly, the refresh triggers but only the final part of the view shows".
/// The display of a refresh must not depend on the speed of the pull: the indicator is revealed in proportion to the pull,
/// whole when the trigger fires, and keeps the refreshing look until the finger lifts even when the action (0.6 s) returned
/// long before; a lift soon after the trigger holds it for the time that is missing. The numbers are those the leaf draws
/// (`RefreshIndicatorMath` over the live state), frame by frame.
@MainActor
@Suite(.serialized)
struct RefreshSlowPullTests {
    let viewport = CGSize(width: 390, height: 360)

    /// How much of the indicator is inside its clip, from the same inputs `RefreshEdgeIndicator` feeds the placement.
    func visible(_ r: RefreshRig, style: ZTronRefreshStyle = .default) -> CGFloat {
        let s = r.state.peek, st = r.refreshState()
        let pull = RefreshMath.signedPull(edge: .top, offset: s.presentationOffset, zoom: s.presentationZoom, metrics: s.metrics,
                                          alignment: r.state.contentAlignment)
        let aci = s.metrics.adjustedContentInset, hold = s.metrics.refreshHold
        let base = EdgeInsets(top: aci.top - hold.top, leading: 0, bottom: aci.bottom - hold.bottom, trailing: 0)
        guard let p = RefreshIndicatorMath.placement(
            edge: .top, style: style, overlay: false, refreshing: st.mode == .refreshing, dragPosition: st.dragPosition,
            pull: pull, length: 60, viewport: s.metrics.viewportSize, base: base) else { return 0 }
        return p.visibleLength(vertical: true)
    }

    /// A pull of `frames` frames to 150 pt; returns the pull and the visible thickness at the frame the trigger fired.
    func pull(_ r: RefreshRig, frames: Int, style: ZTronRefreshStyle = .default, actionReturnsAt: Int? = nil) async
        -> (atTrigger: (pull: CGFloat, visible: CGFloat, mode: ZTronRefreshState.Mode)?, triggerFrame: Int?) {
        var atTrigger: (pull: CGFloat, visible: CGFloat, mode: ZTronRefreshState.Mode)?
        var triggerFrame: Int?
        r.touchDown()
        for i in 1...frames {
            r.finger(toPull: 150 * CGFloat(i) / CGFloat(frames))
            let p = r.pull()
            if triggerFrame == nil, r.refresh.triggerSerial == 1 {
                triggerFrame = i
                atTrigger = (p, visible(r, style: style), r.refreshState().mode)
                await r.pumpTasks()                                     // the action starts
            }
            if let at = actionReturnsAt, let t = triggerFrame, i == t + at { await r.completeAction() }
            // Revealed in proportion to the pull (the clip is the gap), and from the pull of its thickness on whole.
            #expect(abs(visible(r, style: style) - min(p, 60)) < 0.01, "frame \(i), pull \(p)")
        }
        return (atTrigger, triggerFrame)
    }

    @Test(arguments: OSPath.allCases, [ZTronRefreshStyle.default, .system])
    func theWholeIndicatorShowsWhenTheTriggerFiresWhateverTheSpeed(path: OSPath, style: ZTronRefreshStyle) async {
        for frames in [6, 40, 160] {
            let r = RefreshRig(path, viewport: viewport)
            let (atTrigger, _) = await pull(r, frames: frames, style: style)
            guard let t = atTrigger else { Issue.record("\(frames) frames: the pull never fired"); continue }
            #expect(t.pull >= 100 && t.mode == .refreshing)
            #expect(t.visible == 60, "\(frames) frames: whole when the trigger fires (pull \(t.pull))")
        }
    }

    @Test(arguments: OSPath.allCases) func aSlowPullKeepsTheRefreshingLookUntilTheLiftEvenIfTheActionReturnedLongBefore(path: OSPath) async {
        let r = RefreshRig(path, viewport: viewport)
        // 150 frames (2.5 s): the trigger at ~100 pt, the 0.6 s action returns ~36 frames later, the pull goes on.
        _ = await pull(r, frames: 150, actionReturnsAt: 36)
        #expect(r.gate.finished == 1 && r.gate.started == 1, "the action ran and returned under the finger")
        #expect(r.refreshState().mode == .refreshing && r.refreshState().dragPosition == 1, "still the refreshing look")
        #expect(visible(r) == 60 && r.hold == EdgeInsets(), "whole, and nothing is held under a finger")
        r.wait(0.4)
        #expect(r.refreshState().mode == .refreshing && visible(r) == 60)
        r.lift()
        #expect(r.refreshState().mode == .notRefreshing && r.engine().phase == .idle, "shown long enough: the refresh ends at the lift")
        #expect(r.hold == EdgeInsets(), "nothing to hold")
        r.settle()
        #expect(abs(r.offset.y) < 0.5 && r.state.phase == .idle)
        await r.pumpTasks()
        #expect(r.gate.started == 1, "one action per pull")
    }

    @Test(arguments: OSPath.allCases) func aLiftSoonAfterTheTriggerHoldsTheIndicatorForTheTimeThatIsMissing(path: OSPath) async {
        let r = RefreshRig(path, viewport: viewport)
        // A quick pull whose action returns right away: the lift comes 0.1 s after the trigger.
        r.touchDown()
        var triggeredAt: TimeInterval?
        for i in 1...10 {
            r.finger(toPull: 14 * CGFloat(i))
            if triggeredAt == nil, r.refresh.triggerSerial == 1 { triggeredAt = r.now; await r.pumpTasks(); await r.completeAction() }
        }
        guard let trigger = triggeredAt else { Issue.record("the pull never fired"); return }
        r.tick(2)
        r.lift()
        guard case let .finishing(until) = r.engine().phase else { Issue.record("expected finishing, got \(r.engine().phase)"); return }
        #expect(abs(until - (trigger + 0.5)) < 1e-9, "counted from the trigger")
        #expect(r.hold.top == 60 && r.refreshState().mode == .refreshing, "held at the lift")
        r.tick(10)                                                       // still before the deadline, mid spring-back
        #expect(r.hold.top == 60 && r.refreshState().mode == .refreshing && visible(r) == 60, "whole, and held")
        r.settle()                                                       // the spring ends after the deadline: the reset
        if r.hold != EdgeInsets() { r.clock.t = until + 0.01; r.fireWakes(); r.settle() }
        #expect(r.hold == EdgeInsets() && r.refreshState().mode == .notRefreshing && abs(r.offset.y) < 0.5)
        #expect(r.gate.started == 1)
    }
}
