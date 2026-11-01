import XCTest

/// M8b-3: the scaling header in the demo (docs/design/M8b-refresh-header.md §3): profile (`.fixed`, `.preserve`, snapping,
/// a `.system` refresher in the gap, below the still header by default (D65) or above the moving one with
/// `-ZTronHeaderPull followContent`) and banner (`.aspectRatio(16/9)`, `.stretch`, fade, overlay refresher, horizontal axis,
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

    /// D61 (`ZTronHeaderPullBehavior.followContent`, opt-in since D65): under `.preserve` the pull and the refresh hold move
    /// the header down with the content (its height stays R, its bottom edge on the content's top) and the indicator sits in
    /// the gap ABOVE it.
    func testProfileRefreshesInTheGapAboveTheHeader() {
        let app = launch("profile", ["-ZTronLoadSeconds", "4", "-ZTronHeaderPull", "followContent"])
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

    /// D65 (`ZTronHeaderPullBehavior.openGap`, the default): under `.preserve` the pull and the refresh hold leave the header
    /// still at its resting place and height; the gap opens BETWEEN its bottom edge and the content's top, and the indicator
    /// sits in that gap.
    func testProfileOpenGapHeaderStaysStillUnderAPull() {
        let app = launch("profile", ["-ZTronLoadSeconds", "4"])
        let a11y = element(app, "ztron.refresh.a11y.top")
        XCTAssertTrue(a11y.waitForExistence(timeout: 3))
        let rest = element(app, "header.box").frame
        let restRow = element(app, "header.row.0").frame
        drag(app, from: (0.5, 0.05), to: (0.5, 0.95), hold: 0.4)
        let holding = Date().addingTimeInterval(3)
        while Date() < holding, (a11y.value as? String) == "Idle" { Thread.sleep(forTimeInterval: 0.1) }
        Thread.sleep(forTimeInterval: 0.6)
        let header = element(app, "header.box").frame
        let row = element(app, "header.row.0").frame
        print("HEADER \(path) openGap hold: rest \(rest) row0 at rest \(restRow) header \(header) row0 \(row)")
        XCTAssertEqual(header.minY, rest.minY, accuracy: 1, "the header stayed still (its top edge)")
        XCTAssertEqual(header.height, 240, accuracy: 1, "the header kept its resting height")
        XCTAssertEqual(header.maxY, rest.maxY, accuracy: 1, "the header stayed still (its bottom edge)")
        XCTAssertGreaterThan(row.minY, header.maxY + 20, "the gap opened below the header")
        XCTAssertGreaterThan(row.minY, restRow.minY + 20, "the content moved down with the hold")
        let spinner = app.activityIndicators.firstMatch
        if spinner.exists {
            print("HEADER \(path) openGap spinner \(spinner.frame)")
            XCTAssertGreaterThanOrEqual(spinner.frame.minY, header.maxY - 1, "the indicator sits below the header")
            XCTAssertLessThanOrEqual(spinner.frame.maxY, row.minY + 1, "inside the gap, above the content")
        }
        let end = Date().addingTimeInterval(8)
        while Date() < end, (a11y.value as? String) != "Idle" { Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 1.0)
        let after = element(app, "header.box").frame
        XCTAssertEqual(after.minY, rest.minY, accuracy: 1, "at rest again")
        let i = info(app, "openGap")
        XCTAssertEqual(i.counters["refresh.actions"], 1, "one action per pull")
        XCTAssertEqual(i.double("smax"), 0, ".preserve never stretches")
        XCTAssertEqual(i.double("h"), 240, accuracy: 0.5)
        XCTAssertEqual(i.double("p"), 0, accuracy: 0.001)
        assertNoBodies(i, "openGap")
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

    // MARK: slideBehind (D68)

    /// The `header.` identifiers VoiceOver reaches, in VoiceOver's order (the demo's `VoiceOverTree`, read on Info into
    /// `vo.header`): XCUITest also lists elements SwiftUI hides from VoiceOver, so it cannot tell.
    private func voiceOver(_ app: XCUIApplication) -> [String] {
        _ = info(app, "vo")
        let raw = element(app, "vo.header").value as? String ?? ""
        print("HEADER \(path) vo \(raw)")
        return raw.split(separator: ",").map(String.init)
    }

    /// D68: a `.slideBehind` header is drawn behind the content (the container's background slot); the content's hit area
    /// is its own drawn frame, so the header's button works in the band the content leaves uncovered and not where the
    /// content covers it. Banner `.fixed(0…200)` with parallax 0 (the header stays still, its button top-trailing): half
    /// covered the tap counts; with 12 pt left uncovered (the header still visible and hit-testable, the button under the
    /// content) the tap is the content's; uncovered again it counts.
    func testSlideBehindHeaderButtonTapsOnlyWhereUncovered() {
        let app = launch("banner", ["-ZTronHeaderSize", "fixed", "-ZTronHeaderCollapse", "slide0"])
        let button = element(app, "header.button")
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        app.buttons["header.half"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(headerHeight(app), 200, accuracy: 1, "slideBehind keeps the resting height")
        // Frames are read against the scroller's frame read at the same moment: the Info readout above the scroll view
        // wraps onto more lines as it fills, which moves the viewport down.
        func spot() -> XCUICoordinate {
            let f = button.frame
            return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY))
        }
        let top = element(app, "header.scroller").frame.minY
        let frame = button.frame
        print("HEADER \(path) slide button \(frame) scroller top \(top) row0 \(element(app, "header.row.0").frame)")
        spot().tap()
        Thread.sleep(forTimeInterval: 0.3)
        var i = info(app, "slide half")
        XCTAssertEqual(i.double("p"), 0.5, accuracy: 0.001)
        XCTAssertEqual(i.double("taps"), 1, "the button works in the uncovered band")
        app.buttons["header.cover"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        i = info(app, "slide cover")
        XCTAssertEqual(i.double("p"), 0.94, accuracy: 0.001, "12 pt of 200 left uncovered")
        let coverTop = element(app, "header.scroller").frame.minY
        let row0 = element(app, "header.row.0").frame.minY
        print("HEADER \(path) slide cover button \(button.frame) scroller top \(coverTop) row0 \(row0)")
        XCTAssertEqual(button.frame.minY - coverTop, frame.minY - top, accuracy: 1, "parallax 0: the header stays still")
        XCTAssertGreaterThan(row0 - coverTop, 11, "the content's top 12 pt below the header's top")
        XCTAssertLessThan(row0, button.frame.midY - 5, "the content covers the button's centre")
        spot().tap()
        Thread.sleep(forTimeInterval: 0.3)
        i = info(app, "slide covered tap")
        XCTAssertEqual(i.double("taps"), 1, "covered by the content: the tap is the content's, not the header's")
        app.buttons["header.expand"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        spot().tap()
        Thread.sleep(forTimeInterval: 0.3)
        i = info(app, "slide uncovered")
        XCTAssertEqual(i.double("taps"), 2, "uncovered again: the header's button")
        assertNoBodies(i, "slide taps")
    }

    /// D68 on the profile (`.fixed(64…240)`, parallax 0.5, `min` ignored): VoiceOver announces the header before the
    /// content (the background slot keeps the sort priority); half covered the header keeps its 240 pt and its top moved
    /// up by half the covered 120 pt (accessibility frames follow the drawn ones), the content's top 120 pt into it; fully
    /// covered the header leaves VoiceOver (visible height 0). The part moved above the scroll view is neither drawn nor
    /// touchable: the chrome's button there still works.
    func testSlideBehindMovesByTheParallaxAndIsAnnouncedFirst() {
        let app = launch("profile", ["-ZTronHeaderCollapse", "slide"])
        let scroller = element(app, "header.scroller")
        // Frames relative to the scroller's top read at the same moment (the Info readout grows and moves the viewport).
        let rest = element(app, "header.box").frame.offsetBy(dx: 0, dy: -scroller.frame.minY)
        XCTAssertEqual(rest.height, 240, accuracy: 1, "resting height")
        let vo = voiceOver(app)
        let firstRow = vo.firstIndex { $0.hasPrefix("header.row.") } ?? -1
        let lastHeader = vo.lastIndex { !$0.hasPrefix("header.row.") } ?? Int.max
        XCTAssertTrue(vo.contains("header.button") && vo.contains("header.box"), "the header is in VoiceOver's tree: \(vo.prefix(6))")
        XCTAssertTrue(firstRow > 0 && lastHeader < firstRow, "header first, then the content: \(vo.prefix(6))")
        let rowRest = element(app, "header.row.0").frame.minY - scroller.frame.minY
        app.buttons["header.half"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let half = element(app, "header.box").frame.offsetBy(dx: 0, dy: -scroller.frame.minY)
        let rowHalf = element(app, "header.row.0").frame.minY - scroller.frame.minY
        print("HEADER \(path) slide rest \(rest) half \(half) row0 \(rowRest) -> \(rowHalf) (scroller-relative)")
        XCTAssertEqual(half.height, 240, accuracy: 1, "slideBehind keeps R")
        XCTAssertEqual(half.minY, rest.minY - 60, accuracy: 1, "up by k · c = 0.5 · 120")
        XCTAssertEqual(rowHalf, rowRest - 120, accuracy: 1, "the content slid 120 pt over it")
        var i = info(app, "slide half")
        XCTAssertEqual(i.double("p"), 0.5, accuracy: 0.001)
        XCTAssertEqual(i.double("h"), 240, accuracy: 0.5, "the geometry's height is R")
        app.buttons["header.collapse"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let covered = voiceOver(app)
        XCTAssertFalse(covered.contains("header.button") || covered.contains("header.box"),
                       "fully covered: hidden from VoiceOver (\(covered.prefix(4)))")
        i = info(app, "slide covered")
        XCTAssertEqual(i.double("p"), 1, accuracy: 0.001)
        // 12 pt left uncovered (visible, so hit-testable), the header's top is 114 pt above the scroll view, over the
        // chrome; clipped there, it takes no touches there either (the container's content shape): the chrome's Expand
        // button under it still works.
        app.buttons["header.cover"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(info(app, "slide cover").double("p"), 0.95, accuracy: 0.001, "12 pt of 240 left uncovered")
        let expand = app.buttons["header.expand"]
        XCTAssertGreaterThan(expand.frame.maxY, scroller.frame.minY - 114, "Expand is under the header's overflow")
        expand.tap()
        Thread.sleep(forTimeInterval: 1.0)
        i = info(app, "slide expanded")
        XCTAssertEqual(i.double("p"), 0, accuracy: 0.001, "the chrome's button took the tap")
        assertNoBodies(i, "slide profile")
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
