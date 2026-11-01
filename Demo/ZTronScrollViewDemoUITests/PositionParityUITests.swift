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
        _ = app.buttons["Info"].waitForExistence(timeout: 15)   // a loaded host can show an empty tree for a moment
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

    // MARK: parity assertions

    /// The native offsets measured on 18.6 / 26.5 / 27.0 for the position section's commands (pane 150 pt, 100 rows of
    /// 44 pt, bounds -inset...4250): a point lands at the top of the unobscured area, an id without an anchor scrolls the
    /// least. On 17.5 (no `ScrollPosition`) ours is held to the same numbers.
    static let positionCommands = ["top", "pt300", "ptNeg", "ptBig", "ptX", "top", "y500", "yNeg", "xy400", "top", "id30", "bottom",
                                   "id30", "id30c", "id30b", "id99", "id0", "anim60"]
    static let positionOffsets: [String: [Double]] = [
        "inset0": [0, 300, 0, 4250, 300, 0, 500, 0, 400, 0, 1214, 4250, 1320, 1267, 1214, 4250, 0, 2534],
        "inset50": [-50, 250, -50, 4250, 250, -50, 450, -50, 350, -50, 1214, 4250, 1270, 1242, 1214, 4250, -50, 2534],
        "center": [0, 300, 0, 4250, 300, 0, 500, 0, 400, 0, 1267, 4250, 1267, 1267, 1214, 4250, 0, 2587],
    ]
    static let configs: [String: [String]] = [
        "inset0": [], "inset50": ["-ZTronParityInset", "50"], "center": ["-ZTronParityAnchor", "center"],
    ]

    /// The row SwiftUI reports after a user scroll (26.5 / 27.0 sweep): the row whose anchor point is nearest the anchor point
    /// of the unobscured area (top: the nearest row top; center: the row holding the center); ties go to the later row.
    private func reportedRow(offset: Double, inset: Double, center: Bool) -> Int {
        let top = offset + inset
        let k = center ? ((top + (150 - inset) / 2) / 44).rounded(.down) : (top / 44).rounded(.toNearestOrAwayFromZero)
        return Int(min(max(k, 0), 99))
    }

    private func close(_ i: Info, _ key: String, _ a: String, _ b: String, _ what: String, tolerance: Double = 1) {
        XCTAssertEqual(i.double("\(a).\(key)"), i.double("\(b).\(key)"), accuracy: tolerance, "\(what): \(a).\(key) vs \(b).\(key)")
    }

    func testPositionRequestsMatchSwiftUI() {
        let native = major >= 18 ? ["n", "b"] : [String]()
        for name in ["inset0", "inset50", "center"] {
            let app = launch("position", Self.configs[name]!)
            let expected = Self.positionOffsets[name]!
            for (k, c) in Self.positionCommands.enumerated() {
                app.buttons["cmd.\(c)"].tap(); Thread.sleep(forTimeInterval: 0.9)
                let i = info(app, "position \(name) \(c)")
                // SwiftUI 18.6 / 26.5 ignore asking for the id it is already at with another anchor (`id30c` / `id30b` right
                // after `id30`): a native defect fixed in 27.0; ours re-applies, like 27.0.
                let sameIDIgnored = major < 27 && (c == "id30c" || c == "id30b")
                for p in native + ["z"] {
                    let want = sameIDIgnored && p != "z" ? expected[12] : expected[k]
                    XCTAssertEqual(i.double("\(p).oy"), want, accuracy: 1, "\(name) \(c): pane \(p)")
                }
                for p in native where p != "n" { close(i, "dy", p, "n", "\(name) \(c) drawn") }
                if native.contains("n") {
                    for key in ["id", "pt", "edge", "user"] {
                        XCTAssertEqual(i.string("z.\(key)"), i.string("n.\(key)"), "\(name) \(c): \(key) ours vs SwiftUI")
                        XCTAssertEqual(i.string("b.\(key)"), i.string("n.\(key)"), "\(name) \(c): \(key) bridge vs SwiftUI")
                    }
                    if major >= 26 {
                        for key in ["x", "y"] { XCTAssertEqual(i.string("z.\(key)"), i.string("n.\(key)"), "\(name) \(c): \(key)") }
                    }
                    if !sameIDIgnored { XCTAssertEqual(i.string("z.vis"), i.string("n.vis"), "\(name) \(c): visible targets") }
                }
            }
            // `scrollTo(x:)` on a vertical view: SwiftUI (18.6, 27.0) moves y to offset 0, a native defect; ours keeps y.
            app.buttons["cmd.y500"].tap(); Thread.sleep(forTimeInterval: 0.9)
            app.buttons["cmd.x50"].tap(); Thread.sleep(forTimeInterval: 0.9)
            let x = info(app, "position \(name) x50 after y500")
            XCTAssertEqual(x.double("z.oy"), 500 - (name == "inset50" ? 50 : 0), accuracy: 1, "\(name): one axis keeps the other")
            app.terminate()
        }
    }

    func testPositionUserScrollWritesLikeSwiftUI() {
        let panes = major >= 18 ? ["n", "b", "z"] : ["z"]
        for name in ["inset0", "inset50", "center"] {
            let app = launch("position", Self.configs[name]!)
            let inset: Double = name == "inset50" ? 50 : 0
            for (gesture, velocity, to) in [("slow", XCUIGestureVelocity(rawValue: 120), 0.2), ("fling", .fast, 0.15)] {
                app.buttons["Reset"].tap(); Thread.sleep(forTimeInterval: 1.0)
                for p in panes { drag(app, p, from: 0.85, to: to, velocity: velocity, hold: gesture == "slow" ? 0.3 : 0, settle: 3.0) }
                let i = info(app, "position \(name) \(gesture)")
                for p in panes {
                    let row = reportedRow(offset: i.double("\(p).oy"), inset: inset, center: name == "center")
                    XCTAssertEqual(i.string("\(p).id"), "\(row)", "\(name) \(gesture): pane \(p) reports the nearest row")
                    XCTAssertEqual(i.string("\(p).pt"), "nil", "\(name) \(gesture): pane \(p) writes no point")
                }
                XCTAssertGreaterThanOrEqual(Int(i.string("z.w")) ?? 0, 3, "\(name) \(gesture): a write per row passed")
                XCTAssertEqual(i.string("z.user"), "1", "isPositionedByUser after a user scroll")
                if major >= 18 {
                    // SwiftUI leaves isPositionedByUser false once it writes a view id (documented defect, PARITY-s1).
                    XCTAssertEqual(i.string("n.user"), "0")
                    XCTAssertEqual(i.string("b.user"), i.string("n.user"), "the bridge carries SwiftUI's value")
                }
            }
            app.terminate()
        }
    }

    static let idCommands = ["id30", "id60", "id99", "id0", "anim45", "nil", "id30"]
    static let idOffsets: [String: [Double]] = [
        "inset0": [1214, 2534, 4250, 0, 1874, 1874, 1320],
        "inset50": [1214, 2534, 4250, -50, 1874, 1874, 1270],
        "center": [1267, 2587, 4250, 0, 1927, 1927, 1267],
        "lazy": [1214, 2534, 4250, 0, 1874, 1874, 1320],
    ]
    /// SwiftUI 17.5 puts the named row at the top when the id binding has no anchor (18+ scrolls the least, D55).
    static let idOffsets17: [String: [Double]] = [
        "inset0": [1320, 2640, 4250, 0, 1980, 1980, 1320],
        "inset50": [1270, 2590, 4250, -50, 1930, 1930, 1270],
        "center": [1267, 2587, 4250, 0, 1927, 1927, 1267],
        "lazy": [1320, 2640, 4250, 0, 1980, 1980, 1320],
    ]

    func testIDBindingMatchesSwiftUI() {
        let native = major >= 17
        var configs = Self.configs
        configs["lazy"] = ["-ZTronParityLazy", "1"]
        for name in ["inset0", "inset50", "center", "lazy"] {
            let app = launch("id", configs[name]!)
            let inset: Double = name == "inset50" ? 50 : 0
            for (k, c) in Self.idCommands.enumerated() {
                app.buttons["cmd.\(c)"].tap(); Thread.sleep(forTimeInterval: 0.9)
                let i = info(app, "id \(name) \(c)")
                XCTAssertEqual(i.double("z.oy"), (major < 18 ? Self.idOffsets17 : Self.idOffsets)[name]![k], accuracy: 1, "\(name) \(c): ours")
                if native {
                    // SwiftUI's offset: its own geometry on 18+, else the probe in its first row (stale in a lazy stack once
                    // that row is dropped, so not read there).
                    if major >= 18 {
                        close(i, "oy", "z", "n", "\(name) \(c) offset")
                        close(i, "oy", "b", "n", "\(name) \(c) offset (twin)")
                    } else if name != "lazy" {
                        close(i, "dy", "z", "n", "\(name) \(c) drawn")
                        close(i, "dy", "b", "n", "\(name) \(c) drawn (twin)")
                    }
                    XCTAssertEqual(i.string("z.id"), i.string("n.id"), "\(name) \(c): id")
                    XCTAssertEqual(i.string("b.id"), i.string("n.id"), "\(name) \(c): id (twin)")
                }
            }
            app.buttons["Reset"].tap(); Thread.sleep(forTimeInterval: 1.0)
            let panes = native ? ["n", "b", "z"] : ["z"]
            for p in panes { drag(app, p, from: 0.85, to: 0.2, velocity: XCUIGestureVelocity(rawValue: 120), hold: 0.3, settle: 2.0) }
            let i = info(app, "id \(name) slow drags")
            for p in panes {
                // 17.5 has no SwiftUI offset readout but the probe: dy = inset − offset (non-lazy panes).
                let offset = major >= 18 || p == "z" ? i.double("\(p).oy") : inset - i.double("\(p).dy")
                let row = reportedRow(offset: offset, inset: inset, center: name == "center")
                if p != "z", major < 18, name == "lazy" { continue }    // lazy: the probe row is gone, nothing to compare with
                if p != "z", major < 18 {
                    // SwiftUI 17.5 never writes the id binding of a non-lazy stack after a user scroll (native defect).
                    XCTAssertEqual(i.string("\(p).id"), "0", "\(name): 17.5 native id binding stays")
                } else {
                    XCTAssertEqual(i.string("\(p).id"), "\(row)", "\(name): pane \(p) reports the nearest row")
                }
            }
            app.terminate()
        }
    }

    static let anchorSteps = ["grow", "shrink", "toBottom", "grow", "toMid", "grow", "prepend", "toTop", "grow", "prepend"]
    static let anchorCases: [(String, [String])] = [
        ("nil", ["-ZTronParityAnchor", "nil"]), ("bottom", ["-ZTronParityAnchor", "bottom"]), ("center", ["-ZTronParityAnchor", "center"]),
        ("bottom50", ["-ZTronParityAnchor", "bottom", "-ZTronParityInset", "50"]),
        ("bottomFit", ["-ZTronParityAnchor", "bottom", "-ZTronParityRows", "2"]), ("centerFit", ["-ZTronParityAnchor", "center", "-ZTronParityRows", "2"]),
        ("initialOffset", ["-ZTronParityAnchor", "bottom", "-ZTronParityRole", "initialOffset"]),
        ("sizeChanges", ["-ZTronParityAnchor", "bottom", "-ZTronParityRole", "sizeChanges"]),
        ("alignmentFit", ["-ZTronParityAnchor", "bottom", "-ZTronParityRole", "alignment", "-ZTronParityRows", "2"]),
    ]

    /// Steps where SwiftUI 17.5 behaves differently from 18.6+ and ours follows 18.6+ (PARITY-s1, D52): a center anchor keeps
    /// the offset as a fraction of the range on any content change, content that fitted is not re-aligned after it shrank
    /// back; `(_:for:)` roles do not exist on 17 (SwiftUI's pane has no anchor for `sizeChanges` / `alignment`).
    private func divergence17(_ name: String, step k: Int) -> String? {
        guard major < 18 else { return nil }
        if ["initialOffset", "sizeChanges", "alignmentFit"].contains(name) { return "17: no role modifier on SwiftUI's side" }
        if name == "center", [3, 5, 6].contains(k) { return "17.5: a center anchor keeps the offset fraction" }
        if name == "centerFit", [5, 6].contains(k) { return "17.5: a center anchor keeps the offset fraction" }
        if name.hasSuffix("Fit"), [1, 2].contains(k) { return "17.5: fitted content is not re-aligned after it shrinks back" }
        return nil
    }

    func testDefaultScrollAnchorMatchesSwiftUI() throws {
        try XCTSkipIf(major < 17, "defaultScrollAnchor needs iOS 17 on SwiftUI's side")
        for (name, extra) in Self.anchorCases {
            let app = launch("anchor", extra)
            for (k, step) in (["launch"] + Self.anchorSteps).enumerated() {
                if step != "launch" { app.buttons["cmd.\(step)"].tap(); Thread.sleep(forTimeInterval: 0.9) }
                let i = info(app, "anchor \(name) \(step)")
                close(i, "dy", "b", "n", "\(name) \(step): twin")
                if let reason = divergence17(name, step: k - 1) {
                    XCTExpectFailure(reason, strict: false) { close(i, "dy", "z", "n", "\(name) \(step)") }
                } else {
                    close(i, "dy", "z", "n", "\(name) \(step)")
                }
            }
            app.terminate()
        }
    }

    // MARK: measurement passes (print only; ZS_PARITY_DUMP=1)

    private func requireDump() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ZS_PARITY_DUMP"] == "1", "measurement pass: set ZS_PARITY_DUMP=1")
    }

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

    func testDumpPosition() throws {
        try requireDump()
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

    func testDumpID() throws {
        try requireDump()
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
    func testDumpIDSweep() throws {
        try requireDump()
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
    func testDumpAligned() throws {
        try requireDump()
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

    func testDumpAnchor() throws {
        try requireDump()
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
