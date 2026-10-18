import Foundation
import SwiftUI
import UIKit
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// Minimal stand-in for the part-b coordinator: feeds `PanSession`, applies effects to the state.
@MainActor
final class PanDriver {
    let state: ZTronScrollState
    var session = PanSession()
    var tracker = PointVelocityTracker()
    var settings = ReleaseSettings()
    var effectsLog: [PanEffect] = []
    var phases: [ZTronScrollPhase] = []
    var hasArbiter = false

    init(_ state: ZTronScrollState) { self.state = state }

    func env() -> PanEnvironment {
        var e = PanPathEnv.base
        e.presentationOffset = state.peek.presentationOffset
        e.isMovingWithoutFinger = (state.phase == .decelerating || state.phase == .animating) && !state.isTracking
        e.interruptedVelocity = state.lastInterruptedVelocity
        e.hasArbiter = hasArbiter
        return e
    }
    func send(_ event: PanEvent) {
        let e = env()
        apply(session.handle(event, env: e), env: e)
    }
    func apply(_ effects: [PanEffect], env e: PanEnvironment) {
        for fx in effects {
            effectsLog.append(fx)
            switch fx {
            case .catchMotion: state.interrupt()
            case .beginTracking: state.beginTracking()
            case .beginDragging: state.beginDragging()
            case let .setOffset(p): state.writeDragOffset(p)
            case let .release(r): state.endDrag(r, tracker: tracker, env: env(), settings: settings)
            case .endSequence: state.endTracking()
            case .askOwner: break
            }
            if phases.last != state.phase { phases.append(state.phase) }
        }
    }
    func note() { if phases.last != state.phase { phases.append(state.phase) } }
    func move(_ dy: CGFloat, t: TimeInterval) {
        send(.dragChanged(translation: CGSize(width: 0, height: dy), startLocation: .zero, time: t))
        tracker.add(CGPoint(x: 0, y: dy), at: t)
    }
}

enum PanPathEnv {
    static var base: PanEnvironment { PanSessionTests.env() }
}

@MainActor
@Suite(.serialized)
struct DelegateOrderTests {
    func make(_ path: OSPath) -> (ZTronScrollState, ReleaseDelegate, PanDriver) {
        let s = makeState(path)
        let d = ReleaseDelegate()
        s.delegate = d
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900), displayScale: 2))
        s.track(offset: CGPoint(x: 0, y: 300), zoom: 1)
        d.log.removeAll()
        return (s, d, PanDriver(s))
    }
    func step(_ s: ZTronScrollState, _ t: TimeInterval) { s.step(to: Date(timeIntervalSinceReferenceDate: t)) }

    func fling(_ drv: PanDriver, t0: TimeInterval = 100) {
        let s = drv.state
        drv.send(.touchDown(location: .zero, time: t0, touchCount: 1))
        var t = t0
        for i in 1...8 {
            t += 0.015
            drv.move(-CGFloat(i) * 15, t: t)        // finger up 1000 pt/s
            step(s, t); drv.note()
        }
        drv.send(.dragEnded(translation: CGSize(width: 0, height: -120), time: t, fallbackVelocity: nil))
    }

    @Test(arguments: OSPath.allCases) func scrollingOrderAndPhases(path: OSPath) {
        let (s, d, drv) = make(path)
        s.now = { 100.2 }
        fling(drv)
        var t = 100.12
        while s.isClockRunning && t < 110 { t += 1.0 / 60; step(s, t); drv.note() }
        let log = d.log
        #expect(log.first == "willBeginDragging")
        let order = ["willBeginDragging", "didScroll", "willEndDragging", "didEndDragging(true)", "willBeginDecelerating", "didScroll", "didEndDecelerating"]
        var cursor = 0
        for entry in log where cursor < order.count && entry == order[cursor] { cursor += 1 }
        #expect(cursor == order.count, "log: \(log)")
        #expect(log.filter { $0 == "willBeginDragging" }.count == 1 && log.filter { $0 == "didEndDecelerating" }.count == 1)
        #expect(log.last == "didEndDecelerating")
        #expect(drv.phases == [.tracking, .interacting, .decelerating, .idle], "phases: \(drv.phases)")
        #expect(s.peek.presentationOffset.y > 300)
    }

    @Test(arguments: OSPath.allCases) func didScrollAtMostOncePerStep(path: OSPath) {
        let (s, d, drv) = make(path)
        drv.send(.touchDown(location: .zero, time: 100, touchCount: 1))
        drv.move(-12, t: 100.01)
        drv.move(-20, t: 100.02); drv.move(-35, t: 100.03); drv.move(-50, t: 100.04)
        #expect(d.log.filter { $0 == "didScroll" }.isEmpty)       // coalesced until the tick
        step(s, 100.05)
        #expect(d.log.filter { $0 == "didScroll" }.count == 1)
        step(s, 100.06)                                            // nothing moved
        #expect(d.log.filter { $0 == "didScroll" }.count == 1)
        #expect(s.isClockRunning)                                  // keeps flushing while a finger is down
    }

    @Test(arguments: OSPath.allCases) func catchDuringDecelerationEndsItThenTracks(path: OSPath) {
        let (s, d, drv) = make(path)
        s.now = { 100.2 }
        fling(drv)
        step(s, 100.2); step(s, 100.25)
        d.log.removeAll(); drv.phases.removeAll()
        s.now = { 100.3 }
        drv.send(.touchDown(location: .zero, time: 100.3, touchCount: 1))
        #expect(d.log == ["didEndDecelerating"])
        #expect(drv.phases == [.idle, .tracking] || drv.phases == [.tracking], "phases: \(drv.phases)")
        #expect(s.isTracking && !s.isDecelerating && s.peek.targetOffset == s.peek.presentationOffset)
        #expect(drv.effectsLog.contains(.catchMotion))
        // tap: no drag, ends tracking, no scroll delegate calls
        drv.send(.touchesEnded(time: 100.35))
        #expect(!s.isTracking && s.phase == .idle)
        #expect(!d.log.contains("willBeginDragging"))
    }

    @Test(arguments: OSPath.allCases) func tapEmitsNoDelegateCalls(path: OSPath) {
        let (s, d, drv) = make(path)
        drv.send(.touchDown(location: .zero, time: 100, touchCount: 1))
        drv.send(.touchesEnded(time: 100.05))
        #expect(d.log.isEmpty && s.phase == .idle && !s.isClockRunning)
    }

    @Test(arguments: OSPath.allCases) func programmaticAnimationStillEndsWithScrollingAnimation(path: OSPath) {
        let (s, d, _) = make(path)
        s.now = { 100 }
        s.setContentOffset(CGPoint(x: 0, y: 500), animated: true)
        var t = 100.0
        while s.isClockRunning && t < 105 { t += 1.0 / 60; step(s, t) }
        #expect(d.log.last == "didEndScrollingAnimation" && !d.log.contains("didEndDecelerating"))
    }

    @Test(arguments: OSPath.allCases) func knobsDefaults(path: OSPath) {
        let s = makeState(path)
        #expect(s.isScrollEnabled && s.bounces && !s.isPagingEnabled && !s.alwaysBounceVertical && !s.alwaysBounceHorizontal)
        #expect(!s.isDirectionalLockEnabled && s.decelerationRate == .normal)
        #expect(!s.isTracking && !s.isDragging && !s.isDecelerating)
    }

    @Test(arguments: OSPath.allCases) func phaseReaderRendersOnlyOnTransitions(path: OSPath) {
        let (s, _, _) = make(path)
        let renders = Fired()
        let host = withOSPath(path) {
            UIHostingController(rootView: ZTronScrollPhaseReader(s) { phase -> Color in
                renders.n += 1
                _ = phase
                return Color.clear
            })
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.rootViewController = host
        window.makeKeyAndVisible()
        pump(0.2)
        let initial = renders.n
        #expect(initial >= 1)
        for i in 1...20 { s.track(offset: CGPoint(x: 0, y: CGFloat(i)), zoom: 1); pump(0.01) }
        #expect(renders.n == initial)                    // offset writes never wake it
        s.beginTracking(); pump(0.1)
        let afterTracking = renders.n
        #expect(afterTracking > initial)
        s.writeDragOffset(CGPoint(x: 0, y: 77)); pump(0.05)
        s.step(to: Date(timeIntervalSinceReferenceDate: 100)); pump(0.05)
        #expect(renders.n == afterTracking)
        s.endTracking(); pump(0.1)
        #expect(renders.n > afterTracking)
        window.isHidden = true
    }
}
