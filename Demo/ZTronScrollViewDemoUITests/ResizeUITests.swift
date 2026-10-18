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

    private func launch(reflow: Bool = false, userTree: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "resize"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (reflow ? ["-ZTronResizeReflow"] : []) + (userTree ? ["-ZTronResizeUserTree"] : [])
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
    /// `cell`: unscaled cell size (100 for the fixed grid, content width / 6 for the reflow grid).
    private func drawnError(_ app: XCUIApplication, _ i: Info, cell: Double = 100) -> Double {
        let col = Int(floor(i["ux"] / cell)), row = Int(floor(i["uy"] / cell))
        let cell_ = app.descendants(matching: .any)["cell.\(row).\(col)"]
        guard cell_.exists else { return -1 }
        let f = cell_.frame, w = app.windows.firstMatch.frame
        let px = f.minX + (i["ux"] - Double(col) * cell) / cell * f.width
        let py = f.minY + (i["uy"] - Double(row) * cell) / cell * f.height
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

    // MARK: Reflowing content (SPEC S7 "reflowing content"; the user's `Image(...).resizable().aspectRatio(.fit)
    // .frame(maxWidth: .infinity)` in a vertical scroll view): the content size follows the viewport width, so the
    // NORMALIZED centre (u / contentSize) is what must survive, within 1 pt of the new content (scaled).

    /// Normalized-centre error in screen points between two infos: |u_b - n_a * content_b| * z_b.
    private func reflowError(_ a: Info, _ b: Info) -> Double {
        let nx = a["ux"] / a["cw"], ny = a["uy"] / a["ch"]
        return hypot(b["ux"] - nx * b["cw"], b["uy"] - ny * b["ch"]) * b["z"]
    }

    private func onBound(_ i: Info) -> (x: Bool, y: Bool) {
        let z = i["z"]
        let maxX = i["cw"] * z + i["ir"] - i["vw"], maxY = i["ch"] * z + i["ib"] - i["vh"]
        let minX = -i["il"], minY = -i["it"]
        return (abs(i["ox"] - max(maxX, minX)) < 0.5 || abs(i["ox"] - minX) < 0.5,
                abs(i["oy"] - max(maxY, minY)) < 0.5 || abs(i["oy"] - minY) < 0.5)
    }

    /// portrait -> landscape -> portrait on the reflow grid after tapping `button`.
    private func reflowRoundTrip(_ name: String, _ button: String, zoomed: Bool) {
        let app = launch(reflow: true)
        app.buttons[button].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let p0 = info(app, "reflow.\(name).portrait")
        rotate(.landscapeLeft)
        let l = info(app, "reflow.\(name).landscape")
        let dl = drawnError(app, l, cell: l["cw"] / 6)
        rotate(.portrait)
        let p1 = info(app, "reflow.\(name).portraitBack")
        let dp = drawnError(app, p1, cell: p1["cw"] / 6)
        let e1 = reflowError(p0, l), e2 = reflowError(l, p1)
        print("RESIZEERR \(path) reflow.\(name) toLandscape=\(e1) back=\(e2) drawn=\(dl)/\(dp) "
              + "jump=\(l["jump"])/\(p1["jump"]) cidle=\(l["cidle"])/\(p1["cidle"]) vp=\(l["vp"])/\(p1["vp"])")
        XCTAssertNotEqual(p0["cw"], l["cw"], "content reflowed")
        XCTAssertEqual(l["cw"], l["vw"], accuracy: 1, "content takes the viewport width")
        for (prev, i, e) in [(p0, l, e1), (l, p1, e2)] {
            let b = onBound(i)
            // Preserved, except where the content edge required a clamp (then the offset sits on that bound).
            if e > 1 {
                let nx = prev["ux"] / prev["cw"], ny = prev["uy"] / prev["ch"]
                let ex = abs(i["ux"] - nx * i["cw"]) * i["z"], ey = abs(i["uy"] - ny * i["ch"]) * i["z"]
                XCTAssertTrue(ex <= 1 || b.x, "x centre moved off a bound: \(i.raw)")
                XCTAssertTrue(ey <= 1 || b.y, "y centre moved off a bound: \(i.raw)")
            }
            XCTAssertEqual(i["jump"], 0, i.raw)
            if zoomed { XCTAssertEqual(i["z"], prev["z"], accuracy: 1e-3, "scale kept") }
        }
        XCTAssertEqual(p1["body"], 0)
    }

    /// The user's exact tree (16:9 box in a GeometryReader, image as wide as the reader, two axes): zoomed to 2.5x on
    /// an off-centre detail, portrait -> landscape -> portrait. Viewport AND content width change; in landscape the
    /// content is wider than the viewport at 1x.
    func testUserTreeZoomedDetailStaysCentredAcrossRotation() {
        let app = launch(userTree: true)
        app.buttons["Zoom"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let p0 = info(app, "user.portrait")
        rotate(.landscapeLeft)
        let l = info(app, "user.landscape")
        rotate(.portrait)
        let p1 = info(app, "user.portraitBack")
        let e1 = reflowError(p0, l), e2 = reflowError(l, p1)
        print("RESIZEERR \(path) user.zoomed toLandscape=\(e1) back=\(e2) jump=\(l["jump"])/\(p1["jump"]) "
              + "cidle=\(l["cidle"])/\(p1["cidle"]) vp=\(l["vp"])/\(p1["vp"])")
        // zoom(to:) lands at ~1.94x in the 16:9 box (the rect is clamped to the content); the point is a zoomed-in detail.
        XCTAssertGreaterThanOrEqual(p0["z"], 1.9, p0.raw)
        XCTAssertNotEqual(p0["cw"], l["cw"], "content reflowed")
        XCTAssertNotEqual(p0["vw"], l["vw"], "viewport changed")
        XCTAssertGreaterThan(l["cw"], l["vw"] + 1, "landscape content wider than the 16:9 box")
        XCTAssertLessThanOrEqual(e1, 1, l.raw)
        XCTAssertLessThanOrEqual(e2, 1, p1.raw)
        XCTAssertEqual(l["z"], p0["z"], accuracy: 1e-3, "scale kept")
        XCTAssertEqual(p1["z"], p0["z"], accuracy: 1e-3, "scale kept")
        XCTAssertEqual(l["jump"], 0, l.raw)
        XCTAssertEqual(p1["jump"], 0, p1.raw)
    }

    func testReflowMiddleAt1xKeepsNormalizedCentre() { reflowRoundTrip("mid", "Mid", zoomed: false) }
    func testReflowZoomedKeepsNormalizedCentre() { reflowRoundTrip("zoomed", "Zoom", zoomed: true) }
    func testReflowNearTopKeepsNormalizedCentre() { reflowRoundTrip("top", "Top", zoomed: false) }
    func testReflowNearBottomKeepsNormalizedCentre() { reflowRoundTrip("bottom", "Bottom", zoomed: false) }
}
