import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// What the content's and the header's controls read from `isEnabled` (one log per test; the global counters are not
/// used, so the suites stay independent).
@MainActor
final class EnabledLog {
    var content: [Bool] = []
    var header: [Bool] = []
}

/// A leaf that records the `isEnabled` it is evaluated with (its body runs only when that environment value changes).
struct EnabledProbe: View {
    let log: EnabledLog
    let header: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if header { log.header.append(isEnabled) } else { log.content.append(isEnabled) }
        return Color.green.frame(width: 40, height: 40)
    }
}

/// D11, narrowed by the user's ruling of 2026-11-09 (d76-magnified §16.11, item 1): the content and the header take the
/// disabled state (`.disabled`, read as `isEnabled == false` by every control below) ONLY while a drag is recognized.
/// Hit-testing keeps `(decelerating || animating) && !isTracking || isDragging`, so a catch still never reaches a Button
/// (UI rows: PanUITests.testCatchDuringDecelerationDoesNotFireButton, HeaderUITests.testHeaderButtonCatchDuringBounceDoesNotFire).
/// Native: a `UIScrollView` never disables its content during a deceleration or a programmatic animation.
@MainActor
@Suite(.serialized)
struct InteractionGateTests {
    func host(_ s: ZTronScrollState, _ log: EnabledLog) -> UIWindow {
        hostDriven(
            ZTronScrollView(.vertical, state: s) {
                VStack(spacing: 0) {
                    EnabledProbe(log: log, header: false)
                    Color.yellow.frame(height: 3000)
                }
            }
            .withScalingHeader(size: .fixed(min: 64, max: 240), pull: .stretch) { _ in
                ZStack { Color.red; EnabledProbe(log: log, header: true) }
            })
    }

    /// The gate's two halves as functions of the phase flags: hit-testing blocks every motion without a finger and a
    /// recognized drag; the disabled state is the drag only.
    @Test(arguments: OSPath.allCases) func hitTestingBlocksMotionTheDisabledStateOnlyADrag(path: OSPath) {
        let s = makeState(path)
        let st = s.storage
        func both() -> (hit: Bool, disabled: Bool) { (HeaderHitGate.blocked(st), st.isDragging) }
        #expect(both() == (false, false), "at rest")
        s.setPhase(.animating)
        #expect(both() == (true, false), "an app animation: not hit-testable, not disabled")
        s.setPhase(.decelerating)
        #expect(both() == (true, false), "a deceleration: not hit-testable, not disabled")
        s.beginTracking()
        #expect(both() == (false, false), "a finger down (the catch's touch): hit-testable again, never disabled")
        s.beginDragging()
        #expect(both() == (true, true), "a recognized drag: both (the press under the finger is cancelled)")
        s.endTracking()
        #expect(both() == (false, false))
    }

    /// No `isEnabled == false` during an app-animated `scroll(to:)` (transaction path), an animated
    /// `setContentOffset` (clock path) or a deceleration; `false` while a drag is recognized, `true` again after it.
    @Test(arguments: OSPath.allCases) func controlsStayEnabledDuringMotionAndAreDisabledOnlyWhileDragging(path: OSPath) {
        let s = makeState(path)
        let log = EnabledLog()
        let w = withOSPath(path) { host(s, log) }
        defer { unhost(w) }
        #expect(log.content.last == true && log.header.last == true, "at rest")
        let top = -s.adjustedContentInset.top

        // An app animation on the transaction path (a pull past the top, as the C2 pull).
        withAnimation(.easeInOut(duration: 0.6)) { s.scroll(to: CGPoint(x: 0, y: top - 120)) }
        pump(0.15)
        #expect(s.phase == .animating, "mid-animation")
        pump(0.8)
        #expect(s.phase == .idle)
        // An app animation on the clock path.
        s.setContentOffset(CGPoint(x: 0, y: top + 400), animated: true)
        pump(0.1)
        #expect(s.phase == .animating, "clock animation running")
        pump(0.9)
        // A deceleration (a fling's release motion on the clock).
        let y = s.contentOffset.y
        s.beginDeceleration(x: .rest(position: 0),
                            y: .decay(Decay(origin: y, initialVelocity: 1500), start: s.now(), handoff: nil),
                            at: s.now())
        pump(0.1)
        #expect(s.phase == .decelerating, "decelerating")
        #expect(!log.content.contains(false) && !log.header.contains(false),
                "no disabled state through two app animations and a deceleration: \(log.content) \(log.header)")
        s.interrupt()
        pump(0.1)

        // A recognized drag disables both (the press under the finger is cancelled), its end enables them again.
        s.beginTracking()
        pump(0.05)
        #expect(log.content.last == true && log.header.last == true, "a finger down alone does not disable")
        s.beginDragging()
        pump(0.1)
        #expect(log.content.last == false && log.header.last == false, "dragging: disabled")
        s.endTracking()
        pump(0.1)
        #expect(log.content.last == true && log.header.last == true, "the drag ended: enabled")
    }
}
