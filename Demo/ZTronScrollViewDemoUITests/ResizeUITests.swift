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

    private func launch(reflow: Bool = false, userTree: Bool = false, userTree2: Bool = false,
                        extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "resize"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (reflow ? ["-ZTronResizeReflow"] : []) + (userTree ? ["-ZTronResizeUserTree"] : [])
            + (userTree2 ? ["-ZTronResizeUserTree2"] : []) + extra
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
        func bounds(_ i: Info) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
            let z = i["z"]
            return (-i["il"], 1500 * z + i["ir"] - i["vw"], -i["it"], 1000 * z + i["ib"] - i["vh"])
        }
        // toLandscape: in bounds; an axis whose centre moved was clamped only as far as needed, so it sits on a bound.
        let bl = bounds(l)
        XCTAssertTrue(l["ox"] >= bl.minX - 0.5 && l["ox"] <= bl.maxX + 0.5, l.raw)
        XCTAssertTrue(l["oy"] >= bl.minY - 0.5 && l["oy"] <= bl.maxY + 0.5, l.raw)
        if abs(l["ux"] - p0["ux"]) > 1 { XCTAssertTrue(abs(l["ox"] - bl.maxX) < 0.5 || abs(l["ox"] - bl.minX) < 0.5, l.raw) }
        if abs(l["uy"] - p0["uy"]) > 1 { XCTAssertTrue(abs(l["oy"] - bl.maxY) < 0.5 || abs(l["oy"] - bl.minY) < 0.5, l.raw) }
        // portraitBack: the sticky intent (D17) was captured from the initial state, not from the clamped landscape one,
        // so the way back restores the initial offset and zoom exactly (criterion A) even though the landscape centre
        // was clamped onto a bound; the bound rule no longer applies here.
        let bp = bounds(p1)
        XCTAssertTrue(p1["ox"] >= bp.minX - 0.5 && p1["ox"] <= bp.maxX + 0.5, p1.raw)
        XCTAssertTrue(p1["oy"] >= bp.minY - 0.5 && p1["oy"] <= bp.maxY + 0.5, p1.raw)
        XCTAssertEqual(p1["ox"], p0["ox"], accuracy: 0.5, p1.raw)
        XCTAssertEqual(p1["oy"], p0["oy"], accuracy: 0.5, p1.raw)
        XCTAssertEqual(p1["z"], p0["z"], accuracy: 1e-3, p1.raw)
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

    // MARK: Screen space (D17): markers inside the content, measured with XCUIElement.frame

    private static let markerNames = ["detail", "centre", "tl", "br"]
    private static let markerFractions: [String: CGPoint] = ["detail": CGPoint(x: 0.3, y: 0.65), "centre": CGPoint(x: 0.5, y: 0.5),
                                                             "tl": CGPoint(x: 0.1, y: 0.1), "br": CGPoint(x: 0.9, y: 0.9)]

    private func markers(_ app: XCUIApplication) -> [String: CGPoint] {
        var r: [String: CGPoint] = [:]
        for n in Self.markerNames {
            let e = app.descendants(matching: .any)["marker.\(n)"]
            if e.exists { r[n] = CGPoint(x: e.frame.midX, y: e.frame.midY) }
        }
        return r
    }

    /// Screen point of the content fraction `f`, from the tl (10 %) and br (90 %) markers (the content is an affine
    /// image of its unscaled space: offset + uniform scale).
    private func screenPoint(_ m: [String: CGPoint], _ f: CGPoint) -> CGPoint? {
        guard let a = m["tl"], let b = m["br"] else { return nil }
        return CGPoint(x: a.x + (f.x - 0.1) / 0.8 * (b.x - a.x), y: a.y + (f.y - 0.1) / 0.8 * (b.y - a.y))
    }

    /// Content fraction drawn at screen point `p`.
    private func fraction(_ m: [String: CGPoint], at p: CGPoint) -> CGPoint? {
        guard let a = m["tl"], let b = m["br"], b.x != a.x, b.y != a.y else { return nil }
        return CGPoint(x: 0.1 + (p.x - a.x) / (b.x - a.x) * 0.8, y: 0.1 + (p.y - a.y) / (b.y - a.y) * 0.8)
    }

    /// Centre of the unobscured viewport in screen space. The XCUI frame of `scrollerView` (the scroll view itself; the
    /// screen's outer "scroller" wraps the nav stack) already EXCLUDES the safe area: the viewport root ignores it inside
    /// the container, so the frame is the unobscured rect (portrait 16:9 box: frame y=62,h=226 vs vh=288). Its centre is
    /// the visible centre (== f.minX - il + cx); adding `il`/`it` again would double count. contentInset is 0 in the demo.
    private func visibleCentre(_ app: XCUIApplication, _ i: Info) -> CGPoint {
        let f = app.descendants(matching: .any)["scrollerView"].frame
        return CGPoint(x: f.midX, y: f.midY)
    }

    private func dist(_ a: CGPoint?, _ b: CGPoint?) -> Double {
        guard let a, let b else { return -1 }
        return hypot(a.x - b.x, a.y - b.y)
    }

    /// Zoomed 2.5x on an off-centre detail; rotate x1, x2, x3, x4. Odd rotations: the content fraction that was under
    /// the visible centre is under it afterwards (ZTronMapKit formula, <= 1 pt). Even rotations: every marker is back
    /// at its initial screen position (<= 0.5 pt) and the readouts equal the initial offset / zoom.
    private func screenSpaceRoundTrips(_ name: String, userTree2: Bool) {
        let app = launch(userTree: !userTree2, userTree2: userTree2)
        app.buttons["Zoom"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let p0 = info(app, "\(name).0")
        let m0 = markers(app)
        XCTAssertEqual(m0.count, 4, "markers exposed: \(m0)")
        let c0 = visibleCentre(app, p0)
        let f0 = fraction(m0, at: c0)
        print("RESIZESCREEN \(path) \(name) 0 centre=\(c0) fraction=\(String(describing: f0)) markers=\(m0) scroller=\(app.descendants(matching: .any)["scrollerView"].frame)")
        var prevM = m0, prevC = c0, prevI = p0
        for n in 1...4 {
            rotate(n % 2 == 1 ? .landscapeLeft : .portrait)
            let i = info(app, "\(name).\(n)")
            let m = markers(app)
            let c = visibleCentre(app, i)
            let under = fraction(prevM, at: prevC)            // what was under the centre before this rotation
            let now = under.flatMap { screenPoint(m, $0) }     // where that content fraction is drawn now
            let e = dist(now, c)
            let back = Self.markerNames.map { dist(m0[$0], m[$0]) }
            print("RESIZESCREEN \(path) \(name) \(n) centreErr=\(e) under=\(String(describing: under)) now=\(String(describing: now)) centre=\(c) "
                  + "markersBack=\(back) z=\(i["z"]) o=(\(i["ox"]),\(i["oy"])) z0=\(p0["z"]) o0=(\(p0["ox"]),\(p0["oy"])) jump=\(i["jump"])")
            XCTAssertEqual(m.count, 4, "markers after rotation \(n)")
            XCTAssertEqual(i["z"], prevI["z"], accuracy: 1e-3, "scale kept at rotation \(n)")
            XCTAssertLessThanOrEqual(e, 1, "visible centre preserved on screen at rotation \(n): \(i.raw)")
            if n % 2 == 0 {
                for (k, d) in zip(Self.markerNames, back) { XCTAssertLessThanOrEqual(d, 0.5, "marker \(k) back at its initial frame after \(n) rotations") }
                XCTAssertEqual(i["ox"], p0["ox"], accuracy: 0.5, "offset x restored after \(n) rotations")
                XCTAssertEqual(i["oy"], p0["oy"], accuracy: 0.5, "offset y restored after \(n) rotations")
                XCTAssertEqual(i["z"], p0["z"], accuracy: 1e-6, "zoom restored after \(n) rotations")
            }
            prevM = m; prevC = c; prevI = i
        }
    }

    /// The user's current app tree: full-screen scroller (no 16:9 box) under the navigation stack.
    /// User report (2026-10-19): bounce "does not work" in the 16:9 image tree, whatever the behavior. The state
    /// rubber-bands (unit-tested); this checks the DRAWN frames: a drag past the edge must not be clamped away by the
    /// transform at rest (`transform.clampedAtRest == 0`), and no frame may take the resize path with the commit closed.
    private func overscrollIsDrawn(_ label: String, extra: [String], from: CGVector, to: CGVector) {
        let app = launch(userTree: true, extra: extra)
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        let before = info(app, "\(label) before")
        XCTAssertEqual(before["phase"], 0, "idle at rest after launch (a transaction that never settles stays .animating): \(before.raw)")
        let s = app.descendants(matching: .any)["scrollerView"]
        let a = s.coordinate(withNormalizedOffset: from), b = s.coordinate(withNormalizedOffset: to)
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.5)
        Thread.sleep(forTimeInterval: 1.5)
        let i = info(app, "\(label) after")
        XCTAssertGreaterThan(i["effect"], before["effect"], "the drag drew frames")
        XCTAssertEqual(i["slowClosed"], 0, "resize path with the commit closed: \(i.raw)")
        XCTAssertEqual(i["clamped"], 0, "drawn offset clamped away from the target at rest: \(i.raw)")
        XCTAssertEqual(i["ox"], before["ox"], accuracy: 0.5, "sprang back")
        XCTAssertEqual(i["oy"], before["oy"], accuracy: 0.5, "sprang back")
    }

    func testUserTreeVerticalOverscrollIsDrawn() {
        // Starts below the screen's overlay buttons; at the top edge a downward drag overscrolls.
        overscrollIsDrawn("vband", extra: [], from: CGVector(dx: 0.5, dy: 0.6), to: CGVector(dx: 0.5, dy: 0.95))
    }

    func testUserTreeHorizontalAlwaysBounceIsDrawn() {
        overscrollIsDrawn("hband", extra: ["-ZTronResizeBounceAlways"],
                          from: CGVector(dx: 0.3, dy: 0.5), to: CGVector(dx: 0.8, dy: 0.5))
    }

    func testUserTree2ScreenSpaceCentreAndEvenRotationsRestore() { screenSpaceRoundTrips("user2", userTree2: true) }
    /// The 16:9 box variant.
    func testUserTreeScreenSpaceCentreAndEvenRotationsRestore() { screenSpaceRoundTrips("user", userTree2: false) }
}
