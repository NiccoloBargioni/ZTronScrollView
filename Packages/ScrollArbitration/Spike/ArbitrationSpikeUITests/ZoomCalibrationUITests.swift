import XCTest

/// Records native UIScrollView zoom animations (opt-in, slow, no assertions):
/// `TEST_RUNNER_ZS_CALIBRATE=1 ZS_DEST='id=<udid>' scripts/test-spike.sh -only-testing:ArbitrationSpikeUITests/ZoomCalibrationUITests`
/// then `scripts/fetch-calibration.sh <udid> <dir> dev.ztron.ArbitrationSpike` and `scripts/compare-zoom-calibration.py <dir>`.
final class ZoomCalibrationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ZS_CALIBRATE"] == "1", "set TEST_RUNNER_ZS_CALIBRATE=1")
    }

    func testNativeZoomAnimations() {
        let app = XCUIApplication()
        app.launchArguments = ["-zoomCal"]
        app.launch()
        Thread.sleep(forTimeInterval: 1.0)
        func tap(_ name: String) { app.buttons["zoomcal.\(name)"].tap() }
        func run(_ name: String) {
            tap(name)
            Thread.sleep(forTimeInterval: 2.5)
            tap("save")
            Thread.sleep(forTimeInterval: 0.3)
            print("ZOOMCAL \(name): \(app.staticTexts["zoomcal.info"].value as? String ?? app.staticTexts["zoomcal.info"].label)")
        }
        for n in ["set125", "set15", "set2", "set3", "set4", "set8"] {
            tap("reset"); Thread.sleep(forTimeInterval: 0.5)
            run(n)
            run("back")                       // back-from-N: setZoomScale(1, animated: true)
        }
        tap("reset"); Thread.sleep(forTimeInterval: 0.5)
        run("set2"); run("set4"); run("set8") // 2 -> 4 and 4 -> 8: same ratio as 1 -> 2, other deltas
        run("set2")                           // 8 -> 2
        tap("reset"); Thread.sleep(forTimeInterval: 0.5)
        run("rect8")                          // zoom(to:animated:), the double tap
        run("back")
    }
}
