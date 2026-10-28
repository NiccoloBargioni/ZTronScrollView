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

    // MARK: the speed of the pull (user report 2026-10-21: "I pull down slowly, the refresh triggers but only the final part of the view shows")

    /// What the refresher drew and when its state machine moved, from the app's own DEBUG trace (the UI cannot be read while
    /// a finger is down): `leaf` lines are renders of the indicator (pull, progress, mode, visible thickness), `fx` the
    /// engine's effects, `ev` the events it handled.
    private struct Trace {
        let lines: [String]
        func index(_ needle: String, after: Int = -1) -> Int? {
            lines.indices.first { $0 > after && lines[$0].contains(needle) }
        }
        func leaves(_ range: Range<Int>) -> [(pull: Double, vis: Double, mode: String)] {
            lines[range].filter { $0.contains("rf leaf") }.map { Trace.leaf($0) }
        }
        static func number(_ key: String, in line: String) -> Double {
            line.components(separatedBy: " ").first { $0.hasPrefix(key + "=") }.flatMap { Double($0.dropFirst(key.count + 1)) } ?? -9999
        }
        static func leaf(_ line: String) -> (pull: Double, vis: Double, mode: String) {
            let mode = line.components(separatedBy: " ").first { $0.hasPrefix("mode=") }.map { String($0.dropFirst(5)) } ?? "?"
            return (number("pull", in: line), number("vis", in: line), mode)
        }
        /// A leaf line with everything it carries: `p` is the progress the edge reported (printed to 0.1), `look` the retraction look.
        static func detail(_ line: String) -> (pull: Double, vis: Double, mode: String, look: String, p: Double) {
            func text(_ key: String) -> String {
                line.components(separatedBy: " ").first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) } ?? "?"
            }
            return (number("pull", in: line), number("vis", in: line), text("mode"), text("look"), number("p", in: line))
        }
    }

    private func pull(_ app: XCUIApplication, _ velocity: XCUIGestureVelocity, hold: TimeInterval) {
        let list = element(app, "refresh.list")
        let a = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let b = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: velocity, thenHoldForDuration: hold)
    }

    private func readTrace(_ app: XCUIApplication, _ tag: String) -> Trace {
        app.buttons["Info"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let raw = element(app, "refresh.trace").value as? String ?? ""
        let t = Trace(lines: raw.components(separatedBy: "\n").filter { !$0.isEmpty })
        print("REFRESH \(path) trace \(tag) (\(t.lines.count) lines)\n" + t.lines.joined(separator: "\n"))
        return t
    }

    /// One pull at `velocity` on `section`, finger held `hold` seconds at the end (the 0.6 s action returns before the lift of
    /// a slow pull, after the lift of a fast one), then the trace once the refresher rests.
    private func tracedPull(_ section: String, _ velocity: XCUIGestureVelocity, hold: TimeInterval, tag: String) -> (Trace, XCUIApplication) {
        let app = launch(section)
        XCTAssertTrue(a11y(app).waitForExistence(timeout: 3))
        pull(app, velocity, hold: hold)
        XCTAssertTrue(waitFor(8, "Idle again") { mode(app) == "Idle" }, "\(tag): the refresher rests")
        Thread.sleep(forTimeInterval: 1.0)
        return (readTrace(app, tag), app)
    }

    /// The display must not depend on the speed of the pull: revealed in proportion to the pull, whole when the trigger fires,
    /// and still the refreshing look until the finger lifts (a slow pull outlives the 0.6 s action).
    private func assertTheWholeIndicatorShows(_ t: Trace, _ tag: String, indicator: Double = 60) {
        guard let trigger = t.index("fx top trigger") else { return XCTFail("\(tag): the pull never triggered") }
        guard let lift = t.index("ev top lift", after: trigger) else { return XCTFail("\(tag): no lift after the trigger") }
        // 1. Before the trigger the indicator is revealed in proportion to the pull: visible = min(pull, its thickness).
        for l in t.leaves(0..<trigger) where l.mode == "pulling" {
            XCTAssertEqual(l.vis, min(l.pull, indicator), accuracy: 1.0, "\(tag): revealed with the pull (pull \(l.pull))")
        }
        // 2. When the trigger fires it is whole and spinning.
        guard let spin = t.lines.indices.first(where: { $0 >= trigger && t.lines[$0].contains("rf leaf") && t.lines[$0].contains("mode=refreshing") }) else {
            return XCTFail("\(tag): the refreshing look never drew")
        }
        let atTrigger = Trace.leaf(t.lines[spin])
        XCTAssertEqual(atTrigger.vis, min(atTrigger.pull, indicator), accuracy: 1.0, "\(tag): whole when the trigger fires (pull \(atTrigger.pull))")
        XCTAssertGreaterThanOrEqual(atTrigger.vis, indicator - 1, "\(tag): the whole indicator, \(indicator) pt")
        // 3. Until the finger lifts it keeps the refreshing look (no fall back to the pull look under the finger).
        for l in t.leaves(trigger..<lift) {
            XCTAssertEqual(l.mode, "refreshing", "\(tag): still refreshing under the finger (pull \(l.pull))")
            XCTAssertGreaterThanOrEqual(l.vis, min(l.pull, indicator) - 1, "\(tag): still whole under the finger")
        }
    }

    /// The indicator goes back with the content (USER-s6, D39): from the effect that starts the retraction to the one that ends
    /// it, the leaf draws a visible thickness that only shrinks, over several frames, down to (almost) nothing, with the look
    /// that was asked for, while the edge reads `notRefreshing` and `dragPosition` only falls. Before this the leaf was removed on
    /// the frame the progress reset, while the content was still sliding back.
    private func assertTheIndicatorRetracts(_ t: Trace, look: String, _ tag: String) {
        guard let begin = t.lines.indices.first(where: { t.lines[$0].contains("fx top retract(") && !t.lines[$0].contains("retract(nil)") })
        else { return XCTFail("\(tag): the indicator never started to retract") }
        guard let end = t.index("fx top retract(nil)", after: begin) else { return XCTFail("\(tag): the retraction never ended") }
        // The leaf's last frame can land just after the engine saw the content at rest.
        let frames = t.lines[begin..<min(t.lines.count, end + 4)].filter { $0.contains("rf leaf") }.map(Trace.detail)
        let thickness = frames.map { Int($0.vis) }
        XCTAssertGreaterThanOrEqual(frames.count, 4, "\(tag): it thins out over several frames, not at once (\(thickness))")
        for f in frames {
            XCTAssertEqual(f.mode, "notRefreshing", "\(tag): custom views read an idle edge (pull \(f.pull))")
            XCTAssertEqual(f.look, look, "\(tag): the look it keeps (pull \(f.pull))")
        }
        for (a, c) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(c.vis, a.vis + 0.6, "\(tag): never grows back (\(thickness))")
            XCTAssertLessThanOrEqual(c.p, a.p + 0.11, "\(tag): dragPosition only falls (\(a.p) → \(c.p))")
        }
        XCTAssertLessThanOrEqual(frames.last?.vis ?? 99, 4, "\(tag): down to (almost) nothing before it goes (\(thickness))")
        let whole = frames.first?.vis ?? 0
        XCTAssertGreaterThanOrEqual(frames.filter { $0.vis > 1 && $0.vis < whole - 1 }.count, 3,
                                    "\(tag): seen thinner than whole on the way (\(thickness))")
    }

    func testASlowPullShowsTheWholeIndicatorUntilTheLift() {
        continueAfterFailure = true                              // every section reports, not only the first to fail
        for section in ["default", "custom", "system"] {
            let (t, app) = tracedPull(section, .slow, hold: 1.5, tag: "slow \(section)")
            assertTheWholeIndicatorShows(t, "slow \(section)")
            assertTheIndicatorRetracts(t, look: "spinner", "slow \(section)")
            let i = info(app, "slow \(section)")
            XCTAssertEqual(i.counters["refresh.actions"], 1, "slow \(section): one action per pull")
            XCTAssertEqual(i.counters["content.body"], 0)
            XCTAssertEqual(i.double("y"), 0, accuracy: 2, "slow \(section): back at rest")
            app.terminate()
        }
    }

    func testAFastPullShowsTheSameIndicator() {
        let (t, app) = tracedPull("default", .fast, hold: 0.3, tag: "fast default")
        assertTheWholeIndicatorShows(t, "fast default")
        assertTheIndicatorRetracts(t, look: "spinner", "fast default")
        XCTAssertEqual(info(app, "fast").counters["refresh.actions"], 1)
    }

    /// A release below the trigger: the ring / arrow goes back with the content instead of disappearing at the lift, and no
    /// action runs.
    func testAPullLetGoBelowTheTriggerRetractsWithTheContent() {
        continueAfterFailure = true
        for section in ["default", "system", "custom"] {
            let app = launch(section)
            XCTAssertTrue(a11y(app).waitForExistence(timeout: 3))
            drag(app, from: (0.5, 0.08), to: (0.5, 0.36), hold: 0.2)          // about 45 pt of pull, under the 100 pt trigger
            Thread.sleep(forTimeInterval: 1.5)
            let t = readTrace(app, "short \(section)")
            assertTheIndicatorRetracts(t, look: "pull", "short \(section)")
            let i = info(app, "short \(section)")
            XCTAssertEqual(i.counters["refresh.actions"], 0, "short \(section): below the trigger nothing runs")
            XCTAssertEqual(i.counters["content.body"], 0)
            XCTAssertEqual(i.double("y"), 0, accuracy: 2, "short \(section): back at rest")
            app.terminate()
        }
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

    // MARK: drawing

    /// The colour runs (in points) down the screen column at `x` between `y0` and `y1`, from a screenshot: pure colours
    /// by name ("white", "yellow", "magenta", "blue", "green"), anything else "other".
    private func colourRuns(_ app: XCUIApplication, x: CGFloat, from y0: CGFloat, to y1: CGFloat)
        -> [(name: String, from: CGFloat, length: CGFloat)] {
        guard let cg = XCUIScreen.main.screenshot().image.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let scale = CGFloat(w) / app.windows.firstMatch.frame.width
        func name(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> String {
            let hi: (UInt8) -> Bool = { $0 > 200 }, lo: (UInt8) -> Bool = { $0 < 80 }
            switch (hi(r), hi(g), hi(b), lo(r), lo(g), lo(b)) {
            case (true, true, true, _, _, _): return "white"
            case (true, true, _, _, _, true): return "yellow"
            case (true, _, true, _, true, _): return "magenta"
            case (_, _, true, true, true, _): return "blue"
            case (_, true, _, true, _, true): return "green"
            default: return "other"
            }
        }
        let col = min(w - 1, max(0, Int(x * scale)))
        var runs: [(name: String, from: CGFloat, length: CGFloat)] = []
        for row in max(0, Int(y0 * scale))..<min(h, Int(y1 * scale)) {
            let i = (row * w + col) * 4
            let n = name(px[i], px[i + 1], px[i + 2])
            if let last = runs.last, last.name == n {
                runs[runs.count - 1].length += 1 / scale
            } else {
                runs.append((n, CGFloat(row) / scale, 1 / scale))
            }
        }
        return runs
    }

    /// Final check of D65: a custom indicator's blend mode reaches what is behind it in a view without a scaling header,
    /// on every path. The fix of open item 18 (5b32f97) made the indicator box a layer group in every view, and its 15–16
    /// `compositingGroup()` composited the indicator alone: a `.difference` white square stayed white on the forced lane
    /// (17+ and fb1fe59: yellow over the gap's blue, magenta over the content's green). The 15–16 group is now only under
    /// a scaling header, where open item 18 needs it.
    func testACustomIndicatorsBlendModeReachesWhatIsBehindIt() {
        for (section, expected) in [("blend", "yellow"), ("blendOverlay", "magenta")] {
            let app = launch(section)
            app.buttons["refresh.begin"].tap()
            XCTAssertTrue(waitFor(3, "Refreshing") { mode(app) == "Refreshing" }, "\(section): the hold begins")
            Thread.sleep(forTimeInterval: 1.0)
            let list = element(app, "refresh.list").frame
            // The 20 pt probe is centred across the edge, in the hold's gap (or over the content's top, overlay).
            let runs = colourRuns(app, x: list.midX, from: list.minY + 2, to: list.minY + 110)
            let text = runs.filter { $0.length >= 1 }.map { "\($0.name) \(Int($0.from))+\(Int($0.length.rounded()))" }
            print("REFRESH \(path) blend \(section): \(text)")
            XCTAssertTrue(runs.contains { $0.name == expected && $0.length >= 12 },
                          "\(path) \(section): the probe draws \(expected) (blended): \(text)")
            XCTAssertFalse(runs.contains { $0.name == "white" && $0.length >= 6 },
                           "\(path) \(section): the probe is not composited alone (white): \(text)")
            app.buttons["refresh.end"].tap()
            app.terminate()
        }
    }

    /// The identifiers (`refresh.` ones) VoiceOver can reach, from the demo's `VoiceOverTree` (read on Info). XCUITest
    /// lists an element SwiftUI hides from VoiceOver too (`accessibilityHidden` keeps it for automation: same snapshot,
    /// 27.0), so it cannot tell.
    private func voiceOver(_ app: XCUIApplication) -> [String] {
        let raw = info(app, "vo").raw
        guard let r = raw.range(of: " vo=") else { return ["?"] }
        return raw[r.upperBound...].split(separator: ",").map(String.init)
    }

    /// Review of open item 19: a hold scrolled away keeps its custom indicator in the view tree (its box on the content's
    /// edge, clipped), and VoiceOver kept reaching it there, with a frame above the scroll view, over the other controls
    /// (at 37a2cb4 it was removed). It leaves VoiceOver's tree while nothing of it is drawn and comes back with the gap,
    /// still refreshing, the same view.
    func testACustomIndicatorScrolledAwayLeavesTheAccessibilityTree() {
        let app = launch("custom")
        let id = "refresh.custom.mode"
        app.buttons["refresh.begin"].tap()
        XCTAssertTrue(waitFor(3, "Refreshing") { mode(app) == "Refreshing" })
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(voiceOver(app).contains(id), "\(path) held: VoiceOver reaches the custom indicator")
        drag(app, from: (0.5, 0.85), to: (0.5, 0.15))
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertEqual(mode(app), "Refreshing", "still held")
        let away = voiceOver(app)
        XCTAssertFalse(away.contains(id), "\(path) scrolled away: not in VoiceOver's tree (\(away))")
        XCTAssertTrue(away.contains("refresh.begin"), "\(path): the walk reaches the other controls (\(away))")
        drag(app, from: (0.5, 0.15), to: (0.5, 0.85))
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(mode(app), "Refreshing", "still held")
        XCTAssertTrue(voiceOver(app).contains(id), "\(path) back in the gap: VoiceOver reaches it again")
        app.buttons["refresh.end"].tap()
        XCTAssertTrue(waitFor(4, "Idle again") { mode(app) == "Idle" })
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
