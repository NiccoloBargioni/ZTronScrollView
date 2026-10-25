import XCTest
import UIKit

/// M6 session 3: the reader jump menu, `scrollPosition` (edge / id jumps, user write-back), the paging carousel bound by
/// `scrollPosition(id:)`, view-aligned limits next to SwiftUI's, the proxy's first match next to a native
/// `ScrollViewReader`, and `ScrollTargetBehaviorContext.velocity` next to ours (docs/design/M6-targets.md §7, §8 R4/R5).
/// Sections are chosen with the launch argument `-ZTronTargetsSection`.
final class TargetsUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var path: String { forced ? "forced" : "preferred" }

    override func setUp() { continueAfterFailure = false }

    private func launch(_ section: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "targets", "-ZTronTargetsSection", section] + extra + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        reset(app)
        return app
    }

    private func reset(_ app: XCUIApplication) {
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 1.0)
    }

    struct Info {
        var raw: String
        var counters: [String: Int]
        func double(_ n: String) -> Double {
            raw.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.flatMap { Double($0.dropFirst(n.count + 1)) } ?? -9999
        }
        func string(_ n: String) -> String {
            raw.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.map { String($0.dropFirst(n.count + 1)) } ?? ""
        }
    }

    private func info(_ app: XCUIApplication, _ tag: String = "") -> Info {
        app.buttons["Info"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        var counters: [String: Int] = [:]
        for k in ["content.body", "position.writes", "position.applied", "proxy.native"] {
            counters[k] = Int(app.staticTexts["counter.\(k)"].value as? String ?? "") ?? -2
        }
        let raw = app.staticTexts["stateInfo"].value as? String ?? ""
        print("TARGETS \(path) \(tag) \(raw) \(counters.sorted { $0.key < $1.key })")
        return Info(raw: raw, counters: counters)
    }

    /// Any element type: SwiftUI's own `ScrollView` is not an "other element" like our container.
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func coordinate(_ element: XCUIElement, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        element.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func swipe(_ element: XCUIElement, from: (CGFloat, CGFloat), to: (CGFloat, CGFloat), velocity: XCUIGestureVelocity = .default,
                       settle: TimeInterval = 2.0) {
        coordinate(element, from.0, from.1).press(forDuration: 0.05, thenDragTo: coordinate(element, to.0, to.1), withVelocity: velocity,
                                                  thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: settle)
    }

    // MARK: reader

    /// The offset a jump lands at: rows are 44 pt, the list 260 pt tall (content 4400), bounds 0...4140.
    private func expectedY(id: Int, anchor: String) -> Double {
        let top = Double(id) * 44
        let raw: Double
        switch anchor {
        case "top": raw = top
        case "center": raw = top + 22 - 130
        case "bottom": raw = top + 44 - 260
        default: raw = top                                     // nil anchor from the top of the list: the minimal scroll
        }
        return min(max(raw, 0), 4140)
    }

    func testReaderJumpMenu() {
        let app = launch("reader")
        for id in [0, 50, 99] {
            for anchor in ["top", "center", "bottom"] {
                app.buttons["jump.\(id).\(anchor)"].tap()
                Thread.sleep(forTimeInterval: 0.5)
                let i = info(app, "jump \(id) \(anchor)")
                XCTAssertEqual(i.double("y"), expectedY(id: id, anchor: anchor), accuracy: 1.0, "jump \(id) \(anchor)")
            }
        }
        let i = info(app, "end")
        XCTAssertEqual(i.counters["content.body"], 0, "jumps never run a row body")
        XCTAssertEqual(i.counters["proxy.native"], 0)
    }

    func testReaderAnimatedJumpAndUnknownIDs() {
        let app = launch("reader")
        app.buttons["jump.70.center"].tap()                    // the same jump unanimated: the number the animated one must reach
        Thread.sleep(forTimeInterval: 0.6)
        let direct = info(app, "direct 70")
        XCTAssertEqual(direct.double("y"), 70.0 * 44 + 22 - 130, accuracy: 1.0)
        reset(app)
        app.buttons["jump.animated"].tap()
        Thread.sleep(forTimeInterval: 0.25)
        let mid = info(app, "mid")
        // The transaction path ends within a fraction of a point of the target once its animation has finished; a loaded
        // simulator can take longer than the 0.6 s the animation lasts, so poll.
        var end = info(app, "end")
        for _ in 0..<4 where end.string("phase") != "0" || abs(end.double("y") - (70.0 * 44 + 22 - 130)) > 1 {
            Thread.sleep(forTimeInterval: 1.0)
            end = info(app, "end")
        }
        XCTAssertEqual(end.double("y"), 70.0 * 44 + 22 - 130, accuracy: 1.0)
        XCTAssertGreaterThan(mid.double("y"), 0, "the animated jump had started")
        XCTAssertEqual(end.counters["content.body"], 0)
        app.buttons["jump.unknown"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let after = info(app, "unknown")
        XCTAssertEqual(after.double("y"), end.double("y"), accuracy: 0.5, "an unknown id is a no-op")
        XCTAssertEqual(after.counters["proxy.native"], 1, "and goes to the native proxy")
    }

    // MARK: position

    func testPositionJumpsThenUserScrollWritesBack() {
        let app = launch("position")
        app.buttons["pos.bottom"].tap(); Thread.sleep(forTimeInterval: 0.6)
        var i = info(app, "bottom")
        XCTAssertEqual(i.double("y"), 4100, accuracy: 1.0)
        XCTAssertEqual(i.string("edge"), "bottom")
        app.buttons["pos.row30"].tap(); Thread.sleep(forTimeInterval: 0.6)
        i = info(app, "row30")
        XCTAssertEqual(i.double("y"), 30 * 44, accuracy: 1.0)
        XCTAssertEqual(i.string("id"), "30")
        app.buttons["pos.top"].tap(); Thread.sleep(forTimeInterval: 0.6)
        i = info(app, "top")
        XCTAssertEqual(i.double("y"), 0, accuracy: 1.0)
        XCTAssertEqual(i.counters["position.writes"], 0, "programmatic requests never write back")
        XCTAssertEqual(i.string("user"), "0")

        let list = app.otherElements["targets.list"]
        swipe(list, from: (0.5, 0.85), to: (0.5, 0.15), velocity: .fast, settle: 4.0)
        i = info(app, "after fling")
        XCTAssertGreaterThan(i.double("y"), 200)
        XCTAssertEqual(i.string("user"), "1")
        XCTAssertNotEqual(i.string("id"), "nil")
        // SwiftUI's rule (PARITY-s1): the row whose top is nearest the top edge, written once per row passed.
        XCTAssertEqual(Double(i.string("id")) ?? -100, (i.double("y") / 44).rounded(.toNearestOrAwayFromZero), "the reported row")
        XCTAssertGreaterThanOrEqual(i.counters["position.writes"] ?? 0, 2, "a write per row passed")
        XCTAssertEqual(i.counters["content.body"], 0)
    }

    // MARK: carousel

    func testCarouselPageDotsFollowTheSwipeAndTheDotsScroll() {
        let app = launch("carousel")
        let carousel = app.otherElements["targets.carousel"]
        swipe(carousel, from: (0.85, 0.5), to: (0.15, 0.5), velocity: .fast, settle: 2.0)
        var i = info(app, "swipe 1")
        XCTAssertEqual(i.double("x"), 300, accuracy: 1.0)
        XCTAssertEqual(i.string("id"), "1")
        XCTAssertEqual(app.buttons["dot.1"].value as? String, "selected")
        XCTAssertLessThanOrEqual(i.counters["position.writes"] ?? 9, 2)
        XCTAssertGreaterThanOrEqual(i.counters["position.writes"] ?? 0, 1)
        XCTAssertEqual(i.counters["content.body"], 0)

        app.buttons["dot.4"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        i = info(app, "dot 4")
        XCTAssertEqual(i.double("x"), 1200, accuracy: 1.0)
        XCTAssertEqual(i.string("id"), "4")
        app.buttons["dot.0"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        i = info(app, "dot 0")
        XCTAssertEqual(i.double("x"), 0, accuracy: 1.0)
        XCTAssertGreaterThanOrEqual(i.counters["position.applied"] ?? 0, 2)
        XCTAssertEqual(i.counters["content.body"], 0)
    }

    // MARK: view aligned next to SwiftUI's (R5)

    /// R5: the same fling lands on the same cell as SwiftUI's, compared by offset (`nx`, a probe in SwiftUI's content) and by
    /// the id binding. SwiftUI 17.5 never writes the id binding of a non-lazy stack after a user scroll (PARITY-s1, native
    /// defect: that was the "always 0" of M6-s3), so on 17 the ids are compared on a `LazyHStack` too.
    func testViewAlignedLimitsAgainstSwiftUI() {
        let major = Int(UIDevice.current.systemVersion.split(separator: ".").first ?? "0") ?? 0
        for lazy in major >= 18 ? [false] : [false, true] {
            let app = launch("aligned", lazy ? ["-ZTronTargetsLazy"] : [])
            var results: [String] = []
            for limit in ["never", "byOne", "byFew", "automatic"] {
                app.buttons["limit.\(limit)"].tap()
                reset(app)
                // 180 pt = 1.5 cells: the lift lands mid-cell, so `.alwaysByOne` ("the first item beyond the lift") does not
                // flip with a few points of touch slop (a 240 pt drag ends on a cell boundary: 17.5 native gave 2 or 3).
                swipe(app.otherElements["aligned.ours"], from: (0.9, 0.5), to: (0.3, 0.5), velocity: .fast, settle: 2.5)
                swipe(element(app, "aligned.native"), from: (0.9, 0.5), to: (0.3, 0.5), velocity: .fast, settle: 2.5)
                let i = info(app, "limit \(limit) lazy=\(lazy)")
                let ours = i.string("ours"), native = i.string("native")
                results.append("\(limit): ours=\(ours) native=\(native) ox=\(i.double("ox")) nx=\(i.double("nx"))")
                XCTAssertNotEqual(ours, "nil")
                let ox = i.double("ox")
                XCTAssertEqual(ox.truncatingRemainder(dividingBy: 120), 0, accuracy: 1.0, "\(limit): lands on a cell edge (ox \(ox))")
                // The probe sits in SwiftUI's first cell, which a lazy stack drops once it scrolls out: offsets on the eager one.
                // `.never` projects the fling velocity, and the two flings are separate XCUI gestures whose speed drifts on a
                // loaded host (27.0 once: SwiftUI 600, ours 480): one cell of slack there; the capped limits must be exact.
                let slack: Double = limit == "never" ? 121 : 1
                if !lazy { XCTAssertEqual(ox, i.double("nx"), accuracy: slack, "\(limit): the same cell as SwiftUI's") }
                if major >= 18 || lazy {
                    XCTAssertEqual(Double(ours) ?? -9, Double(native) ?? -99, accuracy: limit == "never" ? 1 : 0,
                                   "\(limit): the same id as SwiftUI's binding")
                } else {
                    XCTAssertEqual(native, "0", "17.5: SwiftUI's id binding of a non-lazy stack is not written")
                }
            }
            print("TARGETS R5 \(path) lazy=\(lazy) \(results)")
            app.terminate()
        }
    }

    // MARK: proxy first match against SwiftUI's reader over two scroll views (Open 4)

    func testProxyFirstMatchAgainstNativeReader() {
        let app = launch("twin")
        app.buttons["twin.native"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["twin.ztron"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app, "twin")
        let ztronUpper = i.double("ztronUpper"), ztronLower = i.double("ztronLower")
        // SwiftUI's own scroll views: where does "row 15" sit, at the top of the upper or of the lower one?
        func atTop(_ row: String, _ scroll: String) -> Bool {
            let r = element(app, scroll).frame, t = app.staticTexts[row].frame
            print("TARGETS OPEN4 frames \(row) text=\(t) scroll=\(r)")
            return !t.isEmpty && t.minY >= r.minY - 1 && t.maxY <= r.maxY + 1
        }
        let nativeResolvesUpper = atTop("NU 15", "twin.native.upper") && !atTop("NL 15", "twin.native.lower")
        let nativeResolvesLower = atTop("NL 15", "twin.native.lower") && !atTop("NU 15", "twin.native.upper")
        let ztronResolvesUpper = ztronUpper > 0 && ztronLower == 0
        print("TARGETS OPEN4 \(path) ztron=\(ztronResolvesUpper ? "upper" : "lower") native=\(nativeResolvesUpper ? "upper" : nativeResolvesLower ? "lower" : "?")")
        XCTAssertTrue(nativeResolvesUpper || nativeResolvesLower, "SwiftUI scrolled exactly one scroll view")
        XCTAssertEqual(ztronResolvesUpper, nativeResolvesUpper, "our proxy resolves the same scroll view as SwiftUI's")
    }

    // MARK: R4 — velocity units

    func testNativeAndZTronTargetVelocityUnits() {
        let app = launch("velocity")
        swipe(element(app, "velocity.native"), from: (0.5, 0.85), to: (0.5, 0.15), velocity: .fast, settle: 3.0)
        swipe(app.otherElements["velocity.ours"], from: (0.5, 0.85), to: (0.5, 0.15), velocity: .fast, settle: 3.0)
        let i = info(app, "velocity")
        let native = i.double("native.vy"), ours = i.double("ours.vy")
        print("TARGETS R4 \(path) native.vy=\(native) ours.vy=\(ours) ratio=\(native / ours)")
        XCTAssertGreaterThan(i.double("native.n"), 0)
        XCTAssertGreaterThan(i.double("ours.n"), 0)
        XCTAssertGreaterThan(abs(native), 0)
        XCTAssertGreaterThan(abs(ours), 0)
        XCTAssertEqual(native > 0, ours > 0, "same direction")
        // SwiftUI's context.velocity is points per MILLISECOND (UIKit's unit) and ours is the same (D32).
        XCTAssertEqual(native / ours, 1, accuracy: 0.5, "native \(native) vs ours \(ours)")
    }
}
