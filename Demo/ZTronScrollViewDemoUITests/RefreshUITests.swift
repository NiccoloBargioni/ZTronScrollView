import XCTest

/// M8b-2: the refresher gallery (docs/design/M8b-refresh-header.md §3): pull → spinner → done → rest with one action per
/// pull and no content body, the named accessibility elements, a custom indicator, load more, a horizontal leading refresh,
/// `.refreshable` and the programmatic begin / end. Sections are chosen with `-ZTronRefreshSection`.
final class RefreshUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var path: String { forced ? "forced" : "preferred" }

    override func setUp() { continueAfterFailure = false }

    private func launch(_ section: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "refresh", "-ZTronRefreshSection", section] + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func a11y(_ app: XCUIApplication, _ edge: String = "top") -> XCUIElement {
        element(app, "ztron.refresh.a11y.\(edge)")
    }

    private func mode(_ app: XCUIApplication, _ edge: String = "top") -> String {
        (a11y(app, edge).value as? String) ?? "?"
    }

    private func waitFor(_ timeout: TimeInterval, _ what: String, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        print("REFRESH \(path) timeout waiting for \(what)")
        return false
    }

    /// Press at `from`, drag to `to` (normalized in the list), hold, release. At the default speed the crossing of the
    /// trigger comes late in the drag, so `Refreshing` is still visible after the lift whatever the machine load.
    private func drag(_ app: XCUIApplication, from: (CGFloat, CGFloat), to: (CGFloat, CGFloat), hold: TimeInterval = 0.4) {
        let list = element(app, "refresh.list")
        let a = list.coordinate(withNormalizedOffset: CGVector(dx: from.0, dy: from.1))
        let b = list.coordinate(withNormalizedOffset: CGVector(dx: to.0, dy: to.1))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .default, thenHoldForDuration: hold)
    }

    private func pullDown(_ app: XCUIApplication, hold: TimeInterval = 0.4) {
        drag(app, from: (0.5, 0.08), to: (0.5, 0.92), hold: hold)
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
        for k in ["refresh.actions", "content.body", "refresh.host.body", "chromeLeaf.body"] {
            counters[k] = Int(app.staticTexts["counter.\(k)"].value as? String ?? "") ?? -2
        }
        let raw = app.staticTexts["stateInfo"].value as? String ?? ""
        print("REFRESH \(path) \(tag) \(raw) \(counters.sorted { $0.key < $1.key })")
        return Info(counters: counters, raw: raw)
    }

    // MARK: pull → spinner → done → rest

    private func pullCycle(_ section: String) {
        let app = launch(section)
        XCTAssertTrue(a11y(app).waitForExistence(timeout: 3), "\(section): the refresher's accessibility element exists")
        XCTAssertEqual(mode(app), "Idle")
        pullDown(app)
        XCTAssertTrue(waitFor(3, "Refreshing") { mode(app) == "Refreshing" }, "\(section): the pull starts the refresh")
        XCTAssertTrue(waitFor(6, "Idle again") { mode(app) == "Idle" }, "\(section): the refresh ends and the indicator rests")
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app, section)
        XCTAssertEqual(i.counters["refresh.actions"], 1, "\(section): one action per pull")
        XCTAssertEqual(i.counters["content.body"], 0, "\(section): refreshing never re-evaluates a content body")
        XCTAssertEqual(i.double("y"), 0, accuracy: 2, "\(section): back at rest")
    }

    func testSystemPullSpinsAndRests() { pullCycle("system") }
    func testDefaultLoaderShapePullSpinsAndRests() { pullCycle("default") }
    func testOverlayPullSpinsAndRests() { pullCycle("overlay") }
    func testCompletionHandlerPullSpinsAndRests() { pullCycle("completion") }
    func testRefreshableMapsToTheSystemRefresher() { pullCycle("refreshable") }

    func testAPullDuringARefreshNeverFiresTheAction() {
        let app = launch("system")
        app.buttons["refresh.begin"].tap()                      // a refresh that stays until `End`
        XCTAssertTrue(waitFor(3, "Refreshing") { mode(app) == "Refreshing" })
        pullDown(app, hold: 0.2)
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(mode(app), "Refreshing")
        XCTAssertEqual(info(app, "pull while refreshing").counters["refresh.actions"], 0, "one refresh at a time")
        app.buttons["refresh.end"].tap()
        XCTAssertTrue(waitFor(4, "Idle again") { mode(app) == "Idle" })
    }

    // MARK: the custom indicator

    func testCustomIndicatorFollowsTheModes() {
        let app = launch("custom")
        let custom = element(app, "refresh.custom.mode")
        // A short pull below the trigger (the call returns after the lift): rests, nothing ran.
        drag(app, from: (0.5, 0.08), to: (0.5, 0.32), hold: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(custom.exists, "the indicator is gone at rest")
        XCTAssertEqual(info(app, "short pull").counters["refresh.actions"], 0, "below the trigger nothing runs")
        // A full pull: the view reads `refreshing`, then leaves.
        pullDown(app)
        XCTAssertTrue(waitFor(3, "custom refreshing") { (custom.value as? String) == "refreshing" })
        XCTAssertTrue(waitFor(6, "custom gone") { !custom.exists })
        let i = info(app, "full pull")
        XCTAssertEqual(i.counters["refresh.actions"], 1)
        XCTAssertEqual(i.counters["content.body"], 0)
    }

    // MARK: load more and the leading edge

    func testLoadMoreAppendsRowsAtTheBottomEdge() {
        let app = launch("loadMore")
        XCTAssertEqual(a11y(app, "bottom").label, "Load more")
        XCTAssertEqual(a11y(app, "top").label, "Refresh")
        for _ in 0..<2 { drag(app, from: (0.5, 0.9), to: (0.5, 0.05), hold: 0.0) ; Thread.sleep(forTimeInterval: 1.0) }
        print("REFRESH \(path) before bottom pull \(info(app, "at bottom").raw)")
        drag(app, from: (0.5, 0.92), to: (0.5, 0.08), hold: 0.4)
        XCTAssertTrue(waitFor(3, "Refreshing") { mode(app, "bottom") == "Refreshing" }, "the bottom pull is a load more")
        XCTAssertTrue(waitFor(6, "Idle again") { mode(app, "bottom") == "Idle" })
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app, "load more")
        XCTAssertEqual(i.counters["refresh.actions"], 1)
        XCTAssertEqual(i.double("rows"), 30, "ten rows were appended")
    }

    func testHorizontalViewRefreshesOnTheLeadingEdge() {
        let app = launch("horizontal")
        XCTAssertTrue(a11y(app, "leading").waitForExistence(timeout: 3))
        XCTAssertFalse(a11y(app, "top").exists, "a horizontal view answers its leading edge only")
        let list = element(app, "refresh.list")
        let a = list.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let b = list.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        // The action may return before the lift of a slow drag (then the hold never opens): only the outcome is asserted.
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .default, thenHoldForDuration: 0.1)
        XCTAssertTrue(waitFor(6, "Idle again") { mode(app, "leading") == "Idle" })
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app, "horizontal")
        XCTAssertEqual(i.counters["refresh.actions"], 1)
        XCTAssertEqual(i.counters["content.body"], 0)
        XCTAssertEqual(i.double("x"), 0, accuracy: 2)
    }

    // MARK: programmatic and accessibility

    func testBeginAndEndRefreshingRunNoActionAndHoldTheIndicator() {
        let app = launch("system")
        app.buttons["refresh.begin"].tap()
        XCTAssertTrue(waitFor(3, "Refreshing") { mode(app) == "Refreshing" })
        Thread.sleep(forTimeInterval: 1.0)
        let held = info(app, "begin")
        XCTAssertEqual(held.counters["refresh.actions"], 0, "beginRefreshing runs no action (UIKit parity)")
        XCTAssertLessThan(held.double("y"), -30, "the indicator is revealed: the content holds below the top")
        app.buttons["refresh.end"].tap()
        XCTAssertTrue(waitFor(4, "Idle again") { mode(app) == "Idle" })
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(info(app, "end").double("y"), 0, accuracy: 2)
    }

    func testTheNamedAccessibilityElementsExist() {
        let app = launch("system")
        let e = a11y(app)
        XCTAssertTrue(e.waitForExistence(timeout: 3))
        XCTAssertEqual(e.label, "Refresh")
        XCTAssertEqual(e.value as? String, "Idle")
        XCTAssertFalse(a11y(app, "bottom").exists, "no load more without a bottom refresher")
    }
}
