import XCTest

/// BTN-s1 (docs/progress/BTN-s1.md): the Q3-s2 spike drag (press 0.05 s, fast drag by -120 pt, hold 0.05 s) on the
/// two-axis `buttonDrag` screen, on a `ZTronScrollView` and on SwiftUI's own `ScrollView` (`-ZTronBDNative`).
///
/// A drag that starts on a Button moves like one from the background as long as the finger stays on the screen. The spike's
/// "short scroll from a Button" was the Button's position: it sat 66 pt from the screen's left edge, so the -120 pt drag ran
/// off the screen, no touch moved after the edge (native's offset freezes there too), and the lift came ~117 ms later. UIKit
/// flings with the velocity from before that event-free pause; since BTN-s3 so do we (SPEC S6 amendment, D49: the pause
/// never enters the release, a 250 pt/s gate decides whether it decelerates).
final class ButtonDragUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var uikit: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_UIKIT"] == "1" }

    override func setUp() { continueAfterFailure = false }

    private struct Readout {
        var x = 0, taps = 0
        var raw = ""
    }

    /// Where the drag starts: on the Button, or at the scroller's centre (the gradient).
    private enum Start { case button, centre }

    private func launch(native: Bool, leading: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "buttonDrag", "-ZTronBDLeading", "\(leading)"] + (native ? ["-ZTronBDNative"] : [])
            + (forced ? ["-ZTronForceAllFallbacks"] : []) + (uikit ? ["-ZTronForceUIKitObserver"] : [])
        app.launch()
        return app
    }

    private func read(_ app: XCUIApplication) -> Readout {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let s = app.staticTexts["bd.info"].value as? String ?? ""
        func field(_ n: String) -> Int {
            s.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.flatMap { Int($0.dropFirst(n.count + 1)) } ?? -9999
        }
        return Readout(x: field("x"), taps: field("taps"), raw: s)
    }

    /// One fresh launch, one fast drag by -120 pt, read at rest. `leading` places the Button (40 = the spike page's).
    private func drag(native: Bool, from: Start, leading: Int) -> Readout {
        let app = launch(native: native, leading: leading)
        let start: XCUICoordinate
        switch from {
        case .button:
            let button = app.buttons["bd.button"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            start = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        case .centre:
            let scroller = app.descendants(matching: .any)["scroller"].firstMatch
            XCTAssertTrue(scroller.waitForExistence(timeout: 5))
            let f = scroller.frame
            start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY))
        }
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -120, dy: 0)), withVelocity: .fast,
                    thenHoldForDuration: 0.05)
        Thread.sleep(forTimeInterval: 3)
        let r = read(app)
        print("BD \(native ? "native" : "ztron")\(forced ? " forced" : "") from=\(from) leading=\(leading) \(r.raw)")
        app.terminate()
        return r
    }

    /// The Button 160 pt in: the drag ends 26 pt from the screen edge.
    private func compareButtonWithBackground(native: Bool) {
        let button = drag(native: native, from: .button, leading: 160)
        let background = drag(native: native, from: .centre, leading: 160)
        print("BD summary \(native ? "native" : "ztron") button x=\(button.x) background x=\(background.x)")
        XCTAssertEqual(button.taps, 0, "a drag from the Button must not fire it")
        XCTAssertGreaterThan(background.x, 200, "the background drag flings")
        // 27.0 varies run to run (381 / 375, 324 / 382); the defect shape was 64 / 384.
        XCTAssertGreaterThan(Double(button.x), 0.7 * Double(background.x), "a drag from the Button moves like one from the background")
    }

    func testDragFromAButtonMovesLikeFromTheBackground() { compareButtonWithBackground(native: false) }

    /// Baseline lane: SwiftUI's own `ScrollView`, same screen and drag.
    func testNativeDragFromAButtonMovesLikeFromTheBackground() { compareButtonWithBackground(native: true) }

    /// The spike's drag from the Button 40 pt in runs off the screen's left edge (BTN-s1): the content follows the finger
    /// to the edge (64 pt = 74 pt of travel − the 10 pt hysteresis) on both, then no touch moves until the lift. UIKit
    /// flings with the velocity from before that event-free pause, and since BTN-s3 so do we (SPEC S6 amendment, D49; before
    /// it our 64 ms rest timeout zeroed the release and the content rested at 64 pt). 27.0: ours 450, native 475.
    func testDragRunningOffTheScreenEdgeFlingsLikeNative() {
        let ztron = drag(native: false, from: .button, leading: 40)
        let native = drag(native: true, from: .button, leading: 40)
        print("BD summary edge ztron x=\(ztron.x) native x=\(native.x)")
        XCTAssertEqual(ztron.taps, 0)
        XCTAssertEqual(native.taps, 0)
        XCTAssertGreaterThan(native.x, 300, "native flings with the velocity from before the pause")
        XCTAssertGreaterThan(ztron.x, 300, "the event-free pause does not zero the release (SPEC S6 amendment)")
        XCTAssertGreaterThan(Double(ztron.x), 0.7 * Double(native.x), "flings about as far as native")
        XCTAssertLessThan(Double(ztron.x), 1.3 * Double(native.x), "flings about as far as native")
    }
}
