import XCTest

/// DBG-s5 / DBG-s8 (D40, D47, Orchestration open item 12): `ZTronScrollView`s inside a vertical page (`-ZTronScreen mixed`), slow 60 pt vertical / 80 pt horizontal
/// drags, one launch each. `page` is how far the page scrolled (a native page: the carousel's accessibility frame moved; a ZTron page: `py`), `cx` / `ly` the
/// carousel's x offset and the list's y offset. Every case prints a `MIXED ...` line (grep the full log) and asserts what is measured on every OS.
///
/// **Native `ScrollView` page.** Below iOS 26 the page's pan and the library's simultaneous pan both follow the finger, so the page scrolls under a vertical drag that starts
/// on a ZTron view and the ZTron view sees (almost) nothing. From iOS 26 (apps linked against the 26 SDK) a recognized SwiftUI drag ends the page's pan: the ZTron view
/// takes every drag that starts on it, also the vertical one over a horizontal carousel that cannot follow it, so the page does not scroll. That is a limitation of pure
/// SwiftUI (no remedy inside SPEC S2; `docs/progress/DBG-s8.md`), kept as a strict expected failure: the day an OS makes the page scroll, the wrapper goes red.
/// **ZTron page.** The supported nesting: the library's arbiter decides, the same on every OS.
///
/// `ZS_PAN_MODE=simultaneous|gesture|high|adaptive` picks the pan attach (`-ZTronPanGestureMode`), none = the OS default.
final class MixedTopologyUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var mode: String? { ProcessInfo.processInfo.environment["ZS_PAN_MODE"].flatMap { $0.isEmpty ? nil : $0 } }

    override func setUp() { continueAfterFailure = false }

    private struct Moved {
        var page = 0, cx = 0, ly = 0
    }

    private func readout(_ app: XCUIApplication) -> [String: Int] {
        for _ in 0..<3 {
            app.buttons["Info"].tap()
            Thread.sleep(forTimeInterval: 0.4)
            if let s = app.staticTexts["mixedInfo"].value as? String, !s.isEmpty {
                return Dictionary(uniqueKeysWithValues: s.split(separator: " ").compactMap { kv -> (String, Int)? in
                    let p = kv.split(separator: "="); return p.count == 2 ? Int(p[1]).map { (String(p[0]), $0) } : nil
                })
            }
        }
        return [:]
    }

    @discardableResult
    private func drag(_ label: String, over id: String, from start: CGVector = .zero, by delta: CGVector, ztronPage: Bool = false) -> Moved {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "mixed"] + (ztronPage ? ["-ZTronMixedPage", "ztron"] : []) + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (mode.map { ["-ZTronPanGestureMode", $0] } ?? [])
        app.launch()
        let carousel = app.descendants(matching: .any)["mixed.carousel"].firstMatch
        let target = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 8) && target.waitForExistence(timeout: 8), "the mixed page is up")
        let before = carousel.frame.minY
        let a = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(start)
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(delta), withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.0)
        let frameMoved = Int((before - carousel.frame.minY).rounded())   // before the readout: its text changes the height above the page
        let r = readout(app)
        let moved = Moved(page: ztronPage ? (r["py"] ?? -1) : frameMoved, cx: r["cx"] ?? -1, ly: r["ly"] ?? -1)
        print("MIXED \(UIDevice.current.systemVersion) \(forced ? "forced" : "preferred") mode=\(mode ?? "default") \(ztronPage ? "ztron-page" : "native-page") \(label): page=\(moved.page) cx=\(moved.cx) ly=\(moved.ly)")
        return moved
    }

    // MARK: Native ScrollView page

    func testVerticalDragOverTheCarousel() {
        let m = drag("vertical-on-carousel", over: "mixed.carousel", by: CGVector(dx: 0, dy: -60))
        XCTAssertEqual(m.cx, 0, "a horizontal carousel does not follow a vertical drag")
        if #available(iOS 26, *) {
            // The ZTron pan begins in the same touch sample as the page's and SwiftUI wins the tie: the page's pan is dropped (DBG-s8).
            XCTExpectFailure("26+: a recognized SwiftUI drag ends the native page's pan, whatever its axis", strict: true) {
                XCTAssertGreaterThan(m.page, 20, "the page scrolls under the finger")
            }
            XCTAssertLessThanOrEqual(m.page, 2, "the page does not move: this is the limitation, not a harness problem")
        } else {
            XCTAssertGreaterThan(m.page, 20, "the page scrolls under a vertical drag that starts on a horizontal ZTron carousel")
        }
    }

    func testHorizontalDragOverTheCarousel() {
        let m = drag("horizontal-on-carousel", over: "mixed.carousel", by: CGVector(dx: -80, dy: 0))
        XCTAssertGreaterThan(m.cx, 40, "the carousel follows a horizontal drag")
        XCTAssertEqual(m.page, 0, "the page does not move under a horizontal drag")
    }

    func testVerticalDragOverTheList() {
        let m = drag("vertical-on-list", over: "mixed.list", by: CGVector(dx: 0, dy: -60))
        if #available(iOS 26, *) {
            XCTAssertGreaterThan(m.ly, 40, "26+: the list takes the drag that starts on it (the same axis as the page)")
            XCTAssertLessThanOrEqual(m.page, 2, "26+: the page's pan is dropped")
        } else {
            // Both pans follow the finger and the list's gesture space moves with the page: the page wins, the list sees at most a point.
            XCTAssertGreaterThan(m.page, 20, "below 26 the page scrolls under the finger")
            XCTAssertLessThanOrEqual(m.ly, 2, "and the list sees (almost) nothing of it")
        }
    }

    /// The oracle: a drag that starts on a native band (above the carousel) scrolls the page, on every OS and attach.
    func testVerticalDragOverANativeBand() {
        let m = drag("vertical-on-native-band", over: "mixed.carousel", from: CGVector(dx: 0, dy: -90), by: CGVector(dx: 0, dy: -60))
        XCTAssertGreaterThan(m.page, 20, "the page scrolls under a drag that starts on a native band (the harness works)")
    }

    // MARK: ZTronScrollView page (the supported nesting)

    func testZTronPageScrollsUnderAVerticalDragOverTheCarousel() {
        let m = drag("vertical-on-carousel", over: "mixed.carousel", by: CGVector(dx: 0, dy: -60), ztronPage: true)
        XCTAssertGreaterThan(m.page, 20, "the arbiter gives the page the swipe the horizontal carousel cannot follow")
        XCTAssertEqual(m.cx, 0, "and the carousel does not move")
    }

    func testZTronPageLeavesAHorizontalDragToTheCarousel() {
        let m = drag("horizontal-on-carousel", over: "mixed.carousel", by: CGVector(dx: -80, dy: 0), ztronPage: true)
        XCTAssertGreaterThan(m.cx, 40, "the carousel follows a horizontal drag")
        XCTAssertEqual(m.page, 0, "the page does not move")
    }

    func testZTronPageLetsTheListTakeASameAxisDrag() {
        let m = drag("vertical-on-list", over: "mixed.list", by: CGVector(dx: 0, dy: -60), ztronPage: true)
        XCTAssertGreaterThan(m.ly, 40, "the list scrolls (the inner wins while it can move, on every OS)")
        XCTAssertLessThanOrEqual(m.page, 2, "and the page stays")
    }
}
