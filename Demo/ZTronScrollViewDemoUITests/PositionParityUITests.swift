import XCTest
import UIKit

/// PARITY-s1 (Orchestration item 9): SwiftUI's position APIs against ours in `PositionParityScreen`, on the same OS. Pane `n` is
/// SwiftUI's `ScrollView` with SwiftUI's modifier, `b` SwiftUI's `ScrollView` under our twin (the native bridge), `z` ours.
final class PositionParityUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var os: String { UIDevice.current.systemVersion }
    private var major: Int { Int(os.split(separator: ".").first ?? "0") ?? 0 }

    override func setUp() { continueAfterFailure = true }

    private func launch(_ section: String, _ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "positionParity", "-ZTronParity", section] + extra + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        Thread.sleep(forTimeInterval: 1.0)
        return app
    }

    struct Info {
        var raw: String
        func string(_ n: String) -> String {
            raw.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.map { String($0.dropFirst(n.count + 1)) } ?? "?"
        }
        func double(_ n: String) -> Double { Double(string(n)) ?? -9999 }
    }

    @discardableResult
    private func info(_ app: XCUIApplication, _ tag: String) -> Info {
        app.buttons["Info"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let raw = app.staticTexts["stateInfo"].value as? String ?? ""
        print("PARITY \(os) \(forced ? "forced" : "preferred") \(tag) | \(raw)")
        return Info(raw: raw)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func drag(_ app: XCUIApplication, _ pane: String, from: CGFloat, to: CGFloat, velocity: XCUIGestureVelocity,
                      hold: TimeInterval, settle: TimeInterval) {
        let e = element(app, "pane.\(pane)")
        e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
            .press(forDuration: 0.05, thenDragTo: e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)), withVelocity: velocity,
                   thenHoldForDuration: hold)
        Thread.sleep(forTimeInterval: settle)
    }

    private func run(_ app: XCUIApplication, _ label: String, _ commands: [String]) {
        for c in commands {
            if c == "Reset" { app.buttons["Reset"].tap() } else { app.buttons["cmd.\(c)"].tap() }
            Thread.sleep(forTimeInterval: 0.9)
            info(app, "\(label) \(c)")
        }
    }

    // MARK: measurement passes (print only)

    private func userScrolls(_ app: XCUIApplication, _ label: String, panes: [String]) {
        app.buttons["Reset"].tap(); Thread.sleep(forTimeInterval: 0.9)
        for pane in panes {
            drag(app, pane, from: 0.85, to: 0.2, velocity: XCUIGestureVelocity(rawValue: 120), hold: 0.3, settle: 1.5)
        }
        info(app, "\(label) slow drags")
        app.buttons["Reset"].tap(); Thread.sleep(forTimeInterval: 0.9)
        for pane in panes {
            drag(app, pane, from: 0.85, to: 0.15, velocity: .fast, hold: 0, settle: 3.0)
        }
        info(app, "\(label) flings")
    }

    func testDumpPosition() {
        let panes = major >= 18 ? ["n", "b", "z"] : ["b", "z"]
        for extra in [["-ZTronParityInset", "0"], ["-ZTronParityInset", "50"], ["-ZTronParityAnchor", "center"]] {
            let app = launch("position", extra)
            let label = "position\(extra.joined())"
            info(app, "\(label) launch")
            run(app, label, ["top", "pt300", "ptNeg", "ptBig", "ptX", "top", "y500", "yNeg", "x50", "y500", "x50", "xy400", "top", "id30",
                             "bottom", "id30", "id30c", "id30b", "id99", "id0", "anim60"])
            run(app, label, ["Reset", "j45", "j60", "j66", "j70", "j87"])
            userScrolls(app, label, panes: panes)
            // Content changes after each kind of request: an id, a point, an edge.
            run(app, label, ["id30", "prepend", "pt300", "prepend", "bottom", "grow", "top", "grow"])
            app.terminate()
        }
    }

    func testDumpID() {
        let panes = major >= 17 ? ["n", "b", "z"] : ["z"]
        for extra in [["-ZTronParityInset", "0"], ["-ZTronParityInset", "50"], ["-ZTronParityAnchor", "center"], ["-ZTronParityLazy", "1"]] {
            let app = launch("id", extra)
            let label = "id\(extra.joined())"
            info(app, "\(label) launch")
            run(app, label, ["id30", "id60", "id99", "id0", "anim45", "nil", "id30"])
            run(app, label, ["Reset", "j45", "j60", "j66", "j70", "j87"])
            userScrolls(app, label, panes: panes)
            run(app, label, ["id30", "prepend", "grow", "nil", "prepend"])
            app.terminate()
        }
    }

    /// Which id a user scroll reports when it stops inside a row: short slow drags from the top land at a few points inside
    /// rows 0 and 1 (SwiftUI's binding vs ours, read with the offsets).
    func testDumpIDSweep() {
        for extra in [["-ZTronParity", "id"], ["-ZTronParity", "id", "-ZTronParityAnchor", "center"],
                      ["-ZTronParity", "position"]] {
            let app = XCUIApplication()
            app.launchArguments = ["-ZTronScreen", "positionParity"] + extra + (forced ? ["-ZTronForceAllFallbacks"] : [])
            app.launch()
            Thread.sleep(forTimeInterval: 1.0)
            let panes = (extra.contains("position") ? (major >= 18 ? ["n", "b", "z"] : ["z"]) : (major >= 17 ? ["n", "b", "z"] : ["z"]))
            for to in [0.72, 0.62, 0.52, 0.42, 0.32] {
                app.buttons["Reset"].tap(); Thread.sleep(forTimeInterval: 0.9)
                for pane in panes {
                    drag(app, pane, from: 0.85, to: to, velocity: XCUIGestureVelocity(rawValue: 80), hold: 0.3, settle: 1.2)
                }
                info(app, "sweep \(extra.joined()) to=\(to)")
            }
            app.terminate()
        }
    }

    /// R5: SwiftUI's view-aligned list next to ours, with SwiftUI's offset read by a probe (`nx`).
    func testDumpAligned() {
        for lazy in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-ZTronScreen", "targets", "-ZTronTargetsSection", "aligned"] + (lazy ? ["-ZTronTargetsLazy"] : [])
                + (forced ? ["-ZTronForceAllFallbacks"] : [])
            app.launch()
            Thread.sleep(forTimeInterval: 1.0)
            for limit in ["never", "byOne", "byFew", "automatic"] {
                app.buttons["limit.\(limit)"].tap()
                app.buttons["Reset"].tap(); Thread.sleep(forTimeInterval: 1.0)
                info(app, "aligned lazy=\(lazy) \(limit) reset")
                for id in ["aligned.native", "aligned.ours"] {
                    let e = element(app, id)
                    e.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                        .press(forDuration: 0.05, thenDragTo: e.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)),
                               withVelocity: .fast, thenHoldForDuration: 0)
                    Thread.sleep(forTimeInterval: 2.5)
                    info(app, "aligned lazy=\(lazy) \(limit) after \(id)")
                }
            }
            app.terminate()
        }
    }

    func testDumpAnchor() {
        let cases: [[String]] = [
            ["-ZTronParityAnchor", "nil"], ["-ZTronParityAnchor", "bottom"], ["-ZTronParityAnchor", "center"],
            ["-ZTronParityAnchor", "bottom", "-ZTronParityInset", "50"],
            ["-ZTronParityAnchor", "bottom", "-ZTronParityRows", "2"], ["-ZTronParityAnchor", "center", "-ZTronParityRows", "2"],
            ["-ZTronParityAnchor", "bottom", "-ZTronParityRole", "initialOffset"],
            ["-ZTronParityAnchor", "bottom", "-ZTronParityRole", "sizeChanges"],
            ["-ZTronParityAnchor", "center", "-ZTronParityRole", "sizeChanges"],
            ["-ZTronParityAnchor", "bottom", "-ZTronParityRole", "alignment", "-ZTronParityRows", "2"],
        ]
        for extra in cases {
            let app = launch("anchor", extra)
            let label = "anchor\(extra.joined())"
            info(app, "\(label) launch")
            for step in ["grow", "shrink", "toBottom", "grow", "toMid", "grow", "prepend", "toTop", "grow", "prepend"] {
                app.buttons["cmd.\(step)"].tap(); Thread.sleep(forTimeInterval: 0.9)
                info(app, "\(label) \(step)")
            }
            app.terminate()
        }
    }
}
