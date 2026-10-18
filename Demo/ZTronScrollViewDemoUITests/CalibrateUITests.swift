import XCTest

/// Physics calibration runs (docs/design/PHYSICS-calibration.md). Not assertions: each test drives identical gestures
/// on one variant and the app writes the trajectories to Documents/cal/*.json; scripts/compare-calibration.py reads
/// them. Opt-in via TEST_RUNNER_ZS_CALIBRATE=1.
final class CalibrateUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        // Opt-in (slow, no assertions): TEST_RUNNER_ZS_CALIBRATE=1 scripts/test-demo-ui.sh <dest> -only-testing:…
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ZS_CALIBRATE"] == "1", "set TEST_RUNNER_ZS_CALIBRATE=1")
    }

    private func launch(native: Bool, short: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "calibrate"] + (native ? ["-ZTronCalibrateNative"] : [])
            + (short ? ["-ZTronCalibrateShort"] : [])
        app.launch()
        return app
    }

    private func point(_ app: XCUIApplication, _ f: CGRect, _ ny: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.minY + f.height * ny))
    }

    private func drag(_ app: XCUIApplication, _ f: CGRect, from a: CGFloat, to b: CGFloat, velocity: CGFloat, hold: TimeInterval) {
        point(app, f, a).press(forDuration: 0.05, thenDragTo: point(app, f, b),
                               withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: hold)
    }

    private func run(_ app: XCUIApplication, _ gesture: String, settle: TimeInterval, _ body: (CGRect) -> Void) {
        app.buttons["cal.prep.\(gesture)"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let f = app.descendants(matching: .any)["cal.scroller"].firstMatch.frame
        body(f)
        Thread.sleep(forTimeInterval: settle)
        app.buttons["cal.save"].tap()
        let info = app.staticTexts["cal.info"]
        _ = info.waitForExistence(timeout: 2)
        Thread.sleep(forTimeInterval: 0.3)
        print("CAL \(gesture): \(info.value as? String ?? "?")")
    }

    private func tall(native: Bool) {
        let app = launch(native: native, short: false)
        let h: CGFloat = 600
        run(app, "slow", settle: 2) { f in drag(app, f, from: 0.75, to: 0.25, velocity: 300, hold: 0.5) }
        run(app, "medium", settle: 4) { f in drag(app, f, from: 0.85, to: 0.35, velocity: 1500, hold: 0) }
        run(app, "fast", settle: 6) { f in drag(app, f, from: 0.9, to: 0.1, velocity: 4000, hold: 0) }
        run(app, "edge", settle: 4) { f in drag(app, f, from: 0.85, to: 0.35, velocity: 1500, hold: 0) }
        run(app, "top", settle: 3) { f in drag(app, f, from: 0.2, to: 0.2 + 200 / h, velocity: 400, hold: 0.3) }
        run(app, "catch", settle: 3) { f in
            drag(app, f, from: 0.9, to: 0.1, velocity: 4000, hold: 0)
            Thread.sleep(forTimeInterval: 0.35)
            point(app, f, 0.5).press(forDuration: 0.1)
        }
    }

    private func short(native: Bool) {
        let app = launch(native: native, short: true)
        let h: CGFloat = 600
        run(app, "top", settle: 3) { f in drag(app, f, from: 0.2, to: 0.2 + 200 / h, velocity: 400, hold: 0.3) }
        run(app, "bottom", settle: 3) { f in drag(app, f, from: 0.6, to: 0.6 - 200 / h, velocity: 400, hold: 0.3) }
    }

    func testCalibrateNative() { tall(native: true) }
    func testCalibrateZTron() { tall(native: false) }
    func testCalibrateNativeShort() { short(native: true) }
    func testCalibrateZTronShort() { short(native: false) }
}
