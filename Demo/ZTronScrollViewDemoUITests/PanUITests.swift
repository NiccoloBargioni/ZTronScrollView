import XCTest

final class PanUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var mode: String? { ProcessInfo.processInfo.environment["ZS_PAN_MODE"] }
    private var uikit: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_UIKIT"] == "1" }

    override func setUp() { continueAfterFailure = false }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", screen] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (uikit ? ["-ZTronForceUIKitObserver"] : []) + (mode.map { ["-ZTronPanGestureMode", $0] } ?? [])
        app.launch()
        return app
    }

    private func reset(_ app: XCUIApplication) {
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func info(_ app: XCUIApplication) -> (counters: [String: Int], y: Int, minY: Int, phase: String) {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        var out: [String: Int] = [:]
        for k in ["content.body", "didScroll", "button.fired", "clock.tick", "pan.catch", "pan.movingAtEvent", "pan.ev.down", "pan.ev.up", "pan.ev.dragEnd"] {
            out[k] = Int(app.staticTexts["counter.\(k)"].value as? String ?? "") ?? -2
        }
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        func field(_ n: String) -> String {
            s.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.map { String($0.dropFirst(n.count + 1)) } ?? ""
        }
        print("PAN \(forced ? "forced" : "preferred") mode=\(mode ?? "default") \(s) \(out.sorted { $0.key < $1.key })")
        return (out, Int(field("y")) ?? -9999, Int(field("minY")) ?? 9999, field("phase"))
    }

    private func scroller(_ app: XCUIApplication) -> XCUIElement { app.otherElements["scroller"] }

    /// Window-relative coordinate inside the scroller (cheap to resolve: no element snapshot at tap time).
    private func point(_ app: XCUIApplication, frame: CGRect, _ nx: CGFloat, _ ny: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + frame.width * nx, dy: frame.minY + frame.height * ny))
    }

    private func fling(_ app: XCUIApplication, frame: CGRect) {
        let a = point(app, frame: frame, 0.5, 0.85)
        let b = point(app, frame: frame, 0.5, 0.15)
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .fast, thenHoldForDuration: 0)
    }

    func testFlingThenRest() {
        let app = launch("pan"); reset(app)
        fling(app, frame: scroller(app).frame)
        Thread.sleep(forTimeInterval: 4)
        let i = info(app)
        XCTAssertEqual(i.phase, "0")
        XCTAssertGreaterThan(i.y, 200)
        XCTAssertGreaterThanOrEqual(i.counters["didScroll"]!, 20)
        XCTAssertEqual(i.counters["content.body"], 0)
        XCTAssertEqual(i.counters["button.fired"], 0)
        let j = info(app)
        XCTAssertEqual(i.y, j.y, "at rest")
    }

    func testRubberBandAtTopReturns() {
        let app = launch("pan"); reset(app)
        let sc = scroller(app)
        let a = sc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let b = sc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 2)
        let i = info(app)
        XCTAssertLessThan(i.minY, -20, "overscrolled during the drag")
        XCTAssertEqual(i.y, 0, "returned to the top edge")
        XCTAssertEqual(i.phase, "0")
        XCTAssertEqual(i.counters["content.body"], 0)
    }

    func testCatchDuringDecelerationDoesNotFireButton() {
        let app = launch("pan"); reset(app)
        let frame = scroller(app).frame
        let tapPoint = point(app, frame: frame, 0.5, 0.5)
        let t0 = Date()
        fling(app, frame: frame)
        let t1 = Date()
        tapPoint.tap()
        print("PAN timing t0=\(t0.timeIntervalSince1970) fling=\(t1.timeIntervalSince(t0)) tap=\(Date().timeIntervalSince(t1))")
        Thread.sleep(forTimeInterval: 0.5)
        let i = info(app)
        let j = info(app)
        Thread.sleep(forTimeInterval: 1.0)
        let k = info(app)
        XCTAssertEqual(i.counters["button.fired"], 0, "catching tap must not fire a button")
        XCTAssertEqual(j.y, k.y, "motion stopped")
        XCTAssertLessThan(k.y, 440, "the catch stopped the fling early")
        XCTAssertEqual(k.phase, "0")
        XCTAssertEqual(k.counters["content.body"], 0)
    }

    func testButtonTapFires() {
        let app = launch("pan"); reset(app)
        app.buttons["row.1"].tap()
        let i = info(app)
        XCTAssertEqual(i.counters["button.fired"], 1)
        XCTAssertEqual(i.y, 0)
    }

    func testPanStartingOnButtonScrollsWithoutFiring() {
        let app = launch("pan"); reset(app)
        let row = app.buttons["row.2"]
        let a = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let b = a.withOffset(CGVector(dx: 0, dy: -150))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1.5)
        let i = info(app)
        XCTAssertGreaterThan(i.y, 50)
        XCTAssertEqual(i.counters["button.fired"], 0)
        XCTAssertEqual(i.counters["content.body"], 0)
    }

    func testControlsUsable() {
        let app = launch("controls")
        let toggle = app.switches["ctl.toggle"]
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let slider = app.sliders["ctl.slider"]
        let before = slider.normalizedSliderPosition
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        print("CTL slider \(before) -> \(slider.normalizedSliderPosition)")
        XCTAssertGreaterThan(slider.normalizedSliderPosition, 0.6, "horizontal drag moves the slider")
        app.buttons["Info"].tap()
        XCTAssertTrue((app.staticTexts["stateInfo"].value as? String ?? "").contains("y=0"), "slider drag did not scroll")
        app.buttons["ctl.button"].tap()
        XCTAssertTrue(app.buttons["Taps: 1"].exists)
        let field = app.textFields["ctl.text"]
        field.tap()
        field.typeText("a"); XCTAssertEqual(field.value as? String, "a", "text field takes input")
    }

    /// Regression (M6 s3, iOS 17.5): a focused TextField inside the scroll view keeps the keyboard while the layout avoids it.
    /// The position ticket wrapped the container in a `GeometryEffect`, SwiftUI interpolated the avoidance, the viewport observer
    /// read the keyboard inset before the frame had moved, the resize watch reported `.animating` and the blocked content was
    /// disabled, which made UIKit resign the field. The pause lets the avoidance and the watch finish before the second input.
    func testFocusedTextFieldKeepsKeyboardThroughAvoidance() {
        let app = launch("controls")
        let field = app.textFields["ctl.text"]
        field.tap()
        field.typeText("a")
        Thread.sleep(forTimeInterval: 1.5)
        field.typeText("b")
        XCTAssertEqual(field.value as? String, "ab", "the field keeps focus through the keyboard avoidance")
        app.buttons["Info"].tap()
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        XCTAssertTrue(s.contains("phase=0"), "the keyboard left the scroll view idle: \(s)")
    }

    func testVerticalDragOnSliderScrolls() {
        let app = launch("controls")
        let slider = app.sliders["ctl.slider"]
        let a = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(CGVector(dx: 0, dy: -150)), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["Info"].tap()
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        print("CTL vertical-on-slider \(s) slider=\(slider.normalizedSliderPosition)")
        XCTAssertFalse(s.contains("y=0 "), "vertical drag from the slider scrolls: \(s)")
    }
}
