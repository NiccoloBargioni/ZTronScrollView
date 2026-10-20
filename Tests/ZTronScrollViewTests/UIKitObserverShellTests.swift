#if canImport(UIKit) && os(iOS)
import Testing
import UIKit
@testable import ZTronScrollView

// The UIKit shell of the iOS 15-16 touch observer (SPEC S2 amendment 2026-10-20, D31; design UIKIT-touch-observer.md §2/§5):
// its passive contract and its install lifecycle, on a real `UIWindow`. The touch overrides themselves are exercised by
// `UIKitObserverUITests` (the demo, `-ZTronForceUIKitObserver`); what UIKit never asks of a recognizer that never
// recognizes (`canPrevent`, `shouldRecognizeSimultaneouslyWith`) is pinned here by calling the answers directly.

@MainActor
@Suite struct UIKitObserverShellTests {
    @MainActor private struct Rig {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let anchor = UIKitTouchAnchorView()
        let recognizer: UIKitTouchObserverRecognizer

        init() {
            let coordinator = PanCoordinator(state: ZTronScrollState(), axes: .vertical)
            recognizer = UIKitTouchObserverRecognizer(anchor: anchor, coordinator: coordinator, catchState: CatchObserverState())
            anchor.recognizer = recognizer
        }
    }

    @Test func theRecognizerIsPassive() {
        let r = Rig().recognizer
        #expect(r.state == .possible)
        #expect(!r.cancelsTouchesInView)
        #expect(!r.delaysTouchesBegan)
        #expect(!r.delaysTouchesEnded)
        #expect(!r.requiresExclusiveTouchType)
        #expect(r.allowedTouchTypes.map(\.intValue) == [UITouch.TouchType.direct.rawValue, UITouch.TouchType.pencil.rawValue])
        #expect(r.delegate === r)
    }

    @Test func itNeitherBlocksNorIsBlocked() {
        let r = Rig().recognizer
        let other = UITapGestureRecognizer()
        #expect(r.gestureRecognizer(r, shouldRecognizeSimultaneouslyWith: other))
        #expect(!r.gestureRecognizer(r, shouldRequireFailureOf: other))
        #expect(!r.gestureRecognizer(r, shouldBeRequiredToFailBy: other))
        #expect(!r.canPrevent(other))
        #expect(!r.canBePrevented(by: other))
    }

    @Test func theAnchorInstallsOnItsWindowAndFollowsIt() {
        let rig = Rig()
        #expect(rig.recognizer.view == nil)
        rig.window.addSubview(rig.anchor)                        // didMoveToWindow(window)
        #expect(rig.recognizer.view === rig.window)
        rig.recognizer.install(on: rig.window)                   // idempotent
        #expect(rig.window.gestureRecognizers?.filter { $0 === rig.recognizer }.count == 1)

        let second = UIWindow(frame: rig.window.frame)
        rig.recognizer.install(on: second)                       // a scene / window move
        #expect(rig.recognizer.view === second)
        #expect(rig.window.gestureRecognizers?.contains { $0 === rig.recognizer } != true)

        UIKitTouchObserverAnchor.dismantleUIView(rig.anchor, coordinator: ())   // SwiftUI removes the representable
        #expect(rig.recognizer.view == nil)
        UIKitTouchObserverAnchor.dismantleUIView(rig.anchor, coordinator: ())   // idempotent
        rig.recognizer.install(on: nil)
        #expect(rig.recognizer.view == nil)
    }

    /// R6 (design resolutions): the simulator never produced a `touchesCancelled` (mid-press: a sheet, the window / root view
    /// not accepting touches, the window hidden, the app sent to Settings; 27.0). This executes the override with no touches, for
    /// the LINE gate only. The behaviour (cancel closes pan and pinch, everything dropped) is `TouchObserverCoreTests`';
    /// the real delivery is the user's device check on iOS 15/16 (`UIKitObserverUITests.testCancelProbe` runs there).
    @Test func touchesCancelledWithNoTouchesChangesNothing() {
        let r = Rig().recognizer
        r.touchesCancelled([], with: UIEvent())
        #expect(r.state == .possible)
    }

    @Test func leavingTheWindowUninstalls() {
        let rig = Rig()
        rig.window.addSubview(rig.anchor)
        #expect(rig.recognizer.view === rig.window)
        rig.anchor.removeFromSuperview()
        #expect(rig.recognizer.view == nil)
    }
}
#endif
