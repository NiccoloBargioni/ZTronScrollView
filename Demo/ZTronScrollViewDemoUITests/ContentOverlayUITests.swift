import XCTest

/// M6b content-integral overlays (design docs/design/M6b-content-overlay.md §4 "UI") on the user's full-screen tree
/// (`-ZTronResizeUserTree2 -ZTronResizeOverlay`): a 6 pt marker pinned on the content point (30 %, 65 %), a 16:9 banner
/// at the content's bottom and a tint over the whole content. Ground truth: the `GeometryReader` markers drawn inside the
/// content (`marker.*`, `ContentMarkers`) and the app's DEBUG counters in the readout (`ovb` overlay roots, `mk` / `bn` /
/// `tn` the demo overlays' bodies, `btap` the banner button), never XCUI state alone.
final class ContentOverlayUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var path: String { forced ? "forced" : "preferred" }

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func launch(counterScaled: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "resize"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + ["-ZTronResizeUserTree2", "-ZTronResizeOverlay"] + (counterScaled ? ["-ZTronResizeOverlayCounterScaled"] : [])
        app.launch()
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    // MARK: Readout and markers (copied from ResizeUITests)

    struct Info {
        var v: [String: Double]; var raw: String
        subscript(_ k: String) -> Double { v[k] ?? -9999 }
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
        print("OVERLAY \(path) \(label) \(s)")
        return Info(v: v, raw: s)
    }

    private func rotate(_ o: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = o
        Thread.sleep(forTimeInterval: 1.5)
    }

    private static let markerNames = ["detail", "centre", "tl", "br"]

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The element's frame, nil when it is not in the tree (reading a missing element's properties fails the test).
    private func frame(_ app: XCUIApplication, _ id: String) -> CGRect? {
        let e = element(app, id)
        return e.exists ? e.frame : nil
    }

    private func markers(_ app: XCUIApplication) -> [String: CGPoint] {
        var r: [String: CGPoint] = [:]
        for n in Self.markerNames {
            if let f = frame(app, "marker.\(n)") { r[n] = CGPoint(x: f.midX, y: f.midY) }
        }
        return r
    }

    /// Screen point of the content fraction `f`, from the tl (10 %) and br (90 %) markers (the content is an affine
    /// image of its unscaled space: offset + uniform scale).
    private func screenPoint(_ m: [String: CGPoint], _ f: CGPoint) -> CGPoint? {
        guard let a = m["tl"], let b = m["br"] else { return nil }
        return CGPoint(x: a.x + (f.x - 0.1) / 0.8 * (b.x - a.x), y: a.y + (f.y - 0.1) / 0.8 * (b.y - a.y))
    }

    /// The content rect on screen, from the 10 % / 90 % markers.
    private func contentRect(_ m: [String: CGPoint]) -> CGRect? {
        guard let a = m["tl"], let b = m["br"] else { return nil }
        let dx = b.x - a.x, dy = b.y - a.y
        return CGRect(x: a.x - dx / 8, y: a.y - dy / 8, width: dx * 1.25, height: dy * 1.25)
    }

    private func dist(_ a: CGPoint?, _ b: CGPoint?) -> Double {
        guard let a, let b else { return -1 }
        return hypot(a.x - b.x, a.y - b.y)
    }

    private func counters(_ i: Info) -> String {
        "ovb=\(i["ovb"]) ovh=\(i["ovh"]) ovr=\(i["ovr"]) ovp=\(i["ovp"]) ocs=\(i["ocs"]) mk=\(i["mk"]) bn=\(i["bn"]) tn=\(i["tn"]) "
            + "btap=\(i["btap"]) body=\(i["body"]) jump=\(i["jump"]) effect=\(i["effect"])"
    }

    // MARK: Checks

    /// `overlay.detail` (pinned with its centre on the content point (30 %, 65 %)) against `marker.detail` (the
    /// `GeometryReader` marker at the same fraction) and the marker-derived screen point; its size is 6 pt scaled with
    /// the content (`.withContent`) or 6 pt on screen (`.counterScaled`). Returns its frame.
    @discardableResult
    private func checkMarker(_ app: XCUIApplication, _ i: Info, _ label: String, counterScaled: Bool = false) -> CGRect? {
        let m = markers(app)
        guard let f = frame(app, "overlay.detail"), let d = m["detail"] else {
            XCTFail("\(label): overlay.detail or marker.detail missing, markers=\(m): \(i.raw)")
            return nil
        }
        let c = CGPoint(x: f.midX, y: f.midY)
        let eMarker = dist(c, d), eSpace = dist(c, screenPoint(m, CGPoint(x: 0.3, y: 0.65)))
        let want = counterScaled ? 6 : 6 * i["z"], tol = counterScaled ? 0.75 : 1.0
        let what = "\(label): overlay=\(f) marker.detail=\(d) errMarker=\(eMarker) errSpace=\(eSpace) wantSize=\(want) "
            + "z=\(i["z"]) \(counters(i)) | \(i.raw)"
        print("OVERLAYMARKER \(path) \(what)")
        XCTAssertEqual(m.count, 4, "markers exposed: \(what)")
        XCTAssertLessThanOrEqual(eMarker, counterScaled ? 0.75 : 0.5, "overlay centre on marker.detail: \(what)")
        XCTAssertTrue(eSpace >= 0 && eSpace <= 1, "overlay centre on the content point (0.3, 0.65): \(what)")
        XCTAssertEqual(f.width, want, accuracy: tol, "overlay width: \(what)")
        XCTAssertEqual(f.height, want, accuracy: tol, "overlay height: \(what)")
        return f
    }

    /// `overlay.banner` (full content width, 16:9, on the content's bottom edge) and `overlay.fill` (the content rect)
    /// against the marker-derived content rect. Returns that rect.
    @discardableResult
    private func checkBannerAndFill(_ app: XCUIApplication, _ i: Info, _ label: String) -> CGRect? {
        let m = markers(app)
        guard let c = contentRect(m), let b = frame(app, "overlay.banner"), let f = frame(app, "overlay.fill") else {
            XCTFail("\(label): markers=\(m) banner=\(String(describing: frame(app, "overlay.banner"))) "
                    + "fill=\(String(describing: frame(app, "overlay.fill"))): \(i.raw)")
            return nil
        }
        let what = "\(label): content=\(c) banner=\(b) fill=\(f) z=\(i["z"]) \(counters(i)) | \(i.raw)"
        print("OVERLAYRECT \(path) \(what)")
        XCTAssertEqual(b.width, c.width, accuracy: 1, "banner width = content width: \(what)")
        XCTAssertEqual(b.height, b.width * 9 / 16, accuracy: 1, "banner 16:9: \(what)")
        XCTAssertEqual(b.maxY, c.maxY, accuracy: 1, "banner on the content's bottom: \(what)")
        XCTAssertEqual(b.midX, c.midX, accuracy: 1, "banner centred on the content: \(what)")
        XCTAssertEqual(f.minX, c.minX, accuracy: 1, "fill minX: \(what)")
        XCTAssertEqual(f.minY, c.minY, accuracy: 1, "fill minY: \(what)")
        XCTAssertEqual(f.maxX, c.maxX, accuracy: 1, "fill maxX: \(what)")
        XCTAssertEqual(f.maxY, c.maxY, accuracy: 1, "fill maxY: \(what)")
        return c
    }

    /// Across a scroll: the overlay bodies (library roots and the demo's) did not run; on the iOS 15 host path (forced
    /// fallbacks) the reader's closure did not either (design M6b R2). Layout placements (`ovp`, 16+) are only printed.
    private func assertNoOverlayBodies(_ a: Info, _ b: Info, _ label: String) {
        let what = "\(label): before \(counters(a)) after \(counters(b)) | \(b.raw)"
        print("OVERLAYMOTION \(path) \(label) delta ovb=\(b["ovb"] - a["ovb"]) ovh=\(b["ovh"] - a["ovh"]) ovr=\(b["ovr"] - a["ovr"]) "
              + "ovp=\(b["ovp"] - a["ovp"]) effect=\(b["effect"] - a["effect"])")
        for k in ["ovb", "mk", "bn", "tn"] { XCTAssertEqual(b[k], a[k], "\(k) unchanged: \(what)") }
        if forced { XCTAssertEqual(b["ovr"], a["ovr"], "reader closure did not run during the scroll: \(what)") }
    }

    /// Drags the content where it is vertically scrollable (slow, held before the release: no fling) and checks that
    /// the banner and the tint moved with it; a pure scroll runs no overlay body.
    private func scrollAndCheck(_ app: XCUIApplication, _ label: String, from: CGVector, to: CGVector) {
        let before = info(app, "\(label).beforeDrag")
        let visibleHeight = before["vh"] - before["it"] - before["ib"]
        guard before["ch"] * before["z"] > visibleHeight + 50 else {
            print("OVERLAYSCROLL \(path) \(label) not scrollable: ch=\(before["ch"]) z=\(before["z"]) visible=\(visibleHeight)")
            return
        }
        guard let r0 = contentRect(markers(app)) else { XCTFail("\(label): markers missing: \(before.raw)"); return }
        let s = element(app, "scrollerView")
        s.coordinate(withNormalizedOffset: from).press(forDuration: 0.05, thenDragTo: s.coordinate(withNormalizedOffset: to),
                                                       withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app, "\(label).dragged")
        guard let r1 = checkBannerAndFill(app, i, "\(label).dragged") else { return }
        let what = "\(label): content before=\(r0) after=\(r1) oy \(before["oy"]) -> \(i["oy"]) | \(i.raw)"
        print("OVERLAYSCROLL \(path) \(what) delta ovh=\(i["ovh"] - before["ovh"]) ovr=\(i["ovr"] - before["ovr"]) "
              + "ovp=\(i["ovp"] - before["ovp"])")
        XCTAssertGreaterThan(abs(r1.minY - r0.minY), 50, "the drag scrolled the content: \(what)")
        XCTAssertEqual(r1.minY - r0.minY, -(i["oy"] - before["oy"]), accuracy: 1.5, "content moved by the offset change: \(what)")
        XCTAssertGreaterThan(i["effect"], before["effect"], "the drag drew frames: \(what)")
        assertNoOverlayBodies(before, i, "\(label) scroll")
    }

    // MARK: Tests

    /// T1: zoomed 2.5x on the detail, rotate x4. After every rotation the marker overlay sits on its content point and
    /// scales with the content; even rotations put it back on its initial frame; no overlay body ran (counters zeroed
    /// after Zoom).
    func testMarkerOverlayStaysOnItsContentPointAcrossRotations() {
        let app = launch()
        app.buttons["Zoom"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let i0 = info(app, "t1.0")
        XCTAssertGreaterThan(i0["z"], 1.5, "zoomed: \(i0.raw)")
        let f0 = checkMarker(app, i0, "t1.0")
        var last = i0
        for n in 1...4 {
            rotate(n % 2 == 1 ? .landscapeLeft : .portrait)
            let i = info(app, "t1.\(n)")
            let f = checkMarker(app, i, "t1.\(n)")
            XCTAssertEqual(i["z"], i0["z"], accuracy: 1e-3, "scale kept at rotation \(n): \(i.raw)")
            if n % 2 == 0, let f, let f0 {
                let d = max(abs(f.minX - f0.minX), abs(f.minY - f0.minY), abs(f.width - f0.width), abs(f.height - f0.height))
                XCTAssertLessThanOrEqual(d, 0.5, "overlay back at its initial frame after \(n) rotations: \(f) vs \(f0): \(i.raw)")
            }
            last = i
        }
        let what = "\(counters(last)) | \(last.raw)"
        print("OVERLAYCOUNTERS \(path) t1 after 4 rotations: \(counters(last))")
        XCTAssertEqual(last["mk"], 0, "the marker's body never ran through four rotations: \(what)")
        XCTAssertEqual(last["ovb"], 0, "no overlay body ran through four rotations: \(what)")
        XCTAssertEqual(last["bn"], 0, "the banner's body never ran: \(what)")
        XCTAssertEqual(last["tn"], 0, "the tint's body never ran: \(what)")
        XCTAssertEqual(last["body"], 0, "content body: \(what)")
        XCTAssertEqual(last["jump"], 0, "no resize jump frames (as ResizeUITests' user-tree rotations): \(what)")
        // The other host path's counter stays 0 (Layout on 16+, the reader on iOS 15 / forced fallbacks).
        XCTAssertEqual(last[forced ? "ovp" : "ovr"], 0, "host path: \(what)")
    }

    /// T2: at fit, portrait -> landscape -> portrait, the banner (full width, 16:9, bottom edge) and the tint (the content
    /// rect) follow the content rect; a drag moves them with the content. No overlay body runs.
    func testBannerAndTintFollowTheContentRect() {
        let app = launch()
        app.buttons["Fit"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let p0 = info(app, "t2.portrait")
        checkBannerAndFill(app, p0, "t2.portrait")
        scrollAndCheck(app, "t2.portrait", from: CGVector(dx: 0.5, dy: 0.75), to: CGVector(dx: 0.5, dy: 0.45))
        rotate(.landscapeLeft)
        let l = info(app, "t2.landscape")
        XCTAssertNotEqual(l["vw"], p0["vw"], "rotated: \(l.raw)")
        checkBannerAndFill(app, l, "t2.landscape")
        scrollAndCheck(app, "t2.landscape", from: CGVector(dx: 0.5, dy: 0.85), to: CGVector(dx: 0.5, dy: 0.5))
        rotate(.portrait)
        let p1 = info(app, "t2.portraitBack")
        checkBannerAndFill(app, p1, "t2.portraitBack")
        let what = "\(counters(p1)) | \(p1.raw)"
        print("OVERLAYCOUNTERS \(path) t2 end: \(counters(p1))")
        for k in ["ovb", "mk", "bn", "tn", "body"] { XCTAssertEqual(p1[k], 0, "\(k) == 0 after scrolls and rotations: \(what)") }
    }

    /// T3: a tap on the banner's button fires it once; a slow drag that starts on it scrolls and does not fire it.
    func testBannerButtonFiresOnTapNotOnDrag() {
        let app = launch()
        app.buttons["Fit"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let scroller = element(app, "scrollerView").frame
        if let b = frame(app, "overlay.banner.button"), !scroller.insetBy(dx: 0, dy: 40).contains(b) {
            // The banner hangs below the viewport at the fit: zoom 1 (the fit), content bottom 20 pt below the viewport's.
            app.buttons["Bottom"].tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        let i0 = info(app, "t3.ready")
        let button = element(app, "overlay.banner.button")
        guard button.exists, let banner = frame(app, "overlay.banner") else {
            XCTFail("banner button missing: \(i0.raw)")
            return
        }
        let bf = button.frame
        print("OVERLAYTAP \(path) scroller=\(scroller) banner=\(banner) button=\(bf)")
        XCTAssertTrue(scroller.contains(bf), "button in view: \(bf) scroller=\(scroller): \(i0.raw)")
        button.tap()
        Thread.sleep(forTimeInterval: 0.5)
        let i1 = info(app, "t3.tapped")
        XCTAssertEqual(i1["btap"], 1, "a tap fires the banner button once: \(counters(i1)) | \(i1.raw)")
        // Press on the button (inside the banner), then drag 120 pt up slowly and hold: a pan, not a tap.
        let bf2 = button.frame
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: bf2.midX, dy: bf2.midY))
        let end = start.withOffset(CGVector(dx: 0, dy: -120))
        XCTAssertTrue(banner.contains(CGPoint(x: bf2.midX, y: bf2.midY)), "the drag starts on the banner: \(bf2) in \(banner)")
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        let i2 = info(app, "t3.dragged")
        let what = "before \(counters(i1)) after \(counters(i2)) | \(i2.raw)"
        XCTAssertEqual(i2["btap"], 1, "a drag that starts on the button does not fire it: \(what)")
        XCTAssertGreaterThan(i2["effect"], i1["effect"], "the scroll view took the drag (drew frames): \(what)")
        assertNoOverlayBodies(i1, i2, "t3 drag")
    }

    /// T4: `.counterScaled` marker: 6 x 6 on screen at the fit, zoomed, after a rotation and back, and after a pinch; its
    /// centre stays on `marker.detail`. Its body never runs (the counter-scale leaf does the work; `ocs` may count).
    func testCounterScaledMarkerKeepsItsScreenSize() {
        let app = launch(counterScaled: true)
        app.buttons["Fit"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let i0 = info(app, "t4.fit")
        checkMarker(app, i0, "t4.fit", counterScaled: true)
        app.buttons["Zoom"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let i1 = info(app, "t4.zoomed")
        XCTAssertGreaterThan(i1["z"], 1.9, "zoomed: \(i1.raw)")
        checkMarker(app, i1, "t4.zoomed", counterScaled: true)
        rotate(.landscapeLeft)
        let i2 = info(app, "t4.landscape")
        checkMarker(app, i2, "t4.landscape", counterScaled: true)
        rotate(.portrait)
        let i3 = info(app, "t4.portraitBack")
        checkMarker(app, i3, "t4.portraitBack", counterScaled: true)
        XCTAssertEqual(i3["mk"], 0, "the marker's body did not run after Zoom and a rotation round trip: \(counters(i3)) | \(i3.raw)")
        XCTAssertEqual(i3["ovb"], 0, "no overlay body ran: \(counters(i3)) | \(i3.raw)")
        // A pinch: a live zoom (not zeroed afterwards) runs the counter-scale leaf, never the marker's body. Zooming in:
        // the fingers start near the centre (a pinch-in starts them far apart, one on the readout, and became a pan).
        element(app, "scrollerView").pinch(withScale: 1.5, velocity: 1)
        Thread.sleep(forTimeInterval: 1.5)
        let i4 = info(app, "t4.pinched")
        let what = "\(counters(i4)) | \(i4.raw)"
        print("OVERLAYCOUNTERS \(path) t4 pinched: z \(i3["z"]) -> \(i4["z"]) \(counters(i4))")
        XCTAssertGreaterThan(i4["z"], i3["z"] + 0.1, "the pinch zoomed in: \(what)")
        checkMarker(app, i4, "t4.pinched", counterScaled: true)
        XCTAssertEqual(i4["mk"], 0, "the marker's body did not run through the pinch: \(what)")
        XCTAssertEqual(i4["ovb"], 0, "no overlay body ran through the pinch: \(what)")
    }
}
