import XCTest

final class PanUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var mode: String? { ProcessInfo.processInfo.environment["ZS_PAN_MODE"] }
    private var uikit: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_UIKIT"] == "1" }

    override func setUp() { continueAfterFailure = false }

    /// `wrap`: the controls screen's app-level effect around the scroll view, or "native" for a `ScrollView` (`ControlsScreen`).
    private func launch(_ screen: String, wrap: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", screen] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (uikit ? ["-ZTronForceUIKitObserver"] : []) + (mode.map { ["-ZTronPanGestureMode", $0] } ?? [])
            + (wrap.map { ["-ZTronControlsWrap", $0] } ?? [])
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

    /// The fling of the test above starts on a Button, so it also ends a press that began under the finger. This one starts in
    /// the gap between two rows: nothing is pressed, and only the catching tap itself can fire a Button.
    func testCatchOfAFlingThatStartedOffAButtonDoesNotFireButton() {
        let app = launch("pan"); reset(app)
        let frame = scroller(app).frame
        let upper = app.buttons["row.3"].frame, lower = app.buttons["row.4"].frame
        let gap = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: (upper.maxY + lower.minY) / 2))
        gap.press(forDuration: 0.05, thenDragTo: point(app, frame: frame, 0.5, 0.15), withVelocity: .fast, thenHoldForDuration: 0)
        point(app, frame: frame, 0.5, 0.5).tap()
        Thread.sleep(forTimeInterval: 0.5)
        let i = info(app)
        XCTAssertEqual(i.counters["pan.catch"], 1, "the tap caught the motion")
        XCTAssertEqual(i.counters["button.fired"], 0, "the catching tap must not fire a button")
        XCTAssertEqual(i.counters["content.body"], 0)
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

    // MARK: A locked content leaves a focused text field alone (DBG-s3)

    /// Taps the text field and types one character. The pause lets the keyboard avoidance and the resize watch settle.
    private func focusTextField(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["ctl.text"]
        field.tap()
        field.typeText("a")
        Thread.sleep(forTimeInterval: 1.0)
        return field
    }

    /// The Info line: `phase=… y=… edit=<sessions begun>/<sessions ended>` (library DEBUG counters of the text inputs).
    private func controlsInfo(_ app: XCUIApplication) -> String {
        app.buttons["Info"].tap()
        return app.staticTexts["stateInfo"].value as? String ?? ""
    }

    /// The editing session of the field never ended: the keyboard was not taken away, not even for an instant (UIKit resigns a
    /// field for `.disabled` and for `allowsHitTesting(false)` alike, and SwiftUI may bring the focus back afterwards).
    private func assertSessionNeverEnded(_ info: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(info.contains(" edit=1/0"), "\(message): \(info)", file: file, line: line)
    }

    /// The gate used `.disabled` while a drag, a deceleration or an animation locked the content, and SwiftUI answers that with
    /// `setUserInteractionEnabled(false)` on every UIKit-backed control: UIKit resigned the focused `UITextField`, any scroll
    /// dismissed the keyboard. A native `ScrollView` keeps it (`testNativeScrollViewKeepsFocusedTextFieldOnDrag`).
    func testDragKeepsFocusedTextField() {
        let app = launch("controls")
        let field = focusTextField(app)
        let row = app.staticTexts["Filler 1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        row.press(forDuration: 0.05, thenDragTo: row.withOffset(CGVector(dx: 0, dy: -60)), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1.5)
        field.typeText("b")
        XCTAssertEqual(field.value as? String, "ab", "a drag on the scroll view keeps the focused field")
        let info = controlsInfo(app)
        XCTAssertFalse(info.contains("y=0 "), "the drag scrolled: \(info)")
        assertSessionNeverEnded(info, "the drag")
    }

    func testFlingKeepsFocusedTextField() {
        let app = launch("controls")
        let field = focusTextField(app)
        let row = app.staticTexts["Filler 1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        row.press(forDuration: 0.05, thenDragTo: row.withOffset(CGVector(dx: 0, dy: -120)), withVelocity: .fast, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 3.0)   // the deceleration locked the content; it has settled
        field.typeText("b")
        XCTAssertEqual(field.value as? String, "ab", "a fling keeps the focused field")
        let info = controlsInfo(app)
        XCTAssertFalse(info.contains("y=0 "), "the fling scrolled: \(info)")
        assertSessionNeverEnded(info, "the fling")
    }

    func testAnimatedScrollKeepsFocusedTextField() {
        let app = launch("controls")
        let field = focusTextField(app)
        app.buttons["Animate"].tap()   // setContentOffset(y: 120, animated: true): phase .animating
        Thread.sleep(forTimeInterval: 2.0)
        field.typeText("b")
        XCTAssertEqual(field.value as? String, "ab", "an animated scroll keeps the focused field")
        let info = controlsInfo(app)
        XCTAssertTrue(info.contains("phase=0 y=120"), "the animation ran and settled: \(info)")
        assertSessionNeverEnded(info, "the animated scroll")
    }

    /// An app-level effect around the scroll view (even an identity one) makes SwiftUI on iOS 17.5 interpolate the keyboard
    /// avoidance: the viewport observer reads the keyboard's inset before the frame moves, the resize watch reports `.animating`
    /// and the content locks. The lock must not take the focus with it.
    private func focusSurvivesAvoidance(wrap: String?) {
        let app = launch("controls", wrap: wrap)
        let field = app.textFields["ctl.text"]
        field.tap()
        field.typeText("a")
        Thread.sleep(forTimeInterval: 1.5)
        field.typeText("b")
        XCTAssertEqual(field.value as? String, "ab", "the field keeps focus through the keyboard avoidance (wrap: \(wrap ?? "none"))")
        let info = controlsInfo(app)
        XCTAssertTrue(info.contains("phase=0"), "the keyboard left the scroll view idle: \(info)")
        assertSessionNeverEnded(info, "the keyboard avoidance (wrap: \(wrap ?? "none"))")
    }

    /// Regression (M6 s3, iOS 17.5): the position ticket wrapped the container in a `GeometryEffect`, SwiftUI interpolated the
    /// avoidance, the resize watch reported `.animating` and the locked content made UIKit resign the field.
    func testFocusedTextFieldKeepsKeyboardThroughAvoidance() { focusSurvivesAvoidance(wrap: nil) }
    func testFocusedTextFieldKeepsKeyboardInScaleEffectWrapper() { focusSurvivesAvoidance(wrap: "scale") }
    func testFocusedTextFieldKeepsKeyboardInRotationEffectWrapper() { focusSurvivesAvoidance(wrap: "rotation") }

    /// The reference: the same content in a native `ScrollView` (`-ZTronControlsWrap native`) keeps the focus on the same drag.
    func testNativeScrollViewKeepsFocusedTextFieldOnDrag() {
        let app = launch("controls", wrap: "native")
        let field = focusTextField(app)
        let row = app.staticTexts["Filler 1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        row.press(forDuration: 0.05, thenDragTo: row.withOffset(CGVector(dx: 0, dy: -60)), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1.5)
        field.typeText("b")
        XCTAssertEqual(field.value as? String, "ab", "a native ScrollView keeps the focused field on a drag")
        assertSessionNeverEnded(controlsInfo(app), "the native drag")
    }

    /// The lock keeps a new touch away from UIKit-backed controls too. A slow resize keeps the content locked (`.animating`) with
    /// the controls where they are; coordinates are fixed first because `element.tap()` waits for the app to idle.
    func testTapOnUIKitControlsIsBlockedWhileContentIsLocked() {
        let app = launch("controls")
        func tap(_ f: CGRect, _ nx: CGFloat) {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.minX + f.width * nx, dy: f.midY)).tap()
        }
        let toggle = app.switches["ctl.toggle"], field = app.textFields["ctl.text"]
        let toggleFrame = toggle.frame, fieldFrame = field.frame
        app.buttons["Resize"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        tap(fieldFrame, 0.5)
        tap(toggleFrame, 0.93)
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(toggle.value as? String, "0", "a tap on the Toggle while the content is locked does nothing")
        XCTAssertEqual(app.keyboards.count, 0, "a tap on the TextField while the content is locked does not focus it")
        Thread.sleep(forTimeInterval: 4.5)   // the resize is over: the scroll view is taller and the controls moved with the layout
        tap(toggle.frame, 0.93)
        XCTAssertEqual(toggle.value as? String, "1", "unlocked again")
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
