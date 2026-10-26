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

    /// Portrait rest, landscape (system rotation), portrait again.
    func testRotate() {
        let app = launch()
        XCTAssertTrue(app.buttons["seam.width"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        print("SEAMLAB mark landscape \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2.5)
        print("SEAMLAB mark portrait \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2.5)
    }

    /// A pull past the top: press on the content, drag down 220 pt slowly, hold 1.5 s (the finger stays down), release (the
    /// content springs back). `.preserve`: the header moves down with the content (the gap opens above it); `.stretch`: it
    /// grows. Either way its bottom edge stays on the content's top.
    func testPull() {
        let app = launch()
        XCTAssertTrue(app.buttons["seam.width"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
        let end = start.withOffset(CGVector(dx: 0, dy: 220))
        print("SEAMLAB mark pull \(Date().timeIntervalSince1970)")
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: 300, thenHoldForDuration: 1.5)
        print("SEAMLAB mark release \(Date().timeIntervalSince1970)")
        Thread.sleep(forTimeInterval: 2.0)
    }

    /// Full width, 60 % (animated 1.2 s), full width again.
    func testWidth() {
        let app = launch()
        let button = app.buttons["seam.width"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        print("SEAMLAB mark narrow \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
        print("SEAMLAB mark wide \(Date().timeIntervalSince1970)")
        button.tap()
        Thread.sleep(forTimeInterval: 2.5)
    }
}
