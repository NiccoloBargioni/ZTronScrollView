import XCTest

/// DBG-s3 (docs/progress/DBG-s3.md): SwiftUI's `scrollDisabled(_:)` on a `ZTronScrollView` must stop it exactly as it stops
/// SwiftUI's own `ScrollView` (a disabled view never moves), outside and inside a sheet, next to `ztronScrollDisabled`.
/// The oracle is the app's readout (`sd.info`: content offset, the delegate's scroll / drag callbacks, what `\.isScrollEnabled`
/// reads inside and beside the scroller), not XCUI frames. Before the fix `scrollDisabled` was a no-op: the offset reached 240.
final class ScrollDisabledUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var uikit: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_UIKIT"] == "1" }
    private var path: String { uikit ? "uikit" : forced ? "forced" : "preferred" }
    private var osTag: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    override func setUp() { continueAfterFailure = false }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func launch(mode: String, sheet: Bool = false, medium: Bool = false, nativeScroll: Bool = false,
                        grow: Bool = false) throws -> XCUIApplication {
        try XCTSkipIf(nativeScroll && (forced || uikit), "the native variant ignores the fallback switches: preferred run only")
        let app = XCUIApplication()
        var args = ["-ZTronScreen", "scrollDisabled", "-ZTronSDMode", mode]
        if sheet { args.append("-ZTronSDSheet") }
        if medium { args.append("-ZTronSDMedium") }
        if nativeScroll { args.append("-ZTronSDNativeScroll") }
        if grow { args.append("-ZTronSDGrow") }
        if forced { args.append("-ZTronForceAllFallbacks") }
        if uikit { args.append("-ZTronForceUIKitObserver") }
        app.launchArguments = args
        app.launch()
        if sheet { app.buttons["sd.present"].tap() }
        XCTAssertTrue(app.buttons["sd.snapshot"].waitForExistence(timeout: 10), "the pane appeared")
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    private func parse(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for kv in s.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { out[p[0]] = p[1] }
        }
        return out
    }

    private func int(_ r: [String: String], _ key: String) -> Int { Int(r[key] ?? "") ?? -999 }

    @discardableResult
    private func read(_ app: XCUIApplication, _ tag: String) -> [String: String] {
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["sd.snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        let raw = element(app, "sd.info").value as? String ?? ""
        print("SD os=\(osTag) path=\(path) \(tag) | \(raw)")
        return parse(raw)
    }

    private func reset(_ app: XCUIApplication) {
        app.buttons["sd.reset"].tap()
        Thread.sleep(forTimeInterval: 0.3)
    }

    private func drag(_ app: XCUIApplication, dy: CGFloat) {
        let f = element(app, "sd.scroller").frame
        let x = f.minX + f.width * 0.5
        let startY = dy > 0 ? f.minY + 40 : f.maxY - 60
        let a = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: startY))
        let b = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: startY + dy))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Drags up 250 from rest, reads, drags back down 250, reads: `(afterUp, afterDown)`.
    private func upThenDown(_ app: XCUIApplication, _ name: String) -> (up: [String: String], down: [String: String]) {
        reset(app)
        drag(app, dy: -250)
        let up = read(app, "\(name) after-up250")
        reset(app)
        drag(app, dy: 250)
        let down = read(app, "\(name) after-down250")
        return (up, down)
    }

    /// A drag moved nothing: no scroll callback, no drag callback, offset 0.
    private func assertStill(_ r: [String: String], _ what: String) {
        XCTAssertEqual(int(r, "off"), 0, "\(what): offset")
        XCTAssertEqual(int(r, "offMax"), 0, "\(what): offset max")
        XCTAssertEqual(int(r, "didScroll"), 0, "\(what): scroll callbacks")
        XCTAssertEqual(int(r, "dragBegan"), 0, "\(what): drag callbacks")
    }

    // MARK: control

    /// An enabled view scrolls (240 = 250 pt of finger travel minus the pan's 10 pt slack) and comes back; the probe reads `true`.
    func testEnabledScrolls() throws {
        let app = try launch(mode: "none")
        let (up, down) = upThenDown(app, "enabled")
        XCTAssertGreaterThan(int(up, "off"), 200, "the harness can scroll the view")
        XCTAssertEqual(int(down, "off"), 0, "and back")
        XCTAssertEqual(int(up, "envInside"), 1)
    }

    /// The oracle works on SwiftUI's own `ScrollView` (not skipped: preferred run only).
    func testNativeScrollViewScrollsWhenEnabled() throws {
        let app = try launch(mode: "none", nativeScroll: true)
        reset(app)
        drag(app, dy: -250)
        XCTAssertGreaterThan(int(read(app, "native enabled after-up250"), "nativeOff"), 200)
    }

    // MARK: SwiftUI's scrollDisabled (the bug: it did nothing)

    func testNativeScrollDisabledStopsTheView() throws {
        let app = try launch(mode: "native")
        let (up, down) = upThenDown(app, "scrollDisabled")
        XCTAssertEqual(int(up, "envInside"), 0, "the environment reaches the content")
        assertStill(up, "up"); assertStill(down, "down")
    }

    func testNativeScrollDisabledOnAParentStopsTheView() throws {
        let app = try launch(mode: "nativeParent")
        let (up, down) = upThenDown(app, "scrollDisabled(parent)")
        assertStill(up, "up"); assertStill(down, "down")
    }

    func testNativeScrollViewBaselineStaysStill() throws {
        let app = try launch(mode: "native", nativeScroll: true)
        let (up, down) = upThenDown(app, "native scrollDisabled")
        XCTAssertEqual(int(up, "nativeOff"), 0); XCTAssertEqual(int(down, "nativeOff"), 0)
    }

    func testScrollDisabledFalseScrolls() throws {
        let app = try launch(mode: "nativeFalse")
        XCTAssertGreaterThan(int(upThenDown(app, "scrollDisabled(false)").up, "off"), 200)
    }

    /// `ztronScrollDisabled` keeps working (it writes both channels).
    func testZtronScrollDisabledStopsTheView() throws {
        let app = try launch(mode: "ztron")
        let (up, down) = upThenDown(app, "ztronScrollDisabled")
        assertStill(up, "up"); assertStill(down, "down")
    }

    /// The value follows the modifier at run time: enabled, disabled by the button, enabled again.
    func testScrollDisabledFollowsTheModifier() throws {
        let app = try launch(mode: "nativeToggle")
        reset(app)
        drag(app, dy: -250)
        XCTAssertGreaterThan(int(read(app, "toggle enabled after-up250"), "off"), 200)
        reset(app)
        drag(app, dy: 250)
        XCTAssertEqual(int(read(app, "toggle enabled after-down250"), "off"), 0)
        app.buttons["sd.toggle"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        reset(app)
        drag(app, dy: -250)
        assertStill(read(app, "toggle disabled after-up250"), "disabled by the button")
        app.buttons["sd.toggle"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        reset(app)
        drag(app, dy: -250)
        XCTAssertGreaterThan(int(read(app, "toggle re-enabled after-up250"), "off"), 200, "enabled again")
    }

    // MARK: inside a sheet (SHEET-s1 V1 / V7: the scroll view kept scrolling)

    func testSheetScrollDisabledStopsTheView() throws {
        let app = try launch(mode: "native", sheet: true)
        let (up, down) = upThenDown(app, "sheet scrollDisabled")
        assertStill(up, "up"); assertStill(down, "down")
    }

    func testSheetMediumScrollDisabledStopsTheView() throws {
        let app = try launch(mode: "native", sheet: true, medium: true)
        let (up, down) = upThenDown(app, "sheet medium scrollDisabled")
        assertStill(up, "up"); assertStill(down, "down")
    }

    func testSheetZtronScrollDisabledStopsTheView() throws {
        let app = try launch(mode: "ztron", sheet: true)
        let (up, down) = upThenDown(app, "sheet ztronScrollDisabled")
        assertStill(up, "up"); assertStill(down, "down")
    }

    // MARK: the "9 pt residual offset" of SHEET-s1 V6b / V8b

    /// A disabled view still follows its viewport (SPEC S7: the visible centre is kept): when the readout above it grows from
    /// nothing to three lines the viewport shrinks by Δ and the offset becomes Δ / 2 (SHEET-s1's readout did exactly this, hence
    /// "9"). The drag itself moves nothing.
    func testDisabledViewFollowsItsViewportNotTheFinger() throws {
        let app = try launch(mode: "native", grow: true)
        let before = element(app, "sd.scroller").frame.height
        reset(app)
        drag(app, dy: -250)
        let r = read(app, "grow after-up250")
        Thread.sleep(forTimeInterval: 0.5)
        let after = element(app, "sd.scroller").frame.height
        let r2 = read(app, "grow settled")
        XCTAssertEqual(int(r, "didScroll"), 0, "the drag moved nothing")
        XCTAssertEqual(int(r, "dragBegan"), 0)
        XCTAssertGreaterThan(before - after, 4, "the readout shrank the viewport")
        XCTAssertEqual(CGFloat(int(r2, "off")), (before - after) / 2, accuracy: 1.5, "the visible centre was kept")
    }
}
