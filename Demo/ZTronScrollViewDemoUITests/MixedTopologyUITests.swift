import XCTest

/// DBG-s5 (D40, open item 12): `ZTronScrollView`s inside SwiftUI's own vertical `ScrollView` (`-ZTronScreen mixed`). Characterization,
/// not a contract (like `SheetUITests`): a case passes when the harness worked; what moved is printed as `MIXED ...` lines (grep the
/// full log). Four slow drags, one test (one launch) each: vertical over the horizontal ZTron carousel, horizontal over it, vertical
/// over the ZTron list, vertical over a native band. `page` is how far the native page scrolled (the carousel's accessibility frame
/// moved), `cx` / `ly` the carousel's x offset and the list's y offset. `ZS_PAN_MODE=simultaneous|adaptive|...` picks the pan attach
/// (`-ZTronPanGestureMode`), none = the OS default. Numbers: `docs/progress/DBG-s5.md`.
final class MixedTopologyUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var mode: String? { ProcessInfo.processInfo.environment["ZS_PAN_MODE"] }

    override func setUp() { continueAfterFailure = false }

    private func readout(_ app: XCUIApplication) -> String {
        for _ in 0..<3 {
            app.buttons["Info"].tap()
            Thread.sleep(forTimeInterval: 0.4)
            if let s = app.staticTexts["mixedInfo"].value as? String, !s.isEmpty { return s }
        }
        return "cx=? ly=?"
    }

    @discardableResult
    private func drag(_ label: String, over id: String, from start: CGVector = .zero, by delta: CGVector) -> Int {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "mixed"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (mode.map { ["-ZTronPanGestureMode", $0] } ?? [])
        app.launch()
        let carousel = app.descendants(matching: .any)["mixed.carousel"].firstMatch
        let target = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 8) && target.waitForExistence(timeout: 8), "the mixed page is up")
        let before = carousel.frame.minY
        let a = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(start)
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(delta), withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.0)
        let page = Int((before - carousel.frame.minY).rounded())
        print("MIXED \(UIDevice.current.systemVersion) \(forced ? "forced" : "preferred") mode=\(mode ?? "default") \(label): page=\(page) \(readout(app))")
        return page
    }

    func testVerticalDragOverTheCarousel() { drag("vertical-on-carousel", over: "mixed.carousel", by: CGVector(dx: 0, dy: -60)) }

    func testHorizontalDragOverTheCarousel() { drag("horizontal-on-carousel", over: "mixed.carousel", by: CGVector(dx: -80, dy: 0)) }

    func testVerticalDragOverTheList() { drag("vertical-on-list", over: "mixed.list", by: CGVector(dx: 0, dy: -60)) }

    /// The oracle: a drag that starts on a native band (above the carousel) scrolls the page, on every OS and attach.
    func testVerticalDragOverANativeBand() {
        let page = drag("vertical-on-native-band", over: "mixed.carousel", from: CGVector(dx: 0, dy: -90), by: CGVector(dx: 0, dy: -60))
        XCTAssertGreaterThan(page, 20, "the page scrolls under a drag that starts on a native band (the harness works)")
    }
}
