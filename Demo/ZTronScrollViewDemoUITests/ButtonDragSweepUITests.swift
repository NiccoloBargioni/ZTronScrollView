import XCTest

/// BTN-s2 (docs/progress/BTN-s2.md): how `UIScrollView` picks its release velocity when no touch moves between the last
/// movement and the lift, against ZTron. Opt-in (slow, no assertions):
/// `TEST_RUNNER_ZS_BD_SWEEP=1 scripts/test-demo-ui.sh <dest> -only-testing:ZTronScrollViewDemoUITests/ButtonDragSweepUITests`
/// (`TEST_RUNNER_ZS_BD_REPEATS=<n>` repeats every drag).
///
/// One launch per lane, content 6000 pt wide (flings stay clear of the trailing edge). Per drag: "Reset", press 0.05 s,
/// drag by -120 pt at XCUI's slow / default / fast velocity, hold 0 … 1 s, from the scroller's centre (the finger stays on
/// the screen) or 66 pt from its leading edge (the end point is 46 pt off the screen), wait for the rest, print the
/// readouts as one `BDS …` line (`bd.info`; on the native lane also `bd.native`: UIKit's touches, pan velocities, offsets).
final class ButtonDragSweepUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private let holds: [TimeInterval] = [0, 0.05, 0.1, 0.25, 0.5, 1]
    private let speeds: [(String, XCUIGestureVelocity)] = [("slow", .slow), ("default", .default), ("fast", .fast)]

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(env["ZS_BD_SWEEP"] == "1", "set TEST_RUNNER_ZS_BD_SWEEP=1")
    }

    private enum Mode { case presets, threshold, calibration }

    /// `presets`: `speeds` × `holds` from both starts. `threshold`: XCUI velocities in pt/s
    /// (`XCUIGestureVelocity(rawValue:)`; the presets are sentinels: slow −20, default −10, fast −30) × holds 0 and 0.25 s,
    /// where UIKit stops flinging. `calibration`: the calibration's medium and fast flings (1500 / 4000 pt/s, docs/design/
    /// PHYSICS-calibration.md) as −300 pt drags from 350 pt in × holds 0, 0.05, 0.25 s.
    private func sweep(native: Bool, mode: Mode = .presets) {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "buttonDrag", "-ZTronBDWidth", "6000"] + (native ? ["-ZTronBDNative"] : [])
        app.launch()
        let scroller = app.descendants(matching: .any)["scroller"].firstMatch
        XCTAssertTrue(scroller.waitForExistence(timeout: 5))
        let f = scroller.frame
        print("BDS velocities slow=\(XCUIGestureVelocity.slow.rawValue) default=\(XCUIGestureVelocity.default.rawValue)"
              + " fast=\(XCUIGestureVelocity.fast.rawValue) scroller=\(f)")
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let repeats = Int(env["ZS_BD_REPEATS"] ?? "1") ?? 1
        let lane = native ? "native" : "ztron"
        func custom(_ v: [Int]) -> [(String, XCUIGestureVelocity)] { v.map { ("\($0)", XCUIGestureVelocity(rawValue: CGFloat($0))) } }
        let speeds: [(String, XCUIGestureVelocity)]
        let holds: [TimeInterval]
        let starts: [(String, CGFloat)]
        var travel: CGFloat = -120
        switch mode {
        case .presets:
            speeds = self.speeds; holds = self.holds; starts = [("centre", f.midX), ("edge", f.minX + 66)]
        case .threshold:
            // TEST_RUNNER_ZS_BD_SPEEDS="230,240" / ZS_BD_HOLDS="0" / ZS_BD_STARTS="edge" narrow the sweep.
            let list = { (k: String) in self.env[k]?.split(separator: ",").map(String.init) }
            speeds = custom(list("ZS_BD_SPEEDS")?.compactMap { Int($0) } ?? [100, 150, 175, 200, 225, 250, 275, 300, 350, 400, 500])
            holds = list("ZS_BD_HOLDS")?.compactMap { TimeInterval($0) } ?? [0, 0.25]
            starts = [("centre", f.midX), ("edge", f.minX + 66)].filter { list("ZS_BD_STARTS")?.contains($0.0) ?? true }
        case .calibration:
            speeds = custom([1500, 4000]); holds = [0, 0.05, 0.25]; starts = [("long", f.minX + 350)]; travel = -300
        }
        for (start, x) in starts {
            for (name, velocity) in speeds {
                for hold in holds {
                    for run in 0..<repeats {
                        app.buttons["Reset"].tap()
                        Thread.sleep(forTimeInterval: 0.5)
                        let s = origin.withOffset(CGVector(dx: x, dy: f.midY))
                        s.press(forDuration: 0.05, thenDragTo: s.withOffset(CGVector(dx: travel, dy: 0)), withVelocity: velocity,
                                thenHoldForDuration: hold)
                        Thread.sleep(forTimeInterval: 3.5)
                        app.buttons["Snapshot"].tap()
                        Thread.sleep(forTimeInterval: 0.4)
                        let info = app.staticTexts["bd.info"].value as? String ?? ""
                        let nat = native ? (app.staticTexts["bd.native"].value as? String ?? "") : ""
                        print("BDS lane=\(lane) start=\(start) speed=\(name) hold=\(hold) run=\(run) \(info) || \(nat)")
                    }
                }
            }
        }
        app.terminate()
    }

    func testSweepNative() { sweep(native: true) }

    func testSweepZTron() { sweep(native: false) }

    func testThresholdNative() { sweep(native: true, mode: .threshold) }

    func testThresholdZTron() { sweep(native: false, mode: .threshold) }

    func testCalibrationFlingsNative() { sweep(native: true, mode: .calibration) }

    func testCalibrationFlingsZTron() { sweep(native: false, mode: .calibration) }
}
