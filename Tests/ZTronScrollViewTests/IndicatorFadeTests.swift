import Combine
import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// A controller on a manual clock and a hand-fired timer list.
@MainActor
final class FadeRig {
    var t: TimeInterval = 100
    var wakes: [(delay: TimeInterval, fire: @MainActor () -> Void)] = []
    let controller = IndicatorController()

    init() {
        controller.now = { [weak self] in self?.t ?? 0 }
        controller.schedule = { [weak self] delay, fire in self?.wakes.append((delay, fire)) }
        ZTronRenderCounters.reset()
    }

    /// Moves the clock and fires the timers that are due.
    func advance(to time: TimeInterval) {
        t = time
        let due = wakes
        wakes.removeAll()
        for w in due { w.fire() }
    }
    var shown: Bool { controller.isShown }
    var fadeOuts: Int { ZTronRenderCounters.value("indicators.fadeOut") }
    var flashes: Int { ZTronRenderCounters.value("indicators.flash") }
}

/// M8-1 (design M8 §2, §8, §10): the fade timing on a manual clock — hideDelay, fade, flash hold, flash under `.hidden`.
@MainActor
@Suite(.serialized)
struct IndicatorFadeTests {
    @Test func activityShowsAtOnceAndFadesAfterTheHideDelay() {
        let r = FadeRig()
        #expect(!r.shown)
        r.controller.setActive(true)
        #expect(r.shown && r.wakes.isEmpty, "no timer while the content moves")
        r.t = 101
        r.controller.setActive(false)
        #expect(r.shown, "still shown for the hide delay")
        #expect(r.wakes.count == 1 && abs(r.wakes[0].delay - IndicatorStyle.hideDelay) < 1e-9)
        r.advance(to: 101 + IndicatorStyle.hideDelay - 0.01)
        #expect(r.shown && r.fadeOuts == 0, "an early wake-up re-arms instead of hiding")
        #expect(r.wakes.count == 1)
        r.advance(to: 101 + IndicatorStyle.hideDelay)
        #expect(!r.shown && r.fadeOuts == 1, "the fade starts when the delay has passed")
        #expect(r.wakes.isEmpty, "zero idle cost: nothing scheduled once hidden")
    }

    @Test func aFlashHoldsThenFadesAndDoesNotRepeat() {
        let r = FadeRig()
        r.controller.flash()
        #expect(r.shown && r.flashes == 1)
        #expect(r.wakes.count == 1 && abs(r.wakes[0].delay - IndicatorStyle.flashHold) < 1e-9)
        r.advance(to: 100 + IndicatorStyle.flashHold - 0.001)
        #expect(r.shown)
        r.advance(to: 100 + IndicatorStyle.flashHold)
        #expect(!r.shown && r.fadeOuts == 1)
        r.advance(to: 200)
        #expect(!r.shown && r.fadeOuts == 1 && r.flashes == 1)
    }

    @Test func oneTimerPerDeadlineHoweverOftenItIsEvaluated() {
        let r = FadeRig()
        r.controller.flash()
        for i in 0..<60 { r.t = 100 + Double(i) * 0.005; r.controller.evaluate() }
        #expect(r.wakes.count == 1, "frames do not schedule timers")
        for _ in 0..<5 { r.controller.setActive(true); r.controller.setActive(false) }
        #expect(r.wakes.count == 1)
    }

    @Test func aSecondFlashExtendsTheHoldFromItsOwnTime() {
        let r = FadeRig()
        r.controller.flash()
        r.t = 100.4
        r.controller.flash()                     // deadline 101.0
        r.advance(to: 100.6)                     // the first timer fires: the hold continues
        #expect(r.shown && r.fadeOuts == 0)
        #expect(r.wakes.count == 1 && abs(r.wakes[0].delay - 0.4) < 1e-9)
        r.advance(to: 100.4 + IndicatorStyle.flashHold)
        #expect(!r.shown && r.fadeOuts == 1 && r.flashes == 2)
    }

    @Test func activityDuringAFlashKeepsTheThumbsUntilItStops() {
        let r = FadeRig()
        r.controller.flash()
        r.t = 100.3
        r.controller.setActive(true)
        r.advance(to: 100.7)                      // past the flash hold, content still moving
        #expect(r.shown && r.fadeOuts == 0)
        r.t = 102
        r.controller.setActive(false)
        r.advance(to: 102 + IndicatorStyle.hideDelay)
        #expect(!r.shown && r.fadeOuts == 1)
    }

    @Test func aFlashWhileDisabledIsANoOp() {
        let r = FadeRig()
        r.controller.setEnabled(false)            // both axes `.hidden` / `.never`
        r.controller.flash()
        #expect(!r.shown && r.wakes.isEmpty && r.flashes == 0, "no state change, no timer, not even a counted flash")
        r.controller.setActive(true)
        #expect(!r.shown, "activity shows nothing either")
    }

    @Test func hidingAfterAFlashStartedCancelsTheFade() {
        let r = FadeRig()
        r.controller.flash()
        #expect(r.shown)
        r.controller.setEnabled(false)            // the visibility became `.hidden` mid-flash
        #expect(!r.shown && r.fadeOuts == 0, "it disappears without a fade")
        r.advance(to: 101)                        // the stale timer fires: nothing happens
        #expect(!r.shown && r.fadeOuts == 0)
        r.controller.setEnabled(true)
        #expect(!r.shown, "re-enabling alone shows nothing")
        r.controller.flash()
        #expect(r.shown)
    }

    @Test func resetOnDisappearClearsEverything() {
        let r = FadeRig()
        r.controller.setActive(true)
        r.controller.reset()
        #expect(!r.shown && !r.controller.isActive)
        r.t = 101
        r.advance(to: 105)
        #expect(!r.shown)
        r.controller.setActive(true)
        #expect(r.shown, "usable again after a reset")
    }

    @Test func theFadeIsOneSwiftUIAnimationOfTheOpacityTarget() {
        // The shown flag flips once per interaction; the fade itself is `.linear(duration: fade)` run by SwiftUI, so a long
        // scroll costs no timers and no extra evaluations beyond the thumb leaf's own frames.
        final class Flips { var count = 0 }
        let r = FadeRig()
        let flips = Flips()
        let observation = r.controller.objectWillChange.sink { flips.count += 1 }
        for _ in 0..<50 { r.controller.setActive(true) }
        #expect(flips.count == 1, "repeated activity publishes once")
        r.controller.setActive(false)
        r.advance(to: 100 + IndicatorStyle.hideDelay)
        #expect(flips.count == 2)
        observation.cancel()
        #expect(IndicatorStyle.fade == 0.3 && IndicatorStyle.hideDelay == 0.4 && IndicatorStyle.flashHold == 0.6)
    }

    // MARK: through the hosted container (both OS paths): one flash per event, never per frame

    @Test(arguments: OSPath.allCases) func flashOnAppearFlashesOnceWhileScrolling(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        ZTronRenderCounters.reset()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 1000) }.scrollIndicatorsFlash(onAppear: true))
        }
        pump(0.15)
        #expect(ZTronRenderCounters.value("indicators.flash") == 1)
        #expect(s.indicatorController?.isShown == true, "shown for the flash hold")
        for y in stride(from: 10.0, through: 200.0, by: 10) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1); pump(0.02) }
        #expect(ZTronRenderCounters.value("indicators.flash") == 1, "frames of scrolling never flash")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func noFlashWithoutTheModifier(path: OSPath) {
        let s = makeState(path)
        ZTronRenderCounters.reset()
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 1000) }) }
        pump(0.15)
        #expect(ZTronRenderCounters.value("indicators.flash") == 0 && s.indicatorController?.isShown == false)
        unhost(w)
    }

    @MainActor final class Trigger: ObservableObject { @Published var value = 0; @Published var other = 0 }

    @Test(arguments: OSPath.allCases) func aTriggerFlashesOncePerChange(path: OSPath) {
        struct Root: View {
            let state: ZTronScrollState
            @ObservedObject var trigger: Trigger
            var body: some View {
                ZTronScrollView(.vertical, state: state) { Color.red.frame(height: 1000) }
                    .scrollIndicatorsFlash(trigger: trigger.value)
            }
        }
        let s = makeState(path)
        let trigger = Trigger()
        ZTronRenderCounters.reset()
        let w = withOSPath(path) { host(Root(state: s, trigger: trigger)) }
        pump(0.15)
        #expect(ZTronRenderCounters.value("indicators.flash") == 0, "the first value is not a change")
        trigger.value = 1; pump(0.1)
        #expect(ZTronRenderCounters.value("indicators.flash") == 1)
        trigger.other = 5; pump(0.1)                 // an unrelated publish re-evaluates the root, same trigger value
        #expect(ZTronRenderCounters.value("indicators.flash") == 1)
        trigger.value = 2; pump(0.1)
        #expect(ZTronRenderCounters.value("indicators.flash") == 2)
        for y in stride(from: 10.0, through: 100.0, by: 10) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1); pump(0.02) }
        #expect(ZTronRenderCounters.value("indicators.flash") == 2)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theTwinTriggerAndTheMemberTriggerFlashIndependently(path: OSPath) {
        struct Root: View {
            let state: ZTronScrollState
            @ObservedObject var trigger: Trigger
            var body: some View {
                ZTronScrollView(.vertical, state: state) { Color.red.frame(height: 1000) }
                    .scrollIndicatorsFlash(trigger: trigger.value)
                    .ztronScrollIndicatorsFlash(trigger: trigger.other)
            }
        }
        let s = makeState(path)
        let trigger = Trigger()
        ZTronRenderCounters.reset()
        let w = withOSPath(path) { host(Root(state: s, trigger: trigger)) }
        pump(0.15)
        trigger.other = 1; pump(0.1)
        #expect(ZTronRenderCounters.value("indicators.flash") == 1)
        trigger.value = 1; pump(0.1)
        #expect(ZTronRenderCounters.value("indicators.flash") == 2)
        unhost(w)
    }

    @MainActor final class Visibility: ObservableObject { @Published var visible = true }

    @Test(arguments: OSPath.allCases) func theStateFlashesOnDemandOnceItIsOnScreen(path: OSPath) {
        struct Root: View {
            let state: ZTronScrollState
            @ObservedObject var visibility: Visibility
            var body: some View {
                if visibility.visible { ZTronScrollView(.vertical, state: state) { Color.red.frame(height: 1000) } }
            }
        }
        let s = makeState(path)
        let visibility = Visibility()
        ZTronRenderCounters.reset()
        s.flashScrollIndicators()                    // before the view exists: nothing to flash
        #expect(ZTronRenderCounters.value("indicators.flash") == 0)
        let w = withOSPath(path) { host(Root(state: s, visibility: visibility)) }
        pump(0.15)
        s.flashScrollIndicators()
        #expect(ZTronRenderCounters.value("indicators.flash") == 1 && s.indicatorController?.isShown == true)
        visibility.visible = false
        pump(0.15)
        #expect(s.indicatorController == nil, "detached when the view leaves")
        s.flashScrollIndicators()
        #expect(ZTronRenderCounters.value("indicators.flash") == 1)
        visibility.visible = true
        pump(0.15)
        s.flashScrollIndicators()
        #expect(ZTronRenderCounters.value("indicators.flash") == 2, "attached again when it returns")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aFlashUnderHiddenOrShowsIndicatorsFalseIsANoOp(path: OSPath) {
        let s = makeState(path)
        ZTronRenderCounters.reset()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 1000) }
                .scrollIndicators(.hidden).scrollIndicatorsFlash(onAppear: true))
        }
        pump(0.15)
        s.flashScrollIndicators()
        #expect(ZTronRenderCounters.value("indicators.flash") == 0 && s.indicatorController?.isShown == false)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func motionShowsTheThumbsAndStopFadesThem(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        let w = withOSPath(path) { host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 1000) }) }
        pump(0.15)
        guard let c = s.indicatorController else { Issue.record("no controller"); return }
        #expect(!c.isShown)
        s.beginTracking(); pump(0.05)
        #expect(!c.isShown, "a finger down alone shows nothing (UIKit shows the thumb when the content moves)")
        s.beginDragging(); pump(0.05)
        #expect(c.isActive && c.isShown)
        s.endTracking(); pump(0.05)
        #expect(!c.isActive, "the drag ended")
        #expect(c.isShown, "inside the hide delay")
        unhost(w)
    }
}
