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
/// BTN-s3 adds `diagonal`: is UIKit's 250 pt/s gate per axis or on the vector? (content 6000 × 6000).
final class ButtonDragSweepUITests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private let holds: [TimeInterval] = [0, 0.05, 0.1, 0.25, 0.5, 1]
    private let speeds: [(String, XCUIGestureVelocity)] = [("slow", .slow), ("default", .default), ("fast", .fast)]

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(env["ZS_BD_SWEEP"] == "1", "set TEST_RUNNER_ZS_BD_SWEEP=1")
    }

    private enum Mode { case presets, threshold, calibration, diagonal }

    /// `presets`: `speeds` × `holds` from both starts. `threshold`: XCUI velocities in pt/s
    /// (`XCUIGestureVelocity(rawValue:)`; the presets are sentinels: slow −20, default −10, fast −30) × holds 0 and 0.25 s,
    /// where UIKit stops flinging. `calibration`: the calibration's medium and fast flings (1500 / 4000 pt/s, docs/design/
    /// PHYSICS-calibration.md) as −300 pt drags from 350 pt in × holds 0, 0.05, 0.25 s. `diagonal` (BTN-s3): 200 pt drags from the
    /// scroller's centre toward the top-left at `angle`° above the horizontal (0 = horizontal, 90 = vertical) × XCUI velocities
    /// along the path, hold 0 (`TEST_RUNNER_ZS_BD_ANGLES` / `ZS_BD_SPEEDS` narrow it); `start=a<angle>`.
    private func sweep(native: Bool, mode: Mode = .presets) {
        let app = XCUIApplication()
        // TEST_RUNNER_ZS_BD_AXES=h|v: a one-axis scroller (BTN-s3: does a diagonal drag's other axis count for the gate?). Its
        // cross axis fits the 500 pt scroller: SwiftUI's one-axis ScrollView takes its content's cross size.
        let axes = env["ZS_BD_AXES"]
        app.launchArguments = ["-ZTronScreen", "buttonDrag", "-ZTronBDWidth", axes == "v" ? "360" : "6000",
                               "-ZTronBDHeight", axes == "h" ? "480" : "6000"]
            + (native ? ["-ZTronBDNative"] : []) + (axes.map { ["-ZTronBDAxes", $0] } ?? [])
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
        let list = { (k: String) in self.env[k]?.split(separator: ",").map(String.init) }
        let speeds: [(String, XCUIGestureVelocity)]
        let holds: [TimeInterval]
        let starts: [(String, CGFloat)]
        var travel: CGFloat = -120
        /// Per start: the drag's direction (unit vector of the finger's motion).
        var direction: [String: CGVector] = [:]
        switch mode {
        case .presets:
            speeds = self.speeds; holds = self.holds; starts = [("centre", f.midX), ("edge", f.minX + 66)]
        case .threshold:
            // TEST_RUNNER_ZS_BD_SPEEDS="230,240" / ZS_BD_HOLDS="0" / ZS_BD_STARTS="edge" narrow the sweep.
            speeds = custom(list("ZS_BD_SPEEDS")?.compactMap { Int($0) } ?? [100, 150, 175, 200, 225, 250, 275, 300, 350, 400, 500])
            holds = list("ZS_BD_HOLDS")?.compactMap { TimeInterval($0) } ?? [0, 0.25]
            starts = [("centre", f.midX), ("edge", f.minX + 66)].filter { list("ZS_BD_STARTS")?.contains($0.0) ?? true }
        case .calibration:
            speeds = custom([1500, 4000]); holds = [0, 0.05, 0.25]; starts = [("long", f.minX + 350)]; travel = -300
        case .diagonal:
            let angles = list("ZS_BD_ANGLES")?.compactMap { Double($0) } ?? [0, 15, 30, 45, 60, 75, 90]
            speeds = custom(list("ZS_BD_SPEEDS")?.compactMap { Int($0) } ?? [350, 400, 450, 500, 600, 700])
            holds = [0]; travel = -200
            starts = angles.map { ("a\(Int($0))", f.midX) }
            for a in angles {
                let r = a * .pi / 180
                direction["a\(Int(a))"] = CGVector(dx: cos(r), dy: sin(r))
            }
        }
        for (start, x) in starts {
            for (name, velocity) in speeds {
                for hold in holds {
                    for run in 0..<repeats {
                        app.buttons["Reset"].tap()
                        Thread.sleep(forTimeInterval: 0.5)
                        let s = origin.withOffset(CGVector(dx: x, dy: f.midY))
                        let d = direction[start] ?? CGVector(dx: 1, dy: 0)
                        s.press(forDuration: 0.05, thenDragTo: s.withOffset(CGVector(dx: travel * d.dx, dy: travel * d.dy)),
                                withVelocity: velocity, thenHoldForDuration: hold)
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

    func testDiagonalNative() { sweep(native: true, mode: .diagonal) }

    func testDiagonalZTron() { sweep(native: false, mode: .diagonal) }
}
