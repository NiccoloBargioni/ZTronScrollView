import XCTest

/// D11, narrowed by the user's ruling of 2026-11-09 (d76-magnified §16.11, item 1): the content and the header take the
/// disabled state only while a drag is recognized; hit-testing still blocks every motion without a finger. Pinned here
/// against a native `ScrollView` (`-ZTronPanNative 1`, its rows in a `UIScrollView`) where the pan screen allows it:
/// - a press that began before an app-animated scroll is not cancelled: it fires on lift (`-ZTronScrollOnPress`);
/// - a tap that catches a deceleration does not fire the Button;
/// - a drag that starts on a Button scrolls and cancels the press;
/// - the header's Button: a press begun before an app-animated pull fires on lift.
/// `ZS_DEMO_FORCED=1` runs the ZTron rows on the 15–16 paths; the native rows ignore it.
final class InteractionGateUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }

    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String, _ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", screen] + extra + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    private func field(_ raw: String, _ n: String) -> String {
        raw.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.map { String($0.dropFirst(n.count + 1)) } ?? ""
    }

    /// The pan screen's counters and state line (`button.fired`, `y`, `hookScrolls`).
    private func pan(_ app: XCUIApplication, _ tag: String) -> (fired: Int, y: Int, hook: Int, phase: String) {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let fired = Int(app.staticTexts["counter.button.fired"].value as? String ?? "") ?? -2
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        print("GATE \(tag) fired=\(fired) \(s)")
        return (fired, Int(field(s, "y")) ?? -9999, Int(field(s, "hookScrolls")) ?? -1, field(s, "phase"))
    }

    /// The scroller's frame: ours is `scroller`, the native one a `UIScrollView`.
    private func scrollerFrame(_ app: XCUIApplication) -> CGRect {
        let ours = app.otherElements["scroller"]
        return ours.exists ? ours.frame : app.scrollViews.firstMatch.frame
    }

    private func point(_ app: XCUIApplication, _ frame: CGRect, _ nx: CGFloat, _ ny: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + frame.width * nx, dy: frame.minY + frame.height * ny))
    }

    // MARK: A press begun before an app-animated scroll

    private func pressThroughAnAppScroll(native: Bool) {
        let tag = native ? "native" : "ztron"
        let app = launch("pan", ["-ZTronScrollOnPress", "0.3", "-ZTronScrollOnPressBy", "8"] + (native ? ["-ZTronPanNative", "1"] : []))
        app.buttons["row.2"].press(forDuration: 1.4)
        Thread.sleep(forTimeInterval: 0.6)
        let i = pan(app, "\(tag) press")
        XCTAssertEqual(i.hook, 1, "\(tag): the app scroll started while the press was held")
        XCTAssertEqual(i.y, 8, accuracy: 1, "\(tag): it ran to its end")
        XCTAssertEqual(i.fired, 1, "\(tag): a press begun before an app-animated scroll fires on lift (not cancelled)")
    }

    func testPressBegunBeforeAnAppAnimatedScrollFiresOnLift() { pressThroughAnAppScroll(native: false) }
    func testNativePressBegunBeforeAnAppAnimatedScrollFiresOnLift() { pressThroughAnAppScroll(native: true) }

    // MARK: A catch never reaches a Button; a drag cancels the press

    private func catchDoesNotFire(native: Bool) {
        let tag = native ? "native" : "ztron"
        let app = launch("pan", native ? ["-ZTronPanNative", "1"] : [])
        let frame = scrollerFrame(app)
        point(app, frame, 0.5, 0.85).press(forDuration: 0.05, thenDragTo: point(app, frame, 0.5, 0.15),
                                           withVelocity: .fast, thenHoldForDuration: 0)
        point(app, frame, 0.5, 0.5).tap()
        Thread.sleep(forTimeInterval: 0.5)
        let i = pan(app, "\(tag) catch")
        Thread.sleep(forTimeInterval: 1.0)
        let k = pan(app, "\(tag) after")
        XCTAssertEqual(i.fired, 0, "\(tag): a tap that catches a deceleration does not fire a Button")
        XCTAssertEqual(i.y, k.y, "\(tag): the catch stopped the motion")
    }

    func testCatchDuringDecelerationDoesNotFireButton() { catchDoesNotFire(native: false) }
    /// XCUI's tap waits for the app to be idle, so on a native `UIScrollView` it lands after the deceleration (27.0:
    /// fired 1 at a still y): the row is a plain tap at rest there, kept as an expected failure for reference.
    func testNativeCatchDuringDecelerationDoesNotFireButton() {
        XCTExpectFailure("XCUI waits out the native deceleration before tapping (app idle)", strict: false)
        catchDoesNotFire(native: true)
    }

    private func dragOnButtonDoesNotFire(native: Bool) {
        let tag = native ? "native" : "ztron"
        let app = launch("pan", native ? ["-ZTronPanNative", "1"] : [])
        let a = app.buttons["row.2"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(CGVector(dx: 0, dy: -150)), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1.5)
        let i = pan(app, "\(tag) drag")
        XCTAssertGreaterThan(i.y, 50, "\(tag): the drag scrolled")
        XCTAssertEqual(i.fired, 0, "\(tag): a recognized drag cancels the press under the finger")
        app.buttons["row.6"].tap()
        XCTAssertEqual(pan(app, "\(tag) tap").fired, 1, "\(tag): a tap at rest fires")
    }

    func testDragStartingOnAButtonCancelsThePress() { dragOnButtonDoesNotFire(native: false) }
    func testNativeDragStartingOnAButtonCancelsThePress() { dragOnButtonDoesNotFire(native: true) }

    // MARK: The header's Button

    /// The banner's header Button (`.fixed(0…200)`, `.stretch`): a press held while the app pulls the view 8 pt past the
    /// top in an animation (`scroll(to:)` in `withAnimation`) fires on lift.
    func testHeaderPressBegunBeforeAnAppAnimatedPullFiresOnLift() {
        let app = launch("banner", ["-ZTronHeaderSize", "fixed", "-ZTronScrollOnPress", "0.3", "-ZTronScrollOnPressBy", "-8"])
        let button = app.descendants(matching: .any).matching(identifier: "header.button").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.press(forDuration: 1.4)
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Info"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let raw = app.staticTexts["stateInfo"].value as? String ?? ""
        print("GATE header press \(raw)")
        XCTAssertEqual(field(raw, "hook"), "1", "the app pull started while the press was held")
        XCTAssertEqual(Double(field(raw, "taps")) ?? -1, 1, "a header press begun before an app-animated pull fires on lift")
    }
}
