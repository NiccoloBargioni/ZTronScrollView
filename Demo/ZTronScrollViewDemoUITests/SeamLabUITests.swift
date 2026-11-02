import XCTest

/// M8b-3 R5: drives the seam lab (`-ZTronScreen seamlab`) while scripts/seam/measure.sh records the screen; the
/// measurement is scripts/seam/analyze.py on the recording, so these tests assert nothing beyond the launch. The scenario's
/// launch arguments come from `ZS_SEAM_ARGS` (space-separated; xcodebuild passes `TEST_RUNNER_ZS_SEAM_ARGS` through), so
/// one method serves every scenario; `ZS_DEMO_FORCED=1` (scripts/test-demo-ui.sh --forced) adds -ZTronForceAllFallbacks.
final class SeamLabUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var forced: Bool { env["ZS_DEMO_FORCED"] == "1" }
    private var seamArgs: [String] {
        (env["ZS_SEAM_ARGS"] ?? "").split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "seamlab"] + seamArgs + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        print("SEAMLAB args=\(app.launchArguments.joined(separator: " "))")
        return app
    }

    /// `-ZTronSeamInfo 1`: the lab's state line.
    private func info(_ app: XCUIApplication, _ tag: String) {
        let e = app.staticTexts["seam.info"]
        guard e.exists else { return }
        print("SEAMLAB info \(tag): \(e.value as? String ?? "?")")
    }

    /// Portrait rest, landscape (system rotation), portrait again.
    func testRotate() {
        let app = launch()
        XCTAssertTrue(app.buttons["seam.width"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        info(app, "portrait")
        print("SEAMLAB mark landscape \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "landscape")
        print("SEAMLAB mark portrait \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "portrait again")
    }

    /// Landscape rest, portrait (system rotation), landscape again (open item 19: on a horizontal lab the narrowing
    /// rotation takes a leading / trailing hold's gap off the screen, the widening one brings it back).
    func testRotateFromLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch()
        XCTAssertTrue(app.buttons["seam.width"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2.0)
        info(app, "landscape")
        print("SEAMLAB mark portrait \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "portrait")
        print("SEAMLAB mark landscape \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "landscape again")
    }

    /// A pull past the top: press on the content, drag down 220 pt slowly, hold 1.5 s (the finger stays down), release (the
    /// content springs back). `.preserve`: the header moves down with the content (the gap opens above it); `.stretch`: it
    /// grows. Either way its bottom edge stays on the content's top. `-ZTronSeamPullDrag <pt>` (D70: a pull past half the
    /// header's height) drags that far instead, from 25 % of the window's height when it is longer than 220 pt.
    func testPull() {
        let app = launch()
        XCTAssertTrue(app.buttons["seam.width"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        let window = app.windows.firstMatch
        var drag: CGFloat = 220
        if let i = seamArgs.firstIndex(of: "-ZTronSeamPullDrag"), i + 1 < seamArgs.count, let d = Double(seamArgs[i + 1]) {
            drag = CGFloat(d)
        }
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: drag > 220 ? 0.25 : 0.55))
        let end = start.withOffset(CGVector(dx: 0, dy: drag))
        print("SEAMLAB mark pull \(Date().timeIntervalSince1970)")
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 1.5)
        print("SEAMLAB mark release \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 2.0)
    }

    /// A transaction-driven scroll (`withAnimation { state.scroll(to:) }`, easeInOut 1.2 s) from rest to y = 400 (through
    /// the collapse band and past it), then back to rest.
    func testScroll() {
        let app = launch()
        let button = app.buttons["seam.scroll"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        print("SEAMLAB mark far \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "far")
        print("SEAMLAB mark rest \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "rest")
    }

    /// `snapHeader(to: .collapsed, animated: true)`, then `.expanded` (the clock path).
    func testSnap() {
        let app = launch()
        let button = app.buttons["seam.snap"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        print("SEAMLAB mark collapse \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.0)
        print("SEAMLAB mark expand \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.0)
    }

    /// D64 (`-ZTronSeamKeyboard 1`): the system keyboard up (`seam.width` focuses the lab's text field), a system rotation
    /// to landscape and back with it up, then the keyboard down. The keyboard never changes the header's resting height.
    func testKeyboardRotate() {
        let app = launch()
        let button = app.buttons["seam.width"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        info(app, "rest")
        print("SEAMLAB mark keyboard \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "keyboard")
        print("SEAMLAB mark landscape \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "landscape")
        print("SEAMLAB mark portrait \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "portrait")
        print("SEAMLAB mark hide \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "hidden")
    }

    /// Full width, 60 % (animated 1.2 s), full width again. `-ZTronSeamLandscape 1`: in landscape.
    func testWidth() {
        let app = launch()
        let button = app.buttons["seam.width"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        if seamArgs.contains("-ZTronSeamLandscape") {
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 2.5)
        }
        Thread.sleep(forTimeInterval: 1.5)
        print("SEAMLAB mark narrow \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "narrow")
        print("SEAMLAB mark wide \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        info(app, "wide")
    }
}
