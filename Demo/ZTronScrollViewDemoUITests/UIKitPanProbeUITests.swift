import XCTest

/// UIKITPAN-s1 measurement harness (spike U1, docs/design/UIKIT-pan.md §4, handoff docs/progress/UIKITPAN-s1.md): not a contract.
/// Every row prints one `UKP q=<Q> os=<os> ...` line with the app's own readings (grep the full log; `scripts/uikitpan-table.py`
/// turns the lines into the per-lane tables and verdicts). A test fails only when the harness did (a screen or readout missing).
/// It does nothing unless `ZS_UKP=1` (`TEST_RUNNER_ZS_UKP=1`), so the regular demo suite stays fast.
final class UIKitPanProbeUITests: XCTestCase {
    private var os: String { UIDevice.current.systemVersion }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(ProcessInfo.processInfo.environment["ZS_UKP"] != "1", "measurement harness: set ZS_UKP=1")
    }

    // MARK: harness

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// The last match: with a sheet up, the presenting screen's readout is still in the tree.
    private func last(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let all = app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex
        return all.last ?? app.descendants(matching: .any)[id]
    }

    private func parse(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for kv in s.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { out[p[0]] = p[1] }
        }
        return out
    }

    private func num(_ d: [String: String], _ k: String) -> Double { Double(d[k] ?? "") ?? 0 }

    private func point(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    private func drag(_ app: XCUIApplication, from p: CGPoint, by v: CGVector, velocity: XCUIGestureVelocity, hold: TimeInterval = 0.05) {
        let a = point(app, p.x, p.y)
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(v), withVelocity: velocity, thenHoldForDuration: hold)
    }

    /// Finger vector at `deg` from the horizontal (0 = leftwards, 90 = upwards): content moves right / down into its range.
    private func vector(_ deg: Double, _ len: CGFloat) -> CGVector {
        CGVector(dx: -len * CGFloat(cos(deg * .pi / 180)), dy: -len * CGFloat(sin(deg * .pi / 180)))
    }

    private func velocity(_ v: Double) -> XCUIGestureVelocity { XCUIGestureVelocity(rawValue: CGFloat(v)) }

    private func probeInfo(_ app: XCUIApplication) -> [String: String] {
        for _ in 0..<3 {
            last(app, "probe.info").tap()
            Thread.sleep(forTimeInterval: 0.4)
            if let s = last(app, "probe.text").value as? String, !s.isEmpty { return parse(s) }
        }
        XCTFail("probe readout empty")
        return [:]
    }

    private func probeReset(_ app: XCUIApplication) {
        last(app, "probe.reset").tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func counters(_ d: [String: String], _ prefix: String = "c.uikitpan.") -> String {
        d.keys.filter { $0.hasPrefix(prefix) }.sorted().map { "\($0.dropFirst(2))=\(d[$0]!)" }.joined(separator: " ")
    }

    private func emit(_ q: String, _ fields: String) { print("UKP q=\(q) os=\(os) \(fields)") }

    // MARK: sheet (Q1, Q2, Q6, Q8)

    private func launchSheet(plain: String, v: String?, start: String = "medium") -> XCUIApplication {
        var args = ["-ZTronScreen", "sheet", "-ZTronSheetDetents", "medium,large", "-ZTronSheetStart", start, "-ZTronSheetPlain", plain]
        if let v { args += ["-ZTronProbeV", v] }
        let app = launch(args)
        XCTAssertTrue(app.buttons["sheet.present"].waitForExistence(timeout: 30), "the presenting screen")
        app.buttons["sheet.present"].tap()
        XCTAssertTrue(app.buttons["sheet.snapshot"].waitForExistence(timeout: 30), "the sheet appeared")
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    private func sheetEvidence(_ app: XCUIApplication) -> [String: String] {
        Thread.sleep(forTimeInterval: 1.5)
        if app.buttons["sheet.snapshot"].exists {
            app.buttons["sheet.snapshot"].tap()
            Thread.sleep(forTimeInterval: 0.3)
            return parse(any(app, "sheet.info").value as? String ?? "")
        }
        XCTAssertTrue(app.buttons["sheet.present"].waitForExistence(timeout: 5), "the presenting screen is back")
        app.buttons["sheet.baseSnapshot"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        var d = parse(any(app, "sheet.baseInfo").value as? String ?? "")
        d["gone"] = "1"
        return d
    }

    private func sheetReset(_ app: XCUIApplication) {
        app.buttons["sheet.reset"].tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func sheetLine(_ d: [String: String]) -> String {
        let keys = ["det", "dismissed", "top", "topMin", "topMax", "offX", "offXMin", "offXMax", "zxMin", "zxMax", "bothX", "page", "shOnly", "pc"]
        return keys.map { "\($0)=\(d[$0] ?? "-")" }.joined(separator: " ") + " gone=\(d["gone"] ?? "0") " + counters(d)
    }

    /// Q1 / Q6 / Q8: vertical drags at medium (up: expand), at large (down: collapse) and at medium (down 400: dismiss).
    private func sheetVerticalRows(_ q: String, variants: [(plain: String, v: String?)]) {
        for (plain, v) in variants {
            let app = launchSheet(plain: plain, v: v)
            let tag = "variant=\(plain)\(v.map { ":" + $0 } ?? "")"
            for (row, dy) in [("up250@medium", -250.0), ("down250@large", 250.0), ("down400@medium", 400.0)] {
                guard app.buttons["sheet.snapshot"].exists else { emit(q, "\(tag) row=\(row) skipped=sheet-gone"); continue }
                sheetReset(app)
                let f = any(app, "sheet.scroller").frame
                let y = dy > 0 ? f.minY + 24 : f.maxY - 60
                drag(app, from: CGPoint(x: f.midX, y: y), by: CGVector(dx: 0, dy: dy), velocity: .slow, hold: 0.3)
                emit(q, "\(tag) row=\(row) \(sheetLine(sheetEvidence(app)))")
            }
            app.terminate()
        }
    }

    func testQ1_sheetVerticalDrags() {
        sheetVerticalRows("Q1", variants: [("none", nil), ("uikitpan", "on"), ("uikitpan", "off")])
    }

    func testQ6_libraryPinchAndTapAloneInSheet() {
        sheetVerticalRows("Q6", variants: [("none", nil), ("magnifyLib", nil), ("spatialTap2", nil)])
    }

    /// Q2 / Q8: horizontal drags on the pager (page 0), on the zoomed zoomer page (middle, trailing edge), per V and detent.
    func testQ2_sheetHorizontalDrags() {
        for start in ["medium", "large"] {
            for v in ["on", "off"] {
                let app = launchSheet(plain: "uikitpan", v: v, start: start)
                for (pos, vel, dx) in [("P0", "slow", -200.0), ("P0", "fast", -200.0), ("ZMid", "slow", -120.0), ("ZEdge", "slow", -200.0)] {
                    guard app.buttons["sheet.snapshot"].exists else { emit("Q2", "start=\(start) v=\(v) pos=\(pos) vel=\(vel) skipped=sheet-gone"); continue }
                    app.buttons["probe.\(pos)"].tap()
                    Thread.sleep(forTimeInterval: 0.4)
                    sheetReset(app)
                    let f = any(app, "sheet.scroller").frame
                    drag(app, from: CGPoint(x: f.minX + f.width * 0.8, y: f.midY), by: CGVector(dx: dx, dy: 0),
                         velocity: vel == "fast" ? .fast : .slow, hold: vel == "fast" ? 0 : 0.2)
                    emit("Q2", "start=\(start) v=\(v) pos=\(pos) vel=\(vel) \(sheetLine(sheetEvidence(app)))")
                }
                app.terminate()
            }
        }
    }

    // MARK: N (Q3): a target inside SwiftUI's own vertical ScrollView

    private func nativePageRows(targets: [String], q: String = "Q3", angles: [Double] = [0, 40, 50, 90], speeds: [Double] = [150, 600, 2500],
                                extra: [String] = []) {
        for spec in targets {
            let parts = spec.split(separator: ":").map(String.init)
            let target = parts[0], v = parts.count > 1 ? parts[1] : nil
            var args = ["-ZTronScreen", "uikitPanPage", "-ZTronProbeTarget", target] + extra
            if let v { args += ["-ZTronProbeV", v] }
            let app = launch(args)
            let el = any(app, "probe.target")
            guard el.waitForExistence(timeout: 30) else { XCTFail("target missing: \(spec)"); app.terminate(); continue }
            Thread.sleep(forTimeInterval: 1.0)
            for a in angles {
                for s in speeds {
                    probeReset(app)
                    let f = el.frame
                    drag(app, from: CGPoint(x: f.midX, y: f.midY), by: vector(a, 100), velocity: velocity(s))
                    Thread.sleep(forTimeInterval: 1.2)
                    let d = probeInfo(app)
                    let page = num(d, "page.y.span")
                    let tgt = d.keys.filter { $0.hasSuffix(".span") && $0 != "page.y.span" }.map { num(d, $0) }.max() ?? 0
                    let mover = (page > 0.5 ? "P" : "") + (tgt > 0.5 ? "T" : "")
                    emit(q, "target=\(target) v=\(v ?? "-")\(extra.isEmpty ? "" : " extra=" + extra.joined(separator: "_")) deg=\(Int(a)) speed=\(Int(s)) mover=\(mover.isEmpty ? "-" : mover) page=\(Int(page)) tgt=\(Int(tgt)) "
                         + "bothPT=\(d["bothPT"] ?? "-") \(counters(d)) others=\(d["others"] ?? "-")")
                }
            }
            app.terminate()
        }
    }

    func testQ3a_nativeBaselines() { nativePageRows(targets: ["nativeCarousel", "nativeList", "plain"]) }
    func testQ3b_carousel() { nativePageRows(targets: ["carousel:on", "carousel:off", "carousel:axis"]) }
    func testQ3c_list() { nativePageRows(targets: ["list:on", "list:off", "list:axis"]) }
    func testQ3d_zoomer() { nativePageRows(targets: ["zoomer:on", "zoomer:off", "zoomer:axis"]) }

    private let sweep: [Double] = [10, 20, 30, 40, 50, 60, 70, 80]

    /// Where UIKit's own nested scroll views put the cross-axis / same-axis boundary (the design's axis rule says 45°).
    func testQ3e_nativeBoundary() { nativePageRows(targets: ["nativeCarousel", "nativeList", "plain"], q: "Q3e", angles: sweep, speeds: [150, 2500]) }

    /// The probe with a measured boundary (`ZS_UKP_BOUNDARY`, degrees from the view's axis), V off.
    func testQ3f_probeBoundary() {
        let b = ProcessInfo.processInfo.environment["ZS_UKP_BOUNDARY"] ?? "60"
        nativePageRows(targets: ["carousel:off", "list:off"], q: "Q3e", angles: sweep, speeds: [150, 2500], extra: ["-ZTronProbeBoundary", b])
    }

    // MARK: Q4: detection

    func testQ4_detection() {
        for parent in ["none", "nativeV", "nativeH", "list", "form", "tabPage", "sheet", "ztron"] {
            let app = launch(["-ZTronScreen", "uikitPanDetect", "-ZTronProbeParent", parent])
            XCTAssertTrue(last(app, "probe.info").waitForExistence(timeout: 30))
            Thread.sleep(forTimeInterval: 1.5)
            let d = probeInfo(app)
            emit("Q4", "parent=\(parent) det=\(d["det"] ?? "none") detGR=\(d["detGR"] ?? "none")")
            app.terminate()
        }
    }

    // MARK: Q5: recognizer facts (begin distance, first shouldBegin, lift order, second touch, reset/swallow)

    private func pagerApp(_ extra: [String] = []) -> (XCUIApplication, XCUIElement) {
        let app = launch(["-ZTronScreen", "uikitPanPager"] + extra)
        let empty = any(app, "ctl.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 30), "controls screen")
        Thread.sleep(forTimeInterval: 1.0)
        return (app, empty)
    }

    private func q5Line(_ d: [String: String]) -> String {
        let keys = ["fsb", "fsbD", "fsbV", "fsbSrc", "fsbXY", "bt", "btD", "lift", "maxT", "controls.x.span", "controls.y.span"]
        return keys.map { "\($0)=\(d[$0] ?? "-")" }.joined(separator: " ") + " " + counters(d) + " pinch=\(d["c.probe.pinch"] ?? "0")"
    }

    func testQ5_recognizerFacts() {
        var (app, empty) = pagerApp()
        for (deg, s) in [(0.0, 150.0), (0.0, 600.0), (0.0, 2500.0), (40.0, 150.0), (40.0, 2500.0), (90.0, 600.0)] {
            probeReset(app)
            let f = empty.frame
            drag(app, from: CGPoint(x: f.midX, y: f.midY), by: vector(deg, 120), velocity: velocity(s))
            Thread.sleep(forTimeInterval: 0.8)
            emit("Q5", "row=drag deg=\(Int(deg)) speed=\(Int(s)) \(q5Line(probeInfo(app)))")
        }
        probeReset(app)
        empty.pinch(withScale: 2, velocity: 1)
        Thread.sleep(forTimeInterval: 0.8)
        emit("Q5", "row=pinch \(q5Line(probeInfo(app)))")
        probeReset(app)
        empty.twoFingerTap()
        Thread.sleep(forTimeInterval: 0.8)
        emit("Q5", "row=twoFingerTap \(q5Line(probeInfo(app)))")
        app.terminate()
        (app, empty) = pagerApp(["-ZTronProbeResetAfter", "1"])
        for s in [150.0, 600.0, 2500.0] {
            probeReset(app)
            let f = empty.frame
            drag(app, from: CGPoint(x: f.midX, y: f.midY), by: vector(0, 160), velocity: velocity(s))
            Thread.sleep(forTimeInterval: 0.8)
            emit("Q5", "row=resetAfter1 speed=\(Int(s)) \(q5Line(probeInfo(app)))")
        }
        app.terminate()
    }

    // MARK: Q7: controls on the UIKit path; .disabled; drags from bars and a pinned header

    private func q7Line(_ d: [String: String]) -> String {
        let keys = ["ctlB", "ctlS", "ctlT", "ctlX", "ctlW", "ctlSt", "ctlSeg", "controls.x.span", "controls.y.span"]
        return keys.map { "\($0)=\(d[$0] ?? "-")" }.joined(separator: " ") + " " + counters(d) + " others=\(d["others"] ?? "-")"
    }

    func testQ7_controls() {
        for v in ["on", "off"] {
            let (app, empty) = pagerApp(["-ZTronProbeV", v])
            func row(_ name: String, _ act: () -> Void) {
                probeReset(app)
                act()
                Thread.sleep(forTimeInterval: 0.8)
                emit("Q7", "v=\(v) row=\(name) \(q7Line(probeInfo(app)))")
            }
            func center(_ e: XCUIElement) -> CGPoint { CGPoint(x: e.frame.midX, y: e.frame.midY) }
            row("buttonTap") { any(app, "ctl.button").tap() }
            row("buttonDrag") { drag(app, from: center(any(app, "ctl.button")), by: vector(0, 150), velocity: velocity(600)) }
            row("sliderDrag") {
                let s = any(app, "ctl.slider")
                drag(app, from: center(s), by: CGVector(dx: 80, dy: 0), velocity: .slow, hold: 0.2)
            }
            row("toggleTap") {
                // The switch sits at the trailing end of the row (a tap on the label does not toggle on 26+).
                let t = app.switches["ctl.toggle"].firstMatch
                (t.exists ? t : any(app, "ctl.toggle")).coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            row("wheelDrag") { drag(app, from: center(any(app, "ctl.wheel")), by: CGVector(dx: 0, dy: -60), velocity: .slow, hold: 0.2) }
            row("stepperTap") {
                let inc = app.buttons["ctl.stepper-Increment"].firstMatch
                if inc.exists { inc.tap() } else { app.steppers["ctl.stepper"].buttons.element(boundBy: 1).tap() }
            }
            row("segmentTap") { app.segmentedControls["ctl.segment"].buttons.element(boundBy: 1).tap() }
            row("emptyDrag") { drag(app, from: center(empty), by: vector(0, 150), velocity: velocity(600)) }
            row("navBarDrag") {
                let nb = app.navigationBars.firstMatch
                drag(app, from: CGPoint(x: nb.frame.maxX - 60, y: nb.frame.midY), by: vector(0, 150), velocity: velocity(600))
            }
            row("tabBarDrag") {
                let tb = app.tabBars.firstMatch
                drag(app, from: CGPoint(x: tb.frame.maxX - 60, y: tb.frame.minY + 20), by: vector(0, 150), velocity: velocity(600))
            }
            row("headerDrag") {
                let h = any(app, "probe.header")
                drag(app, from: CGPoint(x: h.frame.maxX - 60, y: h.frame.midY), by: vector(0, 150), velocity: velocity(600))
            }
            row("textTapType") {
                any(app, "ctl.text").tap()
                Thread.sleep(forTimeInterval: 0.6)
                app.typeText("a")
            }
            app.terminate()
        }
        for (name, extra) in [("disabledRaw", ["-ZTronProbeDisabled"]), ("disabledEnv", ["-ZTronProbeDisabled", "-ZTronProbeEnvEnabled"])] {
            let (app, empty) = pagerApp(extra)
            Thread.sleep(forTimeInterval: 0.5)
            probeReset(app)
            let f = empty.frame
            drag(app, from: CGPoint(x: f.midX, y: f.midY), by: vector(0, 150), velocity: velocity(600))
            Thread.sleep(forTimeInterval: 0.8)
            emit("Q7", "v=axis row=\(name) \(q7Line(probeInfo(app)))")
            app.terminate()
        }
    }

    // MARK: Q9: a sheet over an N carousel

    func testQ9_coveredCarousel() {
        for cover in ["plain", "pager"] {
            let app = launch(["-ZTronScreen", "uikitPanPage", "-ZTronProbeTarget", "carousel", "-ZTronProbeCover", cover])
            let el = any(app, "probe.target")
            guard el.waitForExistence(timeout: 30) else { XCTFail("target missing"); app.terminate(); continue }
            Thread.sleep(forTimeInterval: 1.0)
            probeReset(app)
            let f = el.frame
            app.buttons["probe.cover"].tap()
            Thread.sleep(forTimeInterval: 1.5)
            probeReset(app)
            drag(app, from: CGPoint(x: f.minX + f.width * 0.8, y: f.midY), by: vector(0, 150), velocity: velocity(600))
            Thread.sleep(forTimeInterval: 1.0)
            let d = probeInfo(app)
            emit("Q9", "cover=\(cover) carouselY=\(Int(f.midY)) carousel.x.span=\(d["carousel.x.span"] ?? "-") pager.x.span=\(d["pager.x.span"] ?? "-") \(counters(d))")
            app.terminate()
        }
    }
}
