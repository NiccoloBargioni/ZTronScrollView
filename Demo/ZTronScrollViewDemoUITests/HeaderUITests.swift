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

    // MARK: fade (D70)

    /// One screen column (x in points) from `y0` to `y1` as sRGB (0…1) per pixel row, from a screenshot (the pattern of
    /// RefreshUITests' blend check): `(y in points, r, g, b)`.
    private func column(_ app: XCUIApplication, x: CGFloat, from y0: CGFloat, to y1: CGFloat)
        -> [(y: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] {
        guard let cg = XCUIScreen.main.screenshot().image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let scale = CGFloat(w) / app.windows.firstMatch.frame.width
        let col = min(w - 1, max(0, Int(x * scale)))
        return (max(0, Int(y0 * scale))..<min(h, Int(y1 * scale))).map { row in
            let i = (row * w + col) * 4
            return ((CGFloat(row) + 0.5) / scale, CGFloat(px[i]) / 255, CGFloat(px[i + 1]) / 255, CGFloat(px[i + 2]) / 255)
        }
    }

    /// The demo's split (`-ZTronHeaderFade split|split2`): rest `.linear(to: .black, from: 0.4)`, collapse from 0 (black;
    /// split2 pure red), pull nil. The opacity at band position `u` with weight `t` toward the collapse state (`pull`:
    /// toward the nil pull state).
    private func splitAlpha(_ u: CGFloat, t: CGFloat, pull: Bool = false) -> CGFloat {
        let rest = max(0, (u - 0.4) / 0.6), partner = pull ? 0 : min(max(u, 0), 1)
        return (1 - t) * rest + t * partner
    }

    /// Checks the fade over the plain white profile header down the column at `x`, rows `[from, to)` in points, the band
    /// `[bandTop, bandEnd]`: black over white reads `1 − α` (split2: the red top layer's share `b = R − G` and the
    /// coverage `1 − G`). Returns the worst opacity error.
    @discardableResult
    private func checkFade(_ app: XCUIApplication, _ tag: String, x: CGFloat, from: CGFloat, to: CGFloat, bandTop: CGFloat,
                           bandEnd: CGFloat, t: CGFloat, pull: Bool = false, twoColours: Bool = false) -> CGFloat {
        let rows = column(app, x: x, from: from + 2, to: to - 2)
        var worst: CGFloat = 0, worstShare: CGFloat = 0
        for p in rows {
            let u = (p.y - bandTop) / (bandEnd - bandTop)
            let want = splitAlpha(u, t: t, pull: pull)
            if twoColours {
                worst = max(worst, abs((1 - p.g) - want))
                worstShare = max(worstShare, abs((p.r - p.g) - t * min(max(u, 0), 1)))
            } else {
                worst = max(worst, abs((1 - (p.r + p.g + p.b) / 3) - want))
            }
        }
        print("HEADER \(path) fade \(tag): \(rows.count) rows \(from)…\(to), band \(bandTop)…\(bandEnd), t \(t), worst \(worst)"
              + (twoColours ? " share \(worstShare)" : ""))
        XCTAssertGreaterThan(rows.count, 20, "\(tag): rows measured")
        XCTAssertLessThan(worst, 0.05, "\(tag): the drawn opacity is the crossfade (worst \(worst))")
        if twoColours { XCTAssertLessThan(worstShare, 0.05, "\(tag): the collapse colour's share (worst \(worstShare))") }
        return worst
    }

    /// D70 on screen (every path, the forced lane's pixel pattern): the split fade over a plain white profile header,
    /// read from screenshots. At rest the rest gradient; half collapsed half of each (one gradient, no dip); collapsed the
    /// collapse gradient over the 64 pt header; in an `.openGap` refresh hold the rest fades out by `min(1, g / 120)` (the
    /// nil pull state, full at half the 240 pt header); two colours (split2) at half: coverage and the red share; under
    /// `.slideBehind` half covered the band ends at the content's top. No content body, no builder run.
    func testSplitFadeCrossfadesByScrollDirection() {
        var app = launch("profile", ["-ZTronHeaderFade", "split", "-ZTronHeaderPlain", "1", "-ZTronLoadSeconds", "4"])
        let box = element(app, "header.box")
        XCTAssertTrue(box.waitForExistence(timeout: 3))
        var f = box.frame
        let x = f.midX + 40
        checkFade(app, "rest", x: x, from: f.minY, to: f.maxY, bandTop: f.minY, bandEnd: f.maxY, t: 0)
        app.buttons["header.half"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        f = box.frame
        XCTAssertEqual(f.height, 152, accuracy: 1)
        checkFade(app, "half", x: x, from: f.minY, to: f.maxY, bandTop: f.minY, bandEnd: f.maxY, t: 0.5)
        app.buttons["header.collapse"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        f = box.frame
        XCTAssertEqual(f.height, 64, accuracy: 1)
        checkFade(app, "collapsed", x: x, from: f.minY, to: f.maxY, bandTop: f.minY, bandEnd: f.maxY, t: 1)
        app.buttons["header.expand"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let a11y = element(app, "ztron.refresh.a11y.top")
        drag(app, from: (0.5, 0.05), to: (0.5, 0.95), hold: 0.4)
        let holding = Date().addingTimeInterval(3)
        while Date() < holding, (a11y.value as? String) == "Idle" { Thread.sleep(forTimeInterval: 0.1) }
        Thread.sleep(forTimeInterval: 0.6)
        f = box.frame
        let row = element(app, "header.row.0").frame
        let g = row.minY - f.maxY
        XCTAssertGreaterThan(g, 20, "the hold's gap opened below the still header")
        checkFade(app, "hold g \(g)", x: x, from: f.minY, to: f.maxY, bandTop: f.minY, bandEnd: f.maxY,
                  t: min(1, g / 120), pull: true)
        let end = Date().addingTimeInterval(8)
        while Date() < end, (a11y.value as? String) != "Idle" { Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 1.0)
        assertNoBodies(info(app, "fade split"), "fade split")
        app.terminate()

        app = launch("profile", ["-ZTronHeaderFade", "split2", "-ZTronHeaderPlain", "1"])
        app.buttons["header.half"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        f = element(app, "header.box").frame
        checkFade(app, "split2 half", x: x, from: f.minY, to: f.maxY, bandTop: f.minY, bandEnd: f.maxY, t: 0.5,
                  twoColours: true)
        assertNoBodies(info(app, "fade split2"), "fade split2")
        app.terminate()

        app = launch("profile", ["-ZTronHeaderFade", "split", "-ZTronHeaderPlain", "1", "-ZTronHeaderCollapse", "slide"])
        app.buttons["header.half"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        // Read together: the scroller's top (the header is clipped there), the moved header, the content's top.
        let top = element(app, "header.scroller").frame.minY
        f = element(app, "header.box").frame
        let content = element(app, "header.row.0").frame.minY
        XCTAssertEqual(f.minY, top - 60, accuracy: 1, "up by k · c")
        checkFade(app, "slide half", x: x, from: top, to: content, bandTop: f.minY, bandEnd: content, t: 0.5)
        assertNoBodies(info(app, "fade slide"), "fade slide")
    }

    // MARK: app banner (D69's motivating setup)

    /// One screenshot's pixels, read at points (sRGB 0…1).
    private struct Pixels {
        let width: Int, height: Int, scale: CGFloat, bytes: [UInt8]
        func rgb(_ x: CGFloat, _ y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            let c = min(width - 1, max(0, Int(x * scale))), r = min(height - 1, max(0, Int(y * scale)))
            let i = (r * width + c) * 4
            return (CGFloat(bytes[i]) / 255, CGFloat(bytes[i + 1]) / 255, CGFloat(bytes[i + 2]) / 255)
        }
        func lum(_ x: CGFloat, _ y: CGFloat) -> CGFloat { let p = rgb(x, y); return (p.r + p.g + p.b) / 3 }
    }

    private func pixels(_ app: XCUIApplication) -> Pixels? {
        guard let cg = XCUIScreen.main.screenshot().image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Pixels(width: w, height: h, scale: CGFloat(w) / app.windows.firstMatch.frame.width, bytes: px)
    }

    /// The x (points) of the picture's dark grid lines along the screen row `y`: the centres of the runs of pixels darker
    /// than 0.3 (the snapshot's tiles are 0.5 or brighter, its lines 0.12).
    private func gridLines(_ p: Pixels, y: CGFloat, from x0: CGFloat, to x1: CGFloat) -> [CGFloat] {
        var out: [CGFloat] = [], run: [Int] = []
        for c in Int(x0 * p.scale)..<Int(x1 * p.scale) {
            if p.lum(CGFloat(c) / p.scale, y) < 0.3 { run.append(c); continue }
            if !run.isEmpty { out.append((CGFloat(run.first!) + CGFloat(run.last!) + 1) / 2 / p.scale); run = [] }
        }
        return out
    }

    /// The y (points) where the screen column `x` turns from the picture (its fade ends on the dark app background) to the
    /// light rows, scanning down from `y0`: the top of the first pixel brighter than 0.7.
    private func lightEdge(_ p: Pixels, x: CGFloat, from y0: CGFloat, to y1: CGFloat) -> CGFloat? {
        for r in Int(y0 * p.scale)..<Int(y1 * p.scale) where p.lum(x, (CGFloat(r) + 0.5) / p.scale) > 0.7 {
            return CGFloat(r) / p.scale
        }
        return nil
    }

    /// The pixel probe: the picture's grid lines (5 vertical lines at x = (100k + 1) / 600 of its width, k = 1…5) are
    /// scaled by `s` about the screen's centre and its bottom edge is at `bottom` (the light rows begin there).
    private func checkDrawnImage(_ app: XCUIApplication, _ tag: String, top: CGFloat, bottom: CGFloat, width: CGFloat,
                                 scale s: CGFloat) {
        guard let p = pixels(app) else { XCTFail("\(tag): no screenshot"); return }
        let lines = gridLines(p, y: top + 6, from: 4, to: width - 4)
        let want = (1...5).map { k in width / 2 + ((CGFloat(100 * k + 1) / 600) * width - width / 2) * s }
        let edge = lightEdge(p, x: width * 0.25, from: top + (bottom - top) * 0.75, to: bottom + 40)
        print("HEADER \(path) appbanner pixels \(tag): lines \(lines.map { String(format: "%.2f", $0) }) want "
              + "\(want.map { String(format: "%.2f", $0) }) edge \(edge.map { String(format: "%.2f", $0) } ?? "nil") want "
              + String(format: "%.2f", bottom))
        XCTAssertEqual(lines.count, 5, "\(tag): the picture's five grid lines")
        for (got, w) in zip(lines, want) { XCTAssertEqual(got, w, accuracy: 1.5, "\(tag): a grid line scaled by \(s)") }
        XCTAssertEqual(edge ?? -1, bottom, accuracy: 1.5, "\(tag): the drawn bottom edge")
    }

    /// The user's setup (D69, `-ZTronScreen appbanner`): `NavigationView` + `GeometryReader`, `.aspectRatio(16/9, min: 0)`,
    /// `pull: .stretch`, `fade: .linear(to: appBackground)`, `.refit`, an aspect-fit 16:9 `Image` with `maxWidth: .infinity`,
    /// through the current call and the deprecated `scalingBehavior:` one. A finger pull grows the drawn image (its probe's
    /// largest bottom edge and width follow the largest pull); a held pull of 60 pt draws it scaled by (R + 60) / R about its
    /// top centre (probe frame and pixels: the grid lines move out, the bottom edge moves down by 60 onto the content's top);
    /// back at rest it is W × R again. No content body, no header builder run.
    func testAppBannerPullGrowsTheImage() {
        for call in ["current", "deprecated"] {
            let app = launch("appbanner", ["-ZTronAppBannerCall", call])
            let image = element(app, "appbanner.image")
            XCTAssertTrue(image.waitForExistence(timeout: 5))
            let width = app.windows.firstMatch.frame.width
            let top = element(app, "header.scroller").frame.minY
            let rest = image.frame
            let row = element(app, "header.row.0")
            print("HEADER \(path) appbanner \(call) rest image \(rest) scroller top \(top) row0 \(row.frame)")
            XCTAssertEqual(rest.minY, top, accuracy: 1, "\(call): the image's top on the scroll view's top")
            XCTAssertEqual(rest.width, width, accuracy: 1, "\(call): full width at rest")
            XCTAssertEqual(rest.height, width * 9 / 16, accuracy: 1, "\(call): R = W · 9/16")
            XCTAssertEqual(row.frame.minY, rest.maxY, accuracy: 1, "\(call): the content starts at the image's bottom")
            let R = rest.height
            checkDrawnImage(app, "\(call) rest", top: rest.minY, bottom: rest.maxY, width: width, scale: 1)

            if call == "current" {
                // A finger pull: the probe's largest drawn bottom edge / width follow the largest pull.
                drag(app, from: (0.5, 0.3), to: (0.5, 0.6), hold: 0.6)
                Thread.sleep(forTimeInterval: 1.5)
                let i = info(app, "appbanner finger pull")
                let g = i.double("smax")
                XCTAssertGreaterThan(g, 20, "the finger pulled past the top")
                XCTAssertEqual(i.double("bmax"), rest.maxY + g, accuracy: 1.5, "the drawn bottom edge moved down by the pull")
                XCTAssertEqual(i.double("wmax"), width * (R + g) / R, accuracy: 1.5, "the drawn width grew by (R + g) / R")
                XCTAssertEqual(image.frame.maxY, rest.maxY, accuracy: 0.5, "back at rest after the release")
            }

            // A held pull of 60 pt (programmatic): probe frame and pixels.
            app.buttons["appbanner.pull"].tap()
            Thread.sleep(forTimeInterval: 0.8)
            let s = (R + 60) / R
            let pulled = image.frame
            let content = row.frame.minY
            print("HEADER \(path) appbanner \(call) pulled image \(pulled) row0 top \(content)")
            XCTAssertEqual(pulled.minY, rest.minY, accuracy: 1, "\(call): the top stays")
            XCTAssertEqual(pulled.maxY, rest.maxY + 60, accuracy: 1, "\(call): the bottom edge moved down by the pull")
            XCTAssertEqual(pulled.width, width * s, accuracy: 1, "\(call): wider by (R + g) / R")
            XCTAssertEqual(pulled.midX, width / 2, accuracy: 1, "\(call): about the centre")
            XCTAssertEqual(content, pulled.maxY, accuracy: 1, "\(call): the content's top on the image's bottom")
            checkDrawnImage(app, "\(call) pulled 60", top: rest.minY, bottom: rest.maxY + 60, width: width, scale: s)
            assertNoBodies(info(app, "appbanner \(call) pulled"), "appbanner \(call)")

            app.buttons["appbanner.rest"].tap()
            Thread.sleep(forTimeInterval: 0.8)
            let back = image.frame
            XCTAssertEqual(back.maxY, rest.maxY, accuracy: 0.5, "\(call): back at rest")
            XCTAssertEqual(back.width, width, accuracy: 0.5, "\(call): full width again")
            checkDrawnImage(app, "\(call) back", top: rest.minY, bottom: rest.maxY, width: width, scale: 1)
            app.terminate()
        }
    }

    /// D68 risk 5 under a real navigation bar (the appbanner screen, `collapse: .slideBehind(parallax: 1)`): as the header
    /// slides up with the content it is clipped at the scroll view's frame, so nothing of it is drawn over the bar: the bar's
    /// pixels are the same at rest, half covered (the header moved up by R/2, more than the bar's height) and covered.
    func testAppBannerSlideBehindStaysBelowTheBar() {
        let app = launch("appbanner", ["-ZTronAppBannerCollapse", "slide1"])
        let image = element(app, "appbanner.image")
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let width = app.windows.firstMatch.frame.width
        let top = element(app, "header.scroller").frame.minY
        let rest = image.frame
        XCTAssertEqual(rest.minY, top, accuracy: 1)
        // The bar's band: from 40 pt above the scroll view's top (below the status bar) to 2 pt above it.
        func bar() -> [CGFloat] {
            guard let p = pixels(app) else { return [] }
            var out: [CGFloat] = []
            var y = top - 40
            while y < top - 2 {
                var x: CGFloat = 4
                while x < width - 4 { let c = p.rgb(x, y); out += [c.r, c.g, c.b]; x += 2 }
                y += 1
            }
            return out
        }
        let atRest = bar()
        XCTAssertFalse(atRest.isEmpty)
        for (tag, button) in [("half", "header.half"), ("covered", "header.collapse")] {
            app.buttons[button].tap()
            Thread.sleep(forTimeInterval: 1.0)
            // Fully covered, the header is hidden from accessibility (h_v ≤ 0.5): no frame to read.
            let movedTop = image.exists ? image.frame.minY : -.infinity
            let now = bar()
            let worst = zip(atRest, now).map { abs($0 - $1) }.max() ?? 1
            print("HEADER \(path) appbanner slide1 \(tag): image top \(movedTop) scroller top \(top) bar worst diff \(worst)")
            XCTAssertLessThan(movedTop, top - 54, "\(tag): the header moved up past the bar's height (\(movedTop))")
            XCTAssertLessThan(worst, 0.06, "\(tag): nothing of the header is drawn over the bar")
        }
        assertNoBodies(info(app, "appbanner slide1"), "appbanner slide1")
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
