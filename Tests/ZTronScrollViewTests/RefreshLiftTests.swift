import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// Found by `RefreshUITests` (M8b-2): a pull whose action returned while the finger was still down fired a SECOND action at
/// the lift. The lift resets the pull (`firedThisPull`), and a flush inside the release hand-over (the state still tracking)
/// sampled the same pull again. The coordinator masks the tracking flag from the lift to the end of the touch.
@MainActor
@Suite(.serialized)
struct RefreshLiftTests {
    @Test(arguments: OSPath.allCases, [Edge.top, Edge.leading])
    func anActionThatReturnedBeforeTheLiftIsNotStartedAgainByTheLift(path: OSPath, edge: Edge) async {
        let horizontal = edge == .leading
        let r = RefreshRig(path, configs: [edge: ZTronRefreshConfiguration()], axes: horizontal ? .horizontal : .vertical,
                           content: horizontal ? CGSize(width: 3000, height: 800) : CGSize(width: 390, height: 3000))
        r.touchDown()
        for p in stride(from: 20.0, through: 140.0, by: 20) { r.finger(toPull: p, edge: edge) }
        await r.pumpTasks()
        #expect(r.gate.started == 1)
        await r.completeAction()                                   // the action returns while the finger is down
        r.wait(0.7)
        for p in stride(from: 160.0, through: 260.0, by: 20) { r.finger(toPull: p, edge: edge) }
        r.lift()
        r.settle()
        await r.pumpTasks()
        r.wait(1.0); r.fireWakes(); await r.pumpTasks(); r.settle()
        #expect(r.gate.started == 1, "one action per pull, also when it returned before the lift")
        #expect(r.refreshState(edge).mode == .notRefreshing && r.refresh.engines[edge]?.phase == .idle)
        #expect(r.refreshHoldTotal == 0)
    }

    @Test(arguments: OSPath.allCases) func theNextPullAfterThatTouchIsANewPull(path: OSPath) async {
        let r = RefreshRig(path)
        r.touchDown()
        for p in stride(from: 20.0, through: 140.0, by: 20) { r.finger(toPull: p) }
        await r.pumpTasks()
        await r.completeAction()
        r.lift()
        r.settle()
        await r.pumpTasks()
        #expect(r.gate.started == 1)
        r.pullAndRelease(to: 130)
        await r.pumpTasks()
        #expect(r.gate.started == 2, "the mask ends with the touch")
    }
}

extension RefreshRig {
    var refreshHoldTotal: CGFloat { let h = hold; return h.top + h.bottom + h.leading + h.trailing }
}
