import XCTest

/// M8b-3: the scaling header in the demo (docs/design/M8b-refresh-header.md §3): profile (`.fixed`, `.preserve`, snapping,
/// a `.system` refresher in the gap) and banner (`.aspectRatio(16/9)`, `.stretch`, fade, overlay refresher, horizontal axis,
/// rotation). Every run checks `header.builder == 0` and `content.body == 0` after its gestures.
final class HeaderUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var path: String { forced ? "forced" : "preferred" }

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func launch(_ screen: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", screen] + extra + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    struct Info {
        var counters: [String: Int]
        var raw: String
        func double(_ n: String) -> Double {
            raw.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.flatMap { Double($0.dropFirst(n.count + 1)) } ?? -9999
        }
    }

    private func info(_ app: XCUIApplication, _ tag: String = "") -> Info {
        app.buttons["Info"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        var counters: [String: Int] = [:]
        for k in ["content.body", "header.builder", "header.frame", "refresh.actions", "header.measure"] {
            counters[k] = Int(app.staticTexts["counter.\(k)"].value as? String ?? "") ?? -2
        }
        let raw = app.staticTexts["stateInfo"].value as? String ?? ""
        print("HEADER \(path) \(tag) \(raw) \(counters.sorted { $0.key < $1.key })")
        return Info(counters: counters, raw: raw)
    }

    /// Press at `from`, drag to `to` (normalized in the scroll view), hold, release.
    private func drag(_ app: XCUIApplication, from: (CGFloat, CGFloat), to: (CGFloat, CGFloat), hold: TimeInterval = 0.3,
                      velocity: XCUIGestureVelocity = .default) {
        let list = element(app, "header.scroller")
        let a = list.coordinate(withNormalizedOffset: CGVector(dx: from.0, dy: from.1))
        let b = list.coordinate(withNormalizedOffset: CGVector(dx: to.0, dy: to.1))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: velocity, thenHoldForDuration: hold)
    }

    /// The header's live frame height (0 when it is hidden from accessibility at h ≤ 0.5).
    private func headerHeight(_ app: XCUIApplication) -> CGFloat {
        let box = element(app, "header.box")
        return box.exists ? box.frame.height : 0
    }

    private func assertNoBodies(_ i: Info, _ tag: String) {
        XCTAssertEqual(i.counters["content.body"], 0, "\(tag): content.body 0")
        XCTAssertEqual(i.counters["header.builder"], 0, "\(tag): header.builder 0")
    }

    // MARK: profile

    func testProfileCollapsesAndSnapsImmediately() {
        let app = launch("profile")
        XCTAssertEqual(headerHeight(app), 240, accuracy: 1, "resting height")
        // A drag that lifts at rest inside the band: the release target snaps to an end of the band.
        drag(app, from: (0.5, 0.75), to: (0.5, 0.6), hold: 0.4)
        Thread.sleep(forTimeInterval: 1.5)
        var i = info(app, "partial drag")
        let p = i.double("p")
        XCTAssertTrue(abs(p) < 0.01 || abs(p - 1) < 0.01, "snapped to a position: p = \(p)")
        // A long swipe collapses it to its minimum.
        app.buttons["header.expand"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        drag(app, from: (0.5, 0.9), to: (0.5, 0.1), hold: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(headerHeight(app), 64, accuracy: 1, "collapsed to min")
        i = info(app, "collapsed")
        XCTAssertEqual(i.double("p"), 1, accuracy: 0.001)
        XCTAssertEqual(i.double("h"), 64, accuracy: 0.01)
        XCTAssertGreaterThan(i.counters["header.frame"] ?? 0, 0, "the frame leaf ran")
        assertNoBodies(i, "profile")
    }

    func testProfileSnapsAfterTheDecelerationEnds() {
        let app = launch("profile", ["-ZTronHeaderSnap", "after"])
        drag(app, from: (0.5, 0.75), to: (0.5, 0.62), hold: 0.4)
        Thread.sleep(forTimeInterval: 2.0)
        let i = info(app, "after")
        let p = i.double("p")
        XCTAssertTrue(abs(p) < 0.01 || abs(p - 1) < 0.01, "animated to a position after the motion rested: p = \(p)")
        assertNoBodies(i, "after")
    }

    /// User decision 2026-10-26: under `.preserve` the pull and the refresh hold move the header down with the content (its
    /// height stays R, its bottom edge on the content's top) and the indicator sits in the gap ABOVE it.
    func testProfileRefreshesInTheGapAboveTheHeader() {
        let app = launch("profile", ["-ZTronLoadSeconds", "4"])
        let a11y = element(app, "ztron.refresh.a11y.top")
        XCTAssertTrue(a11y.waitForExistence(timeout: 3))
        let scroller = element(app, "header.scroller").frame
        let rest = element(app, "header.box").frame
        drag(app, from: (0.5, 0.05), to: (0.5, 0.95), hold: 0.4)
        // While the action runs (4 s), the header rests below the hold.
        let holding = Date().addingTimeInterval(3)
        while Date() < holding, (a11y.value as? String) == "Idle" { Thread.sleep(forTimeInterval: 0.1) }
        Thread.sleep(forTimeInterval: 0.6)
        let header = element(app, "header.box").frame
        let row = element(app, "header.row.0").frame
        print("HEADER \(path) refresh hold: scroller \(scroller) rest \(rest) header \(header) row0 \(row)")
        XCTAssertGreaterThan(header.minY, rest.minY + 20, "the header moved down with the hold (gap above it)")
        XCTAssertEqual(header.height, 240, accuracy: 1, "the header kept its resting height")
        if abs(row.height - 50) < 1 {   // the row's frame (not only its text's)
            XCTAssertEqual(row.minY, header.maxY, accuracy: 1, "the header's bottom edge is the content's top")
        } else {
            XCTAssertGreaterThanOrEqual(row.minY, header.maxY - 1, "the content starts below the header")
        }
        let spinner = app.activityIndicators.firstMatch
        if spinner.exists {
            print("HEADER \(path) spinner \(spinner.frame)")
            XCTAssertLessThanOrEqual(spinner.frame.maxY, header.minY + 1, "the indicator sits above the header")
            XCTAssertGreaterThanOrEqual(spinner.frame.minY, rest.minY - 1, "inside the gap, below the slot's top")
        }
        let end = Date().addingTimeInterval(8)
        while Date() < end, (a11y.value as? String) != "Idle" { Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app, "refresh")
        XCTAssertEqual(i.counters["refresh.actions"], 1, "one action per pull")
        XCTAssertEqual(i.double("smax"), 0, ".preserve never stretches")
        XCTAssertEqual(i.double("h"), 240, accuracy: 0.5, "the header kept its resting height while the gap opened")
        XCTAssertEqual(i.double("p"), 0, accuracy: 0.001)
        assertNoBodies(i, "refresh")
    }

    func testAHeaderButtonWorksAtPartialHeightAndHidesAtZero() {
        let app = launch("banner", ["-ZTronHeaderSize", "fixed"])
        app.buttons["header.half"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(headerHeight(app), 100, accuracy: 1, "half of a 0…200 band")
        let button = element(app, "header.button")
        XCTAssertTrue(button.exists)
        let spot = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        print("HEADER \(path) button frame \(button.frame) hittable \(button.isHittable)")
        spot.tap()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(info(app, "tap").double("taps"), 1, "the header's button works at partial height")
        app.buttons["header.collapse"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let gone = element(app, "header.button")
        XCTAssertFalse(gone.exists && gone.frame.height > 0 && gone.isHittable, "a header at 0 is hidden from accessibility")
        spot.tap()
        Thread.sleep(forTimeInterval: 0.3)
        let i = info(app, "collapsed")
        XCTAssertEqual(i.double("taps"), 1, "a header at 0 is hidden from hit-testing")
        assertNoBodies(i, "button")
    }

    // MARK: banner

    func testBannerStretchesWithThePullAndSpringsBack() {
        let app = launch("banner")
        let width = element(app, "header.scroller").frame.width
        let resting = headerHeight(app)
        XCTAssertEqual(resting, width / (16.0 / 9.0), accuracy: 1, ".aspectRatio(16/9) = W / r")
        // A pull below the refresh trigger: the header grows with the rubber band, then returns with the content.
        drag(app, from: (0.5, 0.1), to: (0.5, 0.35), hold: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        let i = info(app, "stretch")
        XCTAssertGreaterThan(i.double("smax"), 20, "the header grew with the pull")
        XCTAssertEqual(i.double("hmax"), resting + i.double("smax"), accuracy: 1, "grown by exactly the overflow")
        XCTAssertEqual(headerHeight(app), resting, accuracy: 1, "back to rest")
        assertNoBodies(i, "stretch")
    }

    func testBannerOverlayRefresherOverTheStretchedBand() {
        let app = launch("banner")
        let a11y = element(app, "ztron.refresh.a11y.top")
        XCTAssertTrue(a11y.waitForExistence(timeout: 3))
        drag(app, from: (0.5, 0.05), to: (0.5, 0.95), hold: 0.4)
        let end = Date().addingTimeInterval(8)
        while Date() < end, (a11y.value as? String) != "Idle" { Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app, "banner refresh")
        XCTAssertEqual(i.counters["refresh.actions"], 1)
        XCTAssertGreaterThanOrEqual(i.double("smax"), 59, "the hold stretched the header by H")
        assertNoBodies(i, "banner refresh")
    }

    func testBannerOnAHorizontalViewIsAFixedBannerAbove() {
        let app = launch("banner", ["-ZTronBannerAxis", "horizontal"])
        let resting = headerHeight(app)
        XCTAssertGreaterThan(resting, 100)
        drag(app, from: (0.9, 0.8), to: (0.1, 0.8), hold: 0.2)
        Thread.sleep(forTimeInterval: 1.5)
        drag(app, from: (0.5, 0.6), to: (0.5, 0.95), hold: 0.3)       // a vertical pull: no stretch on a horizontal view
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(headerHeight(app), resting, accuracy: 1, "fixed: no collapse, no stretch")
        let header = element(app, "header.box").frame
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'header.row.'")).firstMatch
        XCTAssertTrue(row.exists)
        XCTAssertGreaterThanOrEqual(row.frame.minY, header.maxY - 1, "the content lays out below the banner")
        let i = info(app, "horizontal")
        XCTAssertEqual(i.double("smax"), 0, accuracy: 0.01)
        assertNoBodies(i, "horizontal")
    }

    func testBannerRotationKeepsTheCollapseProgress() {
        let app = launch("banner")
        app.buttons["header.half"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(info(app, "half").double("p"), 0.5, accuracy: 0.01)
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2.0)
        let landscape = info(app, "landscape")
        XCTAssertEqual(landscape.double("p"), 0.5, accuracy: 0.01, "progress kept across the rotation")
        let width = element(app, "header.scroller").frame.width
        XCTAssertEqual(landscape.double("R"), width / (16.0 / 9.0), accuracy: 1, "the new resting height = W / r")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2.0)
        let back = info(app, "portrait")
        XCTAssertEqual(back.double("p"), 0.5, accuracy: 0.01)
        XCTAssertEqual(back.counters["content.body"], 0, "content.body 0 across two rotations")
    }

    /// User decision 2026-10-26: `.ambientBlur` draws a second instance of the header content behind it; that copy is
    /// hidden from accessibility (one button, one box) and from hit-testing (one tap counted), and nothing runs per frame.
    func testAmbientBackgroundIsHiddenAndNeverRunsPerFrame() {
        let app = launch("banner", ["-ZTronHeaderSize", "fixed", "-ZTronHeaderBackground", "ambient"])
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "header.button").count, 1, "the copy's button is hidden")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "header.box").count, 1, "the copy's box is hidden")
        element(app, "header.button").tap()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(info(app, "ambient tap").double("taps"), 1, "one tap: the copy is not hit-testable")
        drag(app, from: (0.5, 0.8), to: (0.5, 0.4), hold: 0.3)
        Thread.sleep(forTimeInterval: 1.0)
        drag(app, from: (0.5, 0.2), to: (0.5, 0.6), hold: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        assertNoBodies(info(app, "ambient"), "ambient")
    }

    func testFitMeasuresTheNaturalHeight() {
        let app = launch("banner", ["-ZTronHeaderSize", "fit"])
        let width = element(app, "header.scroller").frame.width
        XCTAssertEqual(headerHeight(app), width / (16.0 / 9.0), accuracy: 1, ".fit of a 16:9 picture equals .aspectRatio(16/9)")
        drag(app, from: (0.5, 0.8), to: (0.5, 0.5), hold: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        let i = info(app, "fit")
        XCTAssertEqual(i.counters["header.measure"], 0, "no measurement while scrolling")
        assertNoBodies(i, "fit")
    }
}
