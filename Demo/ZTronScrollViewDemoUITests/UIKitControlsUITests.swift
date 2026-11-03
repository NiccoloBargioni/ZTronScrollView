import XCTest

/// Touch-based UIKit controls behind SwiftUI, inside the scroll view (DBG-s4, handoff Open 2 of DBG-s3): `Stepper`,
/// `Picker(.segmented)`, `DatePicker` (compact and wheel), `Menu`, `ColorPicker` on `-ZTronScreen uikitControls`. Each test
/// drives the control the way a user does and asserts that its value changed and, for taps, holds and horizontal drags,
/// that the scroll view stayed at y = 0 (the controls own those touches; the scroll view only observes them).
///
/// `ZS_NATIVE=1` (`TEST_RUNNER_ZS_NATIVE=1`) is the baseline lane: the same screen with SwiftUI's own `ScrollView`. A test that
/// fails there is a test or OS problem, not the library's.
final class UIKitControlsUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var uikit: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_UIKIT"] == "1" }
    private var native: Bool { ProcessInfo.processInfo.environment["ZS_NATIVE"] == "1" }
    /// `-ZTronPanGestureMode` (DEBUG): `ZS_PAN_MODE=gesture|high` runs the lane with another attach style, as in `PanUITests`.
    private var mode: String? { ProcessInfo.processInfo.environment["ZS_PAN_MODE"] }

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "uikitControls"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (uikit ? ["-ZTronForceUIKitObserver"] : []) + (native ? ["-ZTronNativeScroll"] : [])
            + (mode.map { ["-ZTronPanGestureMode", $0] } ?? [])
        app.launch()
        return app
    }

    private typealias Values = [String: String]

    /// The live readout above the scroll view: `stepper=0 segment=0 compact=2026-03-15 wheel=2026-03-15 menu=none ...`.
    private func values(_ app: XCUIApplication) -> Values {
        var out: Values = [:]
        for pair in (app.staticTexts["values"].value as? String ?? "").components(separatedBy: " ") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }

    /// Polls the readout (a render lags the touch under load) until `done` holds or `timeout` passes; returns the last reading.
    @discardableResult
    private func waitValues(_ app: XCUIApplication, timeout: TimeInterval = 3, _ done: (Values) -> Bool) -> Values {
        var v = values(app)
        let end = Date().addingTimeInterval(timeout)
        while !done(v), Date() < end {
            Thread.sleep(forTimeInterval: 0.2)
            v = values(app)
        }
        print("UICTL \(native ? "native" : forced ? "forced" : "preferred") \(v.sorted { $0.key < $1.key })")
        return v
    }

    /// The scroll offset (`Info` prints it; a popover or sheet still open swallows the first tap, hence the retries).
    private func offsetY(_ app: XCUIApplication) -> Int? {
        for _ in 0..<3 {
            app.buttons["Info"].tap()
            Thread.sleep(forTimeInterval: 0.3)
            let s = app.staticTexts["stateInfo"].value as? String ?? ""
            if let y = s.components(separatedBy: " ").first(where: { $0.hasPrefix("y=") }).flatMap({ Int($0.dropFirst(2)) }) { return y }
        }
        return nil
    }

    private func assertStayedAtTop(_ app: XCUIApplication, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        let y = offsetY(app)
        XCTAssertEqual(y, 0, "\(what) did not scroll the content (y=\(y.map(String.init) ?? "?"))", file: file, line: line)
    }

    /// A limitation of the pure-SwiftUI scroller that the baseline lane does not have (docs/progress/DBG-s4.md): it is asserted
    /// like everything else on the native baseline, and recorded as an expected failure on the ZTron lanes, so the suite stays
    /// green and a fix shows up (`strict`: an assertion that starts passing fails the test until this wrapper is removed).
    private func knownLimitation(_ reason: String, strict: Bool = true, _ assertion: () -> Void) {
        if native { assertion() } else { XCTExpectFailure(reason, strict: strict, failingBlock: assertion) }
    }

    /// A required fix that has not landed yet (D84: not a limitation): asserted on the native baseline, an expected failure on the
    /// ZTron lanes that names its open item, until that item is fixed.
    private func requiredFix(_ item: String, strict: Bool = true, _ assertion: () -> Void) {
        if native { assertion() } else { XCTExpectFailure("required fix, \(item)", strict: strict, failingBlock: assertion) }
    }

    private func steps(_ v: Values) -> Int { Int(v["stepper"] ?? "") ?? -1 }

    // MARK: Stepper

    /// A tap on "+" then "−" changes the value by one each. The two buttons are UIKit (`UIStepper`) touch targets.
    func testStepperTapIncrementsAndDecrements() {
        let app = launch()
        let inc = app.buttons["ctl.stepper-Increment"], dec = app.buttons["ctl.stepper-Decrement"]
        inc.tap()
        XCTAssertEqual(steps(waitValues(app) { steps($0) == 1 }), 1, "a tap on + increments")
        inc.tap()
        XCTAssertEqual(steps(waitValues(app) { steps($0) == 2 }), 2, "a second tap on + increments again")
        dec.tap()
        XCTAssertEqual(steps(waitValues(app) { steps($0) == 1 }), 1, "a tap on - decrements")
        assertStayedAtTop(app, "stepper taps")
    }

    /// Press and hold on "+": the stepper auto-repeats (about +3 in two seconds on the native baseline).
    func testStepperPressAndHoldAutoRepeats() {
        let app = launch()
        app.buttons["ctl.stepper-Increment"].press(forDuration: 2.0)
        let v = waitValues(app) { steps($0) >= 2 }
        XCTAssertGreaterThanOrEqual(steps(v), 2, "holding + auto-repeats (a tap alone would give 1)")
        assertStayedAtTop(app, "stepper hold")
    }

    // MARK: Segmented Picker

    /// A tap on the second segment selects it.
    func testSegmentedPickerTapSelectsSegment() {
        let app = launch()
        app.segmentedControls["ctl.segmented"].buttons["Two"].tap()
        XCTAssertEqual(waitValues(app) { $0["segment"] == "1" }["segment"], "1", "tap on Two selects segment 1")
        app.segmentedControls["ctl.segmented"].buttons["Three"].tap()
        XCTAssertEqual(waitValues(app) { $0["segment"] == "2" }["segment"], "2", "tap on Three selects segment 2")
        assertStayedAtTop(app, "segment taps")
    }

    /// A horizontal drag across the segments (press on the first, lift on the third) selects the third; the drag is the
    /// control's, so the content must not scroll. Known limitation on every OS (DBG-s4): the scroll view's pan recognizer
    /// begins after 10 pt of movement and cancels the touch of the touch-based `UISegmentedControl`; taps are not affected.
    func testSegmentedPickerDragBetweenSegments() {
        let app = launch()
        let f = app.segmentedControls["ctl.segmented"].frame
        func at(_ x: CGFloat) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.minX + f.width * x, dy: f.midY))
        }
        at(1.0 / 6).press(forDuration: 0.05, thenDragTo: at(5.0 / 6))
        knownLimitation("the pan cancels the UISegmentedControl's touch (DBG-s4 Open 2)") {
            XCTAssertEqual(waitValues(app) { $0["segment"] == "2" }["segment"], "2", "dragging from segment One to Three selects Three")
        }
        assertStayedAtTop(app, "a segment drag")
    }

    // MARK: DatePicker

    /// Compact style: a tap opens the calendar popover, a tap on a day sets the date.
    func testCompactDatePickerPicksADay() {
        let app = launch()
        app.datePickers["ctl.date.compact"].tap()
        let day = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*\\b20\\b.*")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 8), "a tap on the compact date picker opens the calendar")
        day.tap()
        XCTAssertEqual(waitValues(app) { $0["compact"] == "2026-03-20" }["compact"], "2026-03-20", "the day tapped in the calendar is the date")
        assertStayedAtTop(app, "compact date picker")
    }

    /// Wheel style: a vertical drag on the month wheel turns it. The wheel is a UIKit scroll view, so the drag is its own: a native
    /// `ScrollView` stays put, the ZTron scroll view follows the finger too (y = 50 on 18+, 1 on 17.5; DBG-s4 Open 3). The wheel
    /// must absorb the drag (D84), so this is a required fix, not a limitation: open item 39 on 26+ (D86 keeps the pan simultaneous
    /// there), open item 37 on 18.x and below; not strict, as before, so the expectation holds on every lane until the fix lands.
    func testWheelDatePickerTurnsTheMonthWheel() {
        let app = launch()
        // The month is the one wheel whose value is not a number (the wheel order and the month names follow the locale).
        let month = app.datePickers["ctl.date.wheel"].pickerWheels.matching(NSPredicate(format: "NOT (value MATCHES %@)", "[0-9]+")).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5), "the date picker has a month wheel")
        let a = month.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(CGVector(dx: 0, dy: -60)), withVelocity: .slow, thenHoldForDuration: 0.3)
        let v = waitValues(app) { $0["wheel"] != "2026-03-15" }
        XCTAssertNotEqual(v["wheel"], "2026-03-15", "dragging the month wheel up changes the date")
        XCTAssertGreaterThan(v["wheel"] ?? "", "2026-03-15", "up is later")
        let item = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
            ? "open item 39 (D84, D86): on 26+ a drag that starts on the wheel also scrolls the content (y = 50)"
            : "open item 37 (D84): below 26 a drag that starts on the wheel also scrolls the content (y = 50 on 18.x, 1 on 17.5)"
        requiredFix(item + "; the wheel must absorb it as in a native ScrollView", strict: false) {
            assertStayedAtTop(app, "a wheel drag")
        }
    }

    // MARK: Menu

    /// A tap opens the menu, a tap on an item chooses it.
    func testMenuTapPicksAnItem() {
        let app = launch()
        app.buttons["ctl.menu"].tap()
        let beta = app.buttons["Beta"]
        XCTAssertTrue(beta.waitForExistence(timeout: 8), "a tap on the Menu opens it")
        beta.tap()
        XCTAssertEqual(waitValues(app) { $0["menu"] == "beta" }["menu"], "beta", "the tapped item is chosen")
        assertStayedAtTop(app, "menu")
    }

    /// Press, drag onto an item and lift in one gesture chooses the item under the finger.
    func testMenuPressDragReleasePicksAnItem() {
        let app = launch()
        let a = app.buttons["ctl.menu"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        a.press(forDuration: 0.6, thenDragTo: a.withOffset(CGVector(dx: 0, dy: 60)), withVelocity: .slow, thenHoldForDuration: 0.4)
        let v = waitValues(app) { $0["menu"] != "none" }
        XCTAssertNotEqual(v["menu"], "none", "press, drag and release chooses an item")
        assertStayedAtTop(app, "menu drag")
    }

    // MARK: ColorPicker

    /// A tap on the row opens the system colour picker (a sheet); a tap on its first favourite (black) reports a colour through
    /// the binding. Where the first tap has to land differs per OS: the whole row on 27 and 18, the small colour well at its
    /// right end on 17 (the row's accessibility activation point misses it), so the activation point is tried first, then the well.
    func testColorPickerOpensAndReportsAColor() {
        let app = launch()
        let row = app.descendants(matching: .any).matching(identifier: "ctl.color").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let picker = app.otherElements["UIColorPicker"]
        row.tap()
        if !picker.waitForExistence(timeout: 4) { row.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap() }
        XCTAssertTrue(picker.waitForExistence(timeout: 12), "a tap on the ColorPicker opens the picker")
        let favorite = picker.collectionViews.firstMatch.cells.element(boundBy: 0)
        XCTAssertTrue(favorite.waitForExistence(timeout: 5), "the picker shows its favourites")
        favorite.tap()
        let v = waitValues(app) { (Int($0["colorChanges"] ?? "") ?? 0) >= 1 }
        XCTAssertGreaterThanOrEqual(Int(v["colorChanges"] ?? "") ?? 0, 1, "the picker reported a new colour")
        let bar = app.navigationBars["Color"]
        if bar.exists { bar.buttons.element(boundBy: bar.buttons.count - 1).tap() }
        assertStayedAtTop(app, "colour picker")
    }
}
