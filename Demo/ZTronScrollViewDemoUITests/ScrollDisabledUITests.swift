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
                        grow: Bool = false, anchorTop: Bool = false) throws -> XCUIApplication {
        try XCTSkipIf(nativeScroll && (forced || uikit), "the native variant ignores the fallback switches: preferred run only")
        try XCTSkipIf(medium && ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 16, "detents need iOS 16")
        let app = XCUIApplication()
        var args = ["-ZTronScreen", "scrollDisabled", "-ZTronSDMode", mode]
        if sheet { args.append("-ZTronSDSheet") }
        if medium { args.append("-ZTronSDMedium") }
        if nativeScroll { args.append("-ZTronSDNativeScroll") }
        if grow { args.append("-ZTronSDGrow") }
        if anchorTop { args.append("-ZTronSDAnchorTop") }
        if forced { args.append("-ZTronForceAllFallbacks") }
        if uikit { args.append("-ZTronForceUIKitObserver") }
        // Experiments (DBG-s7): `TEST_RUNNER_ZS_DEMO_PANMODE=gesture|high` attaches the pan the other way (DEBUG `PanGestureMode`).
        if let mode = ProcessInfo.processInfo.environment["ZS_DEMO_PANMODE"], !mode.isEmpty { args += ["-ZTronPanGestureMode", mode] }
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

    /// Reads until two readings in a row agree on the offset and the viewport (a sheet that was dragged settles after the lift).
    @discardableResult
    private func settledRead(_ app: XCUIApplication, _ tag: String) -> [String: String] {
        var last = read(app, tag)
        for _ in 0..<4 {
            let next = read(app, "\(tag) (again)")
            if next["off"] == last["off"], next["vp"] == last["vp"] { return next }
            last = next
        }
        return last
    }

    /// 60 rows of 44 pt (`SDRows`).
    private static let contentHeight: CGFloat = 60 * 44

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

    /// Medium detent (SHEET-s1 V1/V7: the effect-only disabling in a sheet that is not at its largest detent). The enclosing sheet may
    /// take the drag: SwiftUI shares a `.simultaneousGesture` drag with the sheet's own pan on iOS 18.x, so there the sheet expands and
    /// collapses under the finger, while on 17.5, 26.5 and 27.0 it stays put (docs/progress/DBG-s7.md). A viewport that the sheet resizes moves
    /// the offset by the S7 centre rule, which is not what this test is about: the view keeps its top (`-ZTronSDAnchorTop`, S7's one
    /// documented override), so the oracle is the same on every OS: no drag, no callback, offset 0.
    func testSheetMediumScrollDisabledStopsTheView() throws {
        let app = try launch(mode: "native", sheet: true, medium: true, anchorTop: true)
        let (up, down) = upThenDown(app, "sheet medium scrollDisabled")
        assertStill(up, "up"); assertStill(down, "down")
    }

    /// The same shape without the override: the view follows the viewport the sheet gives it (S7: the visible centre stays, so the offset
    /// grows by half of the height lost and shrinks by half of the height gained, clamped), and never follows the finger.
    func testSheetMediumDisabledViewFollowsTheViewportNotTheFinger() throws {
        let app = try launch(mode: "native", sheet: true, medium: true)
        var prev = settledRead(app, "sheet medium start")
        for (name, dy) in [("up250", CGFloat(-250)), ("down250", 250)] {
            reset(app)
            drag(app, dy: dy)
            let next = settledRead(app, "sheet medium after-\(name)")
            XCTAssertEqual(int(next, "dragBegan"), 0, "\(name): no drag began")
            XCTAssertEqual(int(next, "dragEnded"), 0, "\(name): no drag ended")
            let lost = CGFloat(int(prev, "vp") - int(next, "vp"))
            let expected = min(max(CGFloat(int(prev, "off")) + lost / 2, 0), Self.contentHeight - CGFloat(int(next, "vp")))
            XCTAssertEqual(CGFloat(int(next, "off")), expected, accuracy: 2,
                           "\(name): the centre rule (viewport \(int(prev, "vp")) -> \(int(next, "vp")))")
            prev = next
        }
    }

    /// The native baseline in the same sheet: a disabled `ScrollView` does not move its content either (a UIScrollView keeps its offset when
    /// the sheet resizes it, so unlike the test above nothing follows the viewport).
    func testNativeScrollViewScrollDisabledInAMediumSheetStaysStill() throws {
        let app = try launch(mode: "native", sheet: true, medium: true, nativeScroll: true)
        let (up, down) = upThenDown(app, "native sheet medium scrollDisabled")
        XCTAssertEqual(int(up, "nativeOff"), 0, "up"); XCTAssertEqual(int(down, "nativeOff"), 0, "down")
    }

    /// A view presented in a medium sheet starts at its top. On iOS 18.x it does not (measured on 18.0, 18.2, 18.4, 18.5 and 18.6, preferred
    /// and forced): the sheet lays its content out at the large size first and settles at medium, and S7 keeps the visible centre across that
    /// one size change (the first layout itself has no centre rule), so the offset is (large - medium) / 2 before any touch. Expected failure
    /// there until the presentation transient is treated as part of the first layout; `defaultScrollAnchor(.top, for: .sizeChanges)` is the
    /// app-side fix (`testSheetMediumScrollDisabledStopsTheView` runs with it). Strict on the runtimes measured to lay out at the detent
    /// size (17.5, 26.0, 26.5, 27.0); anywhere else (15, 16, 17.0-17.4, 26.1-26.4) it only prints. docs/progress/DBG-s7.md.
    func testSheetMediumStartsAtTheTop() throws {
        let app = try launch(mode: "none", sheet: true, medium: true)
        let r = settledRead(app, "sheet medium start")
        let v = ProcessInfo.processInfo.operatingSystemVersion
        if v.majorVersion == 18 {
            XCTExpectFailure("18.x lays the sheet out large first, then medium; S7 moves the offset across that change (DBG-s7)", strict: true) {
                XCTAssertEqual(int(r, "off"), 0, "the view starts at its top")
            }
            let sizes = (r["sz"] ?? "").split(separator: ">").compactMap { $0.split(separator: "x").last.flatMap { Int($0) } }
            XCTAssertGreaterThan(sizes.count, 1, "the pane was laid out at two sizes")
            if let first = sizes.first, let last = sizes.last {
                XCTAssertEqual(CGFloat(int(r, "off")), CGFloat(first - last) / 2, accuracy: 2, "the offset is the centre rule across \(sizes)")
            }
        } else if (v.majorVersion, v.minorVersion) == (17, 5) || (v.majorVersion == 26 && [0, 5].contains(v.minorVersion)) || v.majorVersion == 27 {
            XCTAssertEqual(int(r, "off"), 0, "the view starts at its top")
        }
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
