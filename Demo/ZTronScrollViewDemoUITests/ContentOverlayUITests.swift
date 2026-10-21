import XCTest

/// M6b content-integral overlays (design docs/design/M6b-content-overlay.md §4 "UI") on the user's full-screen tree
/// (`-ZTronResizeUserTree2 -ZTronResizeOverlay`): a 6 pt marker pinned on the content point (30 %, 65 %), a 16:9 banner
/// at the content's bottom, a tint over the whole content, a label with a constant input centred on the content point (70 %, 30 %)
/// and a bare (`Equatable`) `Text` at its top-leading corner. Ground truth: the `GeometryReader` markers drawn inside the content (`marker.*`,
/// `ContentMarkers`) and the app's DEBUG counters in the readout, never XCUI state alone: `ovb` overlay roots, `ovh` host
/// bodies, `ovr` / `ovp` the iOS 15 reader closure / Layout placements, `mk` / `bn` / `tn` / `lb` the demo overlays'
/// bodies, `body` the content's (it depends on the reader's width: it runs on rotation, never on motion), `btap` the
/// banner button, `lag` / `lks` the per-frame lockstep probe (fill size vs content size between drawn frames).
final class ContentOverlayUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var path: String { forced ? "forced" : "preferred" }
    /// The host the library picks: the Layout one on 16+ unless the fallbacks are forced, the reader on iOS 15.
    private var layoutPath: Bool { !forced && ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 16 }

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() { XCUIDevice.shared.orientation = .portrait }

    private func launch(counterScaled: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "resize"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + ["-ZTronResizeUserTree2", "-ZTronResizeOverlay"] + (counterScaled ? ["-ZTronResizeOverlayCounterScaled"] : [])
            + extra
        app.launch()
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    // MARK: Readout

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

    /// Readouts until two in a row show the scroll view at rest at the same place (phase idle, same offset, zoom and
    /// viewport): under host load a rotation or a release can still be running after a fixed sleep.
    private func settled(_ app: XCUIApplication, _ label: String, after first: Info? = nil) -> Info {
        var prev = first ?? info(app, label)
        for _ in 0..<12 {
            let i = info(app, label)
            let same = ["ox", "oy", "z", "vw", "vh"].allSatisfy { abs(i[$0] - prev[$0]) < 0.01 }
            if same, i["phase"] == 0, prev["phase"] == 0 { return i }
            prev = i
        }
        XCTFail("\(label): the scroll view did not come to rest: \(prev.raw)")
        return prev
    }

    /// Taps a demo button that zeroes the counters 0.3 s later (`resetCounters`), waits for that reset (`rst` grows)
    /// and for the scroll view to rest; the returned readout is the baseline after the reset.
    private func tapAndSettle(_ app: XCUIApplication, _ button: String, _ label: String) -> Info {
        let g = info(app, "\(label).preReset")["rst"]
        app.buttons[button].tap()
        var i = info(app, label)
        for _ in 0..<15 where i["rst"] <= g {
            Thread.sleep(forTimeInterval: 0.2)
            i = info(app, label)
        }
        XCTAssertGreaterThan(i["rst"], g, "\(label): the counters were reset after \(button): \(i.raw)")
        return settled(app, label, after: i)
    }

    private func rotate(_ o: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = o
        Thread.sleep(forTimeInterval: 1.5)
    }

    // MARK: Markers (as ResizeUITests)

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

    private func centre(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

    private static let counterKeys = ["ovb", "ovh", "ovr", "ovp", "ocs", "mk", "bn", "tn", "lb", "body", "btap", "lag", "lks",
                                      "jump", "effect"]

    private func counters(_ i: Info) -> String {
        Self.counterKeys.map { "\($0)=\(Int(i[$0]))" }.joined(separator: " ")
    }

    private func deltas(_ a: Info, _ b: Info) -> String {
        Self.counterKeys.map { "\($0)=\(Int(b[$0] - a[$0]))" }.joined(separator: " ")
    }

    // MARK: Checks

    /// `overlay.detail` (pinned with its centre on the content point (30 %, 65 %)) against `marker.detail` (the
    /// `GeometryReader` marker at the same fraction) and the marker-derived screen point; its size is 6 pt scaled with
    /// the content (`.withContent`) or 6 pt on screen (`.counterScaled`). Overlay and marker are compared directly
    /// (measured error ~1e-13 pt: 0.1 pt); the marker-derived point carries the markers' pixel quantization
    /// (`markerTolerance`). Returns the overlay's frame.
    @discardableResult
    private func checkMarker(_ app: XCUIApplication, _ i: Info, _ label: String, counterScaled: Bool = false) -> CGRect? {
        let m = markers(app)
        guard let f = frame(app, "overlay.detail"), let d = m["detail"] else {
            XCTFail("\(label): overlay.detail or marker.detail missing, markers=\(m): \(i.raw)")
            return nil
        }
        let c = centre(f)
        let eMarker = dist(c, d), eSpace = dist(c, screenPoint(m, CGPoint(x: 0.3, y: 0.65)))
        let want = counterScaled ? 6 : 6 * i["z"]
        let what = "\(label): overlay=\(f) marker.detail=\(d) errMarker=\(eMarker) errSpace=\(eSpace) wantSize=\(want) "
            + "z=\(i["z"]) \(counters(i)) | \(i.raw)"
        print("OVERLAYMARKER \(path) \(what)")
        XCTAssertEqual(m.count, 4, "markers exposed: \(what)")
        XCTAssertLessThanOrEqual(eMarker, 0.1, "overlay centre on marker.detail: \(what)")
        XCTAssertTrue(eSpace >= 0 && eSpace <= markerTolerance(i), "overlay centre on the content point (0.3, 0.65): \(what)")
        // The readout's zoom has 4 decimals: 6 * 4 * 5e-5 = 0.0012 pt.
        XCTAssertEqual(f.width, want, accuracy: 0.1, "overlay width: \(what)")
        XCTAssertEqual(f.height, want, accuracy: 0.1, "overlay height: \(what)")
        return f
    }

    /// The markers are placed on the pixel grid in the unscaled content (1/3 pt), and the zoom scales that error: a
    /// marker-derived content rect is off by up to 1.25 x 1/3 x z pt (1.33 pt measured at z = 4).
    private func markerTolerance(_ i: Info) -> Double { max(1, 0.5 * i["z"]) }

    struct Rects { var content: CGRect; var banner: CGRect; var fill: CGRect; var label: CGRect; var text: CGRect }

    /// `overlay.banner` (full content width, 16:9, on the content's bottom edge), `overlay.fill` (the content rect),
    /// `overlay.label` (centred on the content point (70 %, 30 %)) and the bare `Text` (its top-leading corner on the
    /// content's) against the marker-derived content rect, and the banner and fill sizes against the readout's content
    /// size times the zoom (exact; a viewport-space overlay would keep the viewport's width at any zoom).
    @discardableResult
    private func checkBannerAndFill(_ app: XCUIApplication, _ i: Info, _ label: String) -> Rects? {
        let m = markers(app)
        let text = app.staticTexts["Bare text"]
        guard let c = contentRect(m), let b = frame(app, "overlay.banner"), let f = frame(app, "overlay.fill"),
              let l = frame(app, "overlay.label"), text.exists else {
            XCTFail("\(label): markers=\(m) banner=\(String(describing: frame(app, "overlay.banner"))) "
                    + "fill=\(String(describing: frame(app, "overlay.fill"))) "
                    + "label=\(String(describing: frame(app, "overlay.label"))) text=\(text.exists): \(i.raw)")
            return nil
        }
        let t = text.frame
        let w = i["cw"] * i["z"], h = i["ch"] * i["z"], tol = markerTolerance(i)
        let what = "\(label): content=\(c) banner=\(b) fill=\(f) label=\(l) text=\(t) cw*z=\(w) ch*z=\(h) z=\(i["z"]) "
            + "\(counters(i)) | \(i.raw)"
        print("OVERLAYRECT \(path) \(what)")
        XCTAssertEqual(b.width, c.width, accuracy: tol, "banner width = content width: \(what)")
        XCTAssertEqual(b.width, w, accuracy: 1, "banner width = content width x zoom: \(what)")
        XCTAssertEqual(b.height, b.width * 9 / 16, accuracy: 1, "banner 16:9: \(what)")
        XCTAssertEqual(b.maxY, c.maxY, accuracy: tol, "banner on the content's bottom: \(what)")
        XCTAssertEqual(b.midX, c.midX, accuracy: tol, "banner centred on the content: \(what)")
        XCTAssertEqual(f.minX, c.minX, accuracy: tol, "fill minX: \(what)")
        XCTAssertEqual(f.minY, c.minY, accuracy: tol, "fill minY: \(what)")
        XCTAssertEqual(f.maxX, c.maxX, accuracy: tol, "fill maxX: \(what)")
        XCTAssertEqual(f.maxY, c.maxY, accuracy: tol, "fill maxY: \(what)")
        XCTAssertEqual(f.width, w, accuracy: 1, "fill width = content width x zoom: \(what)")
        XCTAssertEqual(f.height, h, accuracy: 1, "fill height = content height x zoom: \(what)")
        XCTAssertLessThanOrEqual(dist(centre(l), screenPoint(m, CGPoint(x: 0.7, y: 0.3))), tol,
                                 "label centred on the content point (0.7, 0.3): \(what)")
        XCTAssertEqual(t.minX, c.minX, accuracy: tol, "bare text on the content's leading edge: \(what)")
        XCTAssertEqual(t.minY, c.minY, accuracy: tol, "bare text on the content's top: \(what)")
        return Rects(content: c, banner: b, fill: f, label: l, text: t)
    }

    /// Across motion (a scroll, a pinch): no overlay body (library roots, the demo's), no content body, no host body,
    /// no reader closure (iOS 15 host), and the lockstep probe saw no frame with the fill off the content. Layout
    /// placements (16+) are at most `placements`: 0 without a control in the overlays; with the banner's `Button`, one
    /// per flip of the scroll view's `.disabled(blocked)` (motion start, motion end): 2, never per frame (measured 2
    /// with the button, 0 with `-ZTronResizeOverlayNoButton`, against 45-140 drawn frames). nil: not bounded, for a drag
    /// that starts by pressing the button: its pressed / cancelled states re-lay it out (measured 2 and 25 on 27.0 for
    /// the same script); that work follows the control's state, not the scroll (host and bodies stay 0).
    private func assertNoOverlayWork(_ a: Info, _ b: Info, _ label: String, placements bound: Int?) {
        let what = "\(label): before \(counters(a)) after \(counters(b)) | \(b.raw)"
        print("OVERLAYMOTION \(path) \(label) delta \(deltas(a, b))")
        for k in ["ovb", "mk", "bn", "tn", "lb", "body"] { XCTAssertEqual(b[k], a[k], "\(k) unchanged: \(what)") }
        XCTAssertEqual(b["ovh"], a["ovh"], "the host's body did not run: \(what)")
        XCTAssertEqual(b["ovr"], a["ovr"], "the reader's closure did not run: \(what)")
        let placements = b["ovp"] - a["ovp"]
        XCTAssertGreaterThanOrEqual(placements, 0, what)
        if !layoutPath {
            XCTAssertEqual(placements, 0, "no Layout host on this path: \(what)")
        } else if let bound {
            XCTAssertLessThanOrEqual(placements, Double(bound), "Layout placements (at most \(bound): the button's enabled flips): \(what)")
        }
        XCTAssertEqual(b["lag"], a["lag"], "the fill was laid out with the content in every frame: \(what)")
    }

    /// Drags the content where it is vertically scrollable (slow, held before the release: no fling) and checks that
    /// the overlays moved with it; a pure scroll runs no overlay, content or host work.
    private func scrollAndCheck(_ app: XCUIApplication, _ label: String, from: CGVector, to: CGVector) {
        let before = settled(app, "\(label).beforeDrag")
        let visibleHeight = before["vh"] - before["it"] - before["ib"]
        guard before["ch"] * before["z"] > visibleHeight + 50 else {
            XCTFail("\(label): not scrollable: ch=\(before["ch"]) z=\(before["z"]) visible=\(visibleHeight) | \(before.raw)")
            return
        }
        guard let r0 = contentRect(markers(app)) else { XCTFail("\(label): markers missing: \(before.raw)"); return }
        let s = element(app, "scrollerView")
        s.coordinate(withNormalizedOffset: from).press(forDuration: 0.05, thenDragTo: s.coordinate(withNormalizedOffset: to),
                                                       withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.0)
        let i = settled(app, "\(label).dragged")
        guard let r1 = checkBannerAndFill(app, i, "\(label).dragged")?.content else { return }
        let what = "\(label): content before=\(r0) after=\(r1) oy \(before["oy"]) -> \(i["oy"]) | \(i.raw)"
        print("OVERLAYSCROLL \(path) \(what)")
        XCTAssertGreaterThan(abs(r1.minY - r0.minY), 50, "the drag scrolled the content: \(what)")
        XCTAssertEqual(r1.minY - r0.minY, -(i["oy"] - before["oy"]), accuracy: 1.5, "content moved by the offset change: \(what)")
        XCTAssertGreaterThan(i["effect"], before["effect"], "the drag drew frames: \(what)")
        assertNoOverlayWork(before, i, "\(label) scroll", placements: 0)
    }

    // MARK: Tests

    /// T1: zoomed 2.5x on the detail and dragged so the detail is off the visible centre (rotation keeps the centre, so
    /// an overlay at the viewport centre would pass otherwise), rotate x4, then pinch. After every step the marker
    /// overlay sits on its content point and scales with the content, the banner, tint, label and text follow the
    /// zoomed content rect; even rotations put every overlay back on its initial frame. Positive controls: right after
    /// launch every overlay body ran; the rotations ran the host and the content (it depends on the width) but no
    /// overlay body; the pinch ran nothing.
    func testMarkerOverlayStaysOnItsContentPointAcrossRotations() {
        let app = launch()
        let start = settled(app, "t1.launch")
        let what0 = "\(counters(start)) | \(start.raw)"
        XCTAssertGreaterThanOrEqual(start["ovb"], 5, "every overlay root ran at launch (positive control): \(what0)")
        for k in ["mk", "bn", "tn", "lb", "ovh", "body"] {
            XCTAssertGreaterThanOrEqual(start[k], 1, "\(k) ran at launch (positive control): \(what0)")
        }
        XCTAssertEqual(start[layoutPath ? "ovr" : "ovp"], 0, "host path: \(what0)")
        XCTAssertGreaterThanOrEqual(start[layoutPath ? "ovp" : "ovr"], 1, "host path: \(what0)")

        _ = tapAndSettle(app, "Zoom", "t1.zoomed")
        // Off-centre: drag the content up-left by about 100 pt (slow, held: no fling).
        let s = element(app, "scrollerView")
        let a = s.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.6))
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(CGVector(dx: -100, dy: -100)), withVelocity: .slow,
                thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.0)
        let i0 = settled(app, "t1.0")
        XCTAssertGreaterThan(i0["z"], 1.5, "zoomed: \(i0.raw)")
        let f0 = checkMarker(app, i0, "t1.0")
        let r0 = checkBannerAndFill(app, i0, "t1.0")
        let v0 = s.frame
        if let f0 {
            XCTAssertGreaterThan(dist(centre(f0), centre(v0)), 60, "the detail is off the visible centre: \(f0) in \(v0)")
        }
        var last = i0
        for n in 1...4 {
            rotate(n % 2 == 1 ? .landscapeLeft : .portrait)
            let i = settled(app, "t1.\(n)")
            let f = checkMarker(app, i, "t1.\(n)")
            let r = checkBannerAndFill(app, i, "t1.\(n)")
            XCTAssertEqual(i["z"], i0["z"], accuracy: 1e-3, "scale kept at rotation \(n): \(i.raw)")
            if n % 2 == 1, let f {
                XCTAssertGreaterThan(dist(centre(f), centre(s.frame)), 60, "the detail is off the visible centre: \(f)")
            }
            if n % 2 == 0 {
                let pairs: [(String, CGRect?, CGRect?)] = [("marker", f, f0), ("banner", r?.banner, r0?.banner),
                                                          ("fill", r?.fill, r0?.fill), ("label", r?.label, r0?.label),
                                                          ("text", r?.text, r0?.text)]
                for (name, now, then) in pairs {
                    guard let now, let then else { continue }
                    let d = max(abs(now.minX - then.minX), abs(now.minY - then.minY), abs(now.width - then.width),
                                abs(now.height - then.height))
                    XCTAssertLessThanOrEqual(d, 0.5, "\(name) back at its initial frame after \(n) rotations: \(now) vs \(then): \(i.raw)")
                }
            }
            last = i
        }
        let what = "\(counters(last)) | \(last.raw)"
        print("OVERLAYCOUNTERS \(path) t1 after 4 rotations: \(counters(last))")
        for k in ["ovb", "mk", "bn", "tn", "lb"] {
            XCTAssertEqual(last[k], 0, "no overlay body (\(k)) ran through a drag and four rotations: \(what)")
        }
        // Positive controls: the user's GeometryReader rebuilt the scroll view (host bodies) and the content (it takes
        // the reader's width) on every rotation; the probe saw the content's size change each time.
        XCTAssertGreaterThanOrEqual(last["ovh"], 4, "the host was re-evaluated by the rotations: \(what)")
        XCTAssertGreaterThanOrEqual(last["body"], 4, "the content (width-dependent) re-rendered on the rotations: \(what)")
        XCTAssertGreaterThanOrEqual(last["lks"], 4, "the lockstep probe saw every rotation's content size: \(what)")
        XCTAssertEqual(last["lag"], 0, "the fill was laid out with the content in every drawn frame: \(what)")
        XCTAssertEqual(last["jump"], 0, "no resize jump frames (as ResizeUITests' user-tree rotations): \(what)")
        XCTAssertEqual(last[layoutPath ? "ovr" : "ovp"], 0, "host path: \(what)")

        // A live pinch with the default `.withContent` scaling (not zeroed afterwards): nothing runs.
        s.pinch(withScale: 1.5, velocity: 1)
        Thread.sleep(forTimeInterval: 1.5)
        let p = settled(app, "t1.pinched")
        XCTAssertGreaterThan(p["z"], last["z"] + 0.1, "the pinch zoomed in: \(p.raw)")
        checkMarker(app, p, "t1.pinched")
        checkBannerAndFill(app, p, "t1.pinched")
        assertNoOverlayWork(last, p, "t1 pinch", placements: 2)
    }

    /// T2: at fit, portrait -> landscape -> portrait, the banner (full width, 16:9, bottom edge), the tint (the content
    /// rect), the label and the text follow the content rect; a drag moves them with the content and runs nothing, not
    /// even a Layout placement: the banner holds a label here (`-ZTronResizeOverlayNoButton`; its button is T3's).
    func testBannerAndTintFollowTheContentRect() {
        let app = launch(extra: ["-ZTronResizeOverlayNoButton"])
        let p0 = tapAndSettle(app, "Fit", "t2.portrait")
        checkBannerAndFill(app, p0, "t2.portrait")
        scrollAndCheck(app, "t2.portrait", from: CGVector(dx: 0.5, dy: 0.75), to: CGVector(dx: 0.5, dy: 0.45))
        rotate(.landscapeLeft)
        let l = settled(app, "t2.landscape")
        XCTAssertNotEqual(l["vw"], p0["vw"], "rotated: \(l.raw)")
        checkBannerAndFill(app, l, "t2.landscape")
        scrollAndCheck(app, "t2.landscape", from: CGVector(dx: 0.5, dy: 0.85), to: CGVector(dx: 0.5, dy: 0.5))
        rotate(.portrait)
        let p1 = settled(app, "t2.portraitBack")
        checkBannerAndFill(app, p1, "t2.portraitBack")
        let what = "\(counters(p1)) | \(p1.raw)"
        print("OVERLAYCOUNTERS \(path) t2 end: \(counters(p1))")
        for k in ["ovb", "mk", "bn", "tn", "lb", "lag"] { XCTAssertEqual(p1[k], 0, "\(k) == 0 after scrolls and rotations: \(what)") }
    }

    /// T3: a tap on the banner's button fires it once; a slow drag that starts on it scrolls (the content follows the
    /// finger, so the release lands on the button again) and does not fire it.
    func testBannerButtonFiresOnTapNotOnDrag() {
        let app = launch()
        _ = tapAndSettle(app, "Fit", "t3.fit")
        let scroller = element(app, "scrollerView").frame
        if let b = frame(app, "overlay.banner.button"), !scroller.insetBy(dx: 0, dy: 40).contains(b) {
            // The banner hangs below the viewport at the fit: zoom 1 (the fit), content bottom 20 pt below the viewport's.
            _ = tapAndSettle(app, "Bottom", "t3.bottom")
        }
        let i0 = settled(app, "t3.ready")
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
        let i1 = settled(app, "t3.tapped")
        XCTAssertEqual(i1["btap"], 1, "a tap fires the banner button once: \(counters(i1)) | \(i1.raw)")
        // Press on the button, then drag 100 pt DOWN slowly and hold: the content is 20 pt short of its bottom bound,
        // so it has hundreds of points of free travel this way and follows the finger 1:1 after the pan's 10 pt
        // minimum distance; at the release the finger is ~10 pt below the button's centre (34 pt tall), i.e. on it.
        let bf2 = button.frame
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: bf2.midX, dy: bf2.midY))
        let end = start.withOffset(CGVector(dx: 0, dy: 100))
        XCTAssertTrue(banner.contains(CGPoint(x: bf2.midX, y: bf2.midY)), "the drag starts on the banner: \(bf2) in \(banner)")
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        let i2 = settled(app, "t3.dragged")
        let bf3 = button.frame
        let what = "before \(counters(i1)) after \(counters(i2)) oy \(i1["oy"]) -> \(i2["oy"]) button \(bf2) -> \(bf3) | \(i2.raw)"
        print("OVERLAYTAP \(path) dragged: \(what)")
        XCTAssertEqual(i2["oy"] - i1["oy"], -90, accuracy: 4, "the scroll view took the drag, 1:1 after the slop: \(what)")
        XCTAssertTrue(bf3.insetBy(dx: 0, dy: -4).contains(CGPoint(x: bf2.midX, y: bf2.midY + 100)),
                      "the release point is on the button: \(what)")
        XCTAssertEqual(i2["btap"], 1, "a drag that starts on the button does not fire it: \(what)")
        assertNoOverlayWork(i1, i2, "t3 drag", placements: nil)
    }

    /// T4: `.counterScaled` marker: 6 x 6 on screen at the fit, zoomed, after a rotation and back, and after a pinch; its
    /// centre stays on `marker.detail`. Its body never runs (the counter-scale leaf does the work; `ocs` may count).
    func testCounterScaledMarkerKeepsItsScreenSize() {
        let app = launch(counterScaled: true)
        let i0 = tapAndSettle(app, "Fit", "t4.fit")
        checkMarker(app, i0, "t4.fit", counterScaled: true)
        let i1 = tapAndSettle(app, "Zoom", "t4.zoomed")
        XCTAssertGreaterThan(i1["z"], 1.9, "zoomed: \(i1.raw)")
        checkMarker(app, i1, "t4.zoomed", counterScaled: true)
        rotate(.landscapeLeft)
        let i2 = settled(app, "t4.landscape")
        checkMarker(app, i2, "t4.landscape", counterScaled: true)
        rotate(.portrait)
        let i3 = settled(app, "t4.portraitBack")
        checkMarker(app, i3, "t4.portraitBack", counterScaled: true)
        XCTAssertEqual(i3["mk"], 0, "the marker's body did not run through a rotation round trip: \(counters(i3)) | \(i3.raw)")
        XCTAssertEqual(i3["ovb"], 0, "no overlay body ran: \(counters(i3)) | \(i3.raw)")
        // A pinch: a live zoom (not zeroed afterwards) runs the counter-scale leaf, never the marker's body. Zooming in:
        // the fingers start near the centre (a pinch-in starts them far apart, one on the readout, and became a pan).
        element(app, "scrollerView").pinch(withScale: 1.5, velocity: 1)
        Thread.sleep(forTimeInterval: 1.5)
        let i4 = settled(app, "t4.pinched")
        let what = "\(counters(i4)) | \(i4.raw)"
        print("OVERLAYCOUNTERS \(path) t4 pinched: z \(i3["z"]) -> \(i4["z"]) \(counters(i4))")
        XCTAssertGreaterThan(i4["z"], i3["z"] + 0.1, "the pinch zoomed in: \(what)")
        XCTAssertGreaterThan(i4["ocs"], i3["ocs"], "the counter-scale leaf followed the zoom: \(what)")
        checkMarker(app, i4, "t4.pinched", counterScaled: true)
        assertNoOverlayWork(i3, i4, "t4 pinch", placements: 2)
    }
}
