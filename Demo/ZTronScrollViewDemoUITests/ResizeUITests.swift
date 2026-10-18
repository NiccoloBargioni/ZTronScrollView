import XCTest

/// SPEC S7: the unscaled content point at the centre of the unobscured viewport survives rotation.
final class ResizeUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var path: String { forced ? "forced" : "preferred" }

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "resize"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    struct Info {
        var v: [String: Double]; var raw: String
        subscript(_ k: String) -> Double { v[k] ?? -9999 }
        var u: CGPoint { CGPoint(x: self["ux"], y: self["uy"]) }
    }

    private func info(_ app: XCUIApplication, _ label: String) -> Info {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        let s = app.staticTexts["resizeInfo"].value as? String ?? ""
        var v: [String: Double] = [:]
        for part in s.components(separatedBy: " ") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2, let d = Double(kv[1]) { v[String(kv[0])] = d }
        }
        print("RESIZE \(path) \(label) \(s)")
        return Info(v: v, raw: s)
    }

    /// Drawn position of content point `u` (from the cell's accessibility frame) minus the unobscured centre, in points.
    private func drawnError(_ app: XCUIApplication, _ i: Info) -> Double {
        let col = Int(floor(i["ux"] / 100)), row = Int(floor(i["uy"] / 100))
        let cell = app.descendants(matching: .any)["cell.\(row).\(col)"]
        guard cell.exists else { return -1 }
        let f = cell.frame, w = app.windows.firstMatch.frame
        let px = f.minX + (i["ux"] - Double(col) * 100) / 100 * f.width
        let py = f.minY + (i["uy"] - Double(row) * 100) / 100 * f.height
        print("RESIZEDRAWN \(path) cell=\(row),\(col) f=\(f) window=\(w) p=(\(px),\(py)) c=(\(i["cx"]),\(i["cy"]))")
        return hypot(px - (w.minX + i["cx"]), py - (w.minY + i["cy"]))
    }

    private func rotate(_ o: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = o
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func err(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    /// portrait -> landscape -> portrait; returns the infos (drawn error measured right after each snapshot).
    private func roundTrip(_ app: XCUIApplication, _ name: String) -> (Info, Info, Info) {
        let p0 = info(app, "\(name).portrait")
        rotate(.landscapeLeft)
        let l = info(app, "\(name).landscape")
        let dl = drawnError(app, l)
        rotate(.portrait)
        let p1 = info(app, "\(name).portraitBack")
        let dp = drawnError(app, p1)
        print("RESIZEERR \(path) \(name) toLandscape=\(err(p0.u, l.u)) back=\(err(l.u, p1.u)) "
              + "drawn=\(dl)/\(dp) jump=\(l["jump"])/\(p1["jump"])")
        return (p0, l, p1)
    }

    func testRotateAtFitKeepsCentreAndFit() {
        let app = launch()
        app.buttons["Fit"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let (p0, l, p1) = roundTrip(app, "fit")
        XCTAssertNotEqual(p0["vw"], l["vw"], "rotated")
        XCTAssertLessThanOrEqual(err(p0.u, l.u), 1, l.raw)
        XCTAssertLessThanOrEqual(err(l.u, p1.u), 1, p1.raw)
        XCTAssertEqual(l["z"], l["min"], accuracy: 1e-3, "fit stays fit")
        XCTAssertEqual(p1["z"], p1["min"], accuracy: 1e-3, "fit stays fit")
        XCTAssertEqual(p1["body"], 0)
    }

    func testRotateZoomedKeepsCentre() {
        let app = launch()
        app.buttons["Zoom"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let (p0, l, p1) = roundTrip(app, "zoomed")
        XCTAssertGreaterThan(p0["z"], p0["min"] * 1.2)
        XCTAssertLessThanOrEqual(err(p0.u, l.u), 1, l.raw)
        XCTAssertLessThanOrEqual(err(l.u, p1.u), 1, p1.raw)
        XCTAssertEqual(l["z"], p0["z"], accuracy: 1e-3, "scale kept")
        XCTAssertEqual(l["jump"], 0)
        XCTAssertEqual(p1["jump"], 0)
        XCTAssertEqual(p1["body"], 0)
    }

    func testRotateNearEdgeClampsOnlyAsNeeded() {
        let app = launch()
        app.buttons["Edge"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let (p0, l, p1) = roundTrip(app, "edge")
        for (prev, i) in [(p0, l), (l, p1)] {
            let z = i["z"]
            let maxX = 1500 * z + i["ir"] - i["vw"], maxY = 1000 * z + i["ib"] - i["vh"]
            let minX = -i["il"], minY = -i["it"]
            // In bounds; an axis whose centre moved must sit on a bound.
            XCTAssertTrue(i["ox"] >= minX - 0.5 && i["ox"] <= maxX + 0.5, i.raw)
            XCTAssertTrue(i["oy"] >= minY - 0.5 && i["oy"] <= maxY + 0.5, i.raw)
            if abs(i["ux"] - prev["ux"]) > 1 { XCTAssertTrue(abs(i["ox"] - maxX) < 0.5 || abs(i["ox"] - minX) < 0.5, i.raw) }
            if abs(i["uy"] - prev["uy"]) > 1 { XCTAssertTrue(abs(i["oy"] - maxY) < 0.5 || abs(i["oy"] - minY) < 0.5, i.raw) }
        }
        XCTAssertEqual(p1["body"], 0)
    }

    func testRotateMidDecelerationStopsAndKeepsCentre() {
        let app = launch()
        app.buttons["Zoom"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        app.otherElements["scroller"].swipeLeft(velocity: .slow)
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        let l = info(app, "fling.landscape")
        Thread.sleep(forTimeInterval: 1.0)
        let l2 = info(app, "fling.later")
        let pre = CGPoint(x: l["preux"], y: l["preuy"])
        print("RESIZEERR \(path) fling toLandscape=\(err(pre, l.u)) drift=\(err(l.u, l2.u)) drawn=\(drawnError(app, l))")
        XCTAssertEqual(l["resizes"], 1, l.raw)
        XCTAssertLessThanOrEqual(err(pre, l.u), 1, l.raw)
        XCTAssertLessThanOrEqual(err(l.u, l2.u), 0.01, "motion stopped")
        XCTAssertEqual(l2["phase"], 0, "idle")
        XCTAssertEqual(l2["body"], 0)
    }
}
