import XCTest

/// The iOS 15-16 UIKit touch observer (D31, docs/design/UIKIT-touch-observer.md §5) on a 17+ simulator: every test launches
/// the demo with `-ZTronForceUIKitObserver` (+ `-ZTronForceAllFallbacks` when `ZS_DEMO_FORCED=1`, the shipped 15-16 shape).
/// Asserts through the counters (DEBUG) and the state readout; together with the unit run they carry the 100 % line gate
/// of `Sources/ZTronScrollView/Gesture/UIKit/` (scripts/coverage-uikit.sh).
final class UIKitObserverUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private static let keys = ["content.body", "didScroll", "button.fired", "pan.catch", "pan.ev.down", "pan.ev.drag",
                               "pan.ev.up", "pan.ev.cancel", "phase.tracking", "uikit.began", "uikit.moved", "uikit.ended",
                               "uikit.cancelled", "uikit.canPrevent", "uikit.canBePrevented"]

    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String = "pan", _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", screen, "-ZTronForceUIKitObserver"]
            + (forced ? ["-ZTronForceAllFallbacks"] : []) + extra
        app.launch()
        reset(app)
        return app
    }

    private func reset(_ app: XCUIApplication) {
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private struct Info { var c: [String: Int]; var y: Int; var phase: String; var tracking: String; var probe: String }

    private func info(_ app: XCUIApplication) -> Info {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        var out: [String: Int] = [:]
        for k in Self.keys { out[k] = Int(app.staticTexts["counter.\(k)"].value as? String ?? "") ?? -2 }
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        func field(_ n: String) -> String {
            s.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.map { String($0.dropFirst(n.count + 1)) } ?? ""
        }
        print("UIKITOBS \(forced ? "forced" : "preferred") \(s) \(out.sorted { $0.key < $1.key })")
        return Info(c: out, y: Int(field("y")) ?? -9999, phase: field("phase"), tracking: field("tracking"), probe: field("probe"))
    }

    private func scroller(_ app: XCUIApplication) -> XCUIElement { app.otherElements["scroller"] }

    private func point(_ app: XCUIApplication, frame: CGRect, _ nx: CGFloat, _ ny: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + frame.width * nx, dy: frame.minY + frame.height * ny))
    }

    private func swipeUp(_ app: XCUIApplication, frame: CGRect) {
        let a = point(app, frame: frame, 0.5, 0.7), b = point(app, frame: frame, 0.5, 0.2)
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.2)
    }

    private func fling(_ app: XCUIApplication, frame: CGRect) {
        point(app, frame: frame, 0.5, 0.85).press(forDuration: 0.05, thenDragTo: point(app, frame: frame, 0.5, 0.15),
                                                  withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// Install, three of the four touch overrides, `forward`/`deliver` and `canBePrevented`. UIKit asks `canPrevent` and the
    /// delegate's `shouldRecognizeSimultaneouslyWith` only of a recognizer that recognizes: ours never does, so those answers are
    /// pinned by `UIKitObserverShellTests` (unit) instead.
    func testSwipeScrollsAndLogsTouchDown() {
        let app = launch()
        swipeUp(app, frame: scroller(app).frame)
        Thread.sleep(forTimeInterval: 1.5)
        let i = info(app)
        XCTAssertGreaterThan(i.y, 50, "the swipe scrolled")
        XCTAssertGreaterThanOrEqual(i.c["pan.ev.down"]!, 1, "the observer reported the touch-down")
        XCTAssertGreaterThanOrEqual(i.c["pan.ev.up"]!, 1)
        XCTAssertGreaterThanOrEqual(i.c["uikit.began"]!, 1)
        XCTAssertGreaterThanOrEqual(i.c["uikit.moved"]!, 1)
        XCTAssertGreaterThanOrEqual(i.c["uikit.ended"]!, 1)
        XCTAssertGreaterThanOrEqual(i.c["uikit.canBePrevented"]!, 1, "UIKit asked when the SwiftUI pan recognized; the answer is no")
        XCTAssertEqual(i.c["uikit.canPrevent"], 0, "asked only of a recognizing recognizer")
        XCTAssertEqual(i.c["button.fired"], 0)
        XCTAssertEqual(i.c["content.body"], 0)
        XCTAssertEqual(i.phase, "0")
    }

    /// S12: the passive recognizer does not disturb the controls under it.
    func testButtonTapStillFires() {
        let app = launch()
        app.buttons["row.1"].tap()
        let i = info(app)
        XCTAssertEqual(i.c["button.fired"], 1)
        XCTAssertGreaterThanOrEqual(i.c["pan.ev.down"]!, 1)
        XCTAssertEqual(i.y, 0)
    }

    /// The catch / `isTracking` do not wait for a drag sample: a press that never moves is a touch-down and a lift.
    func testPressAtRestSetsTrackingAtTouchDown() {
        let app = launch()
        scroller(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6)
        Thread.sleep(forTimeInterval: 0.5)
        let i = info(app)
        XCTAssertEqual(i.c["pan.ev.down"], 1)
        XCTAssertEqual(i.c["pan.ev.drag"], 0, "no drag sample: the DragGesture never recognized")
        XCTAssertEqual(i.c["pan.ev.up"], 1)
        XCTAssertGreaterThanOrEqual(i.c["phase.tracking"]!, 1, "the phase passed through .tracking at touch-down")
        XCTAssertEqual(i.phase, "0")
        XCTAssertEqual(i.tracking, "0")
        XCTAssertEqual(i.y, 0)
    }

    func testTouchStopsDeceleration() {
        let app = launch()
        let frame = scroller(app).frame
        fling(app, frame: frame)
        point(app, frame: frame, 0.5, 0.5).tap()
        Thread.sleep(forTimeInterval: 0.5)
        let a = info(app)
        Thread.sleep(forTimeInterval: 1.0)
        let b = info(app)
        XCTAssertGreaterThanOrEqual(b.c["pan.catch"]!, 1, "the touch-down caught the motion")
        XCTAssertEqual(b.c["button.fired"], 0, "the catching tap fires nothing")
        XCTAssertEqual(a.y, b.y, "motion stopped")
        XCTAssertLessThan(b.y, 440, "the catch stopped the fling early")
        XCTAssertEqual(b.phase, "0")
    }

    /// The window recognizer sees every touch of the window; the core keeps only those that began in the viewport.
    func testTouchOutsideViewportIgnored() {
        let app = launch()
        _ = info(app)
        let i = info(app)
        XCTAssertGreaterThanOrEqual(i.c["uikit.began"]!, 2, "the recognizer saw the Snapshot taps")
        XCTAssertEqual(i.c["pan.ev.down"], 0, "outside the viewport: no touch-down reaches the coordinator")
        XCTAssertEqual(i.c["pan.ev.up"], 0)
    }

    /// Two touches: the observer feeds count, centroid and magnification (MagnificationGesture only recognizes).
    func testPinchZoomsAroundCentroid() {
        let app = launch("zoom")
        scroller(app).pinch(withScale: 2, velocity: 1)
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        func f(_ n: String) -> Double {
            s.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.flatMap { Double($0.dropFirst(n.count + 1)) } ?? -9999
        }
        print("UIKITOBS zoom \(forced ? "forced" : "preferred") \(s)")
        let z = f("z")
        XCTAssertGreaterThan(z, 1.2, "zoomed in")
        XCTAssertLessThan(z, 8.0001)
        // The content point under the pinch centre (150, 180) stays under it: the centroid came from the touches.
        XCTAssertLessThan(hypot(f("ux") - 150, f("uy") - 180) * z, 30)
        XCTAssertEqual(Int(app.staticTexts["counter.content.body"].value as? String ?? ""), 0)
    }

    /// The scroll view leaves the window (uninstall) and returns (reinstall).
    func testHideAndShowReinstalls() {
        let app = launch("pan", ["-ZTronShowToggle"])
        let frame = scroller(app).frame
        app.buttons["Toggle"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let hidden = info(app)
        point(app, frame: frame, 0.5, 0.5).tap()
        let still = info(app)
        XCTAssertEqual(still.c["uikit.began"], hidden.c["uikit.began"], "uninstalled: the window recognizer sees nothing")
        XCTAssertEqual(still.c["pan.ev.down"], 0)
        app.buttons["Toggle"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        swipeUp(app, frame: frame)
        Thread.sleep(forTimeInterval: 1.0)
        let shown = info(app)
        XCTAssertGreaterThan(shown.c["uikit.began"]!, still.c["uikit.began"]!, "reinstalled")
        XCTAssertGreaterThanOrEqual(shown.c["pan.ev.down"]!, 1)
        XCTAssertGreaterThan(shown.y, 50)
    }

    /// 300 ms into a press the app hides its window for 100 ms, 800 ms in it sends itself to Settings (`-ZTronCancelProbe`). UIKit
    /// then cancels the touch in flight: `touchesCancelled` reaches the recognizer and the core closes pan and pinch with
    /// `.cancelled`. How soon the app is backgrounded varies (17.5: always within the press; 27.0: sometimes after a 2.5 s one),
    /// hence the 4 s hold. R6: if a runtime still delivers no cancel, the test skips (the line is then executed by
    /// `UIKitObserverShellTests`, the behaviour is the core tests'); on the user's 15 / 16 run it is a real check.
    func testCancelProbe() throws {
        let app = launch("pan", ["-ZTronCancelProbe"])
        scroller(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 4.0)
        app.activate()
        Thread.sleep(forTimeInterval: 1.5)
        let i = info(app)
        print("UIKITOBS cancelProbe \(i.probe)")
        try XCTSkipIf(i.c["uikit.cancelled"] == 0, "no touchesCancelled on this simulator (R6); probe: \(i.probe)")
        XCTAssertGreaterThanOrEqual(i.c["pan.ev.cancel"]!, 1, "the core turned it into a cancelled pan")
        XCTAssertEqual(i.phase, "0", "the sequence is over")
        XCTAssertEqual(i.tracking, "0")
    }
}
