import XCTest

/// SHEET-s1 (docs/design/SHEET-spike.md): ZTronScrollView vs SwiftUI's ScrollView inside a bottom sheet. Characterization,
/// not a contract: a case passes when the harness worked (the sheet was up, the readout parsed); what moved is printed as
/// `SHEET ...` lines (grep the full log). The oracle is the app's own readout (`SheetProbe`: sheet top sampled per display
/// frame, content offset, double-move counters), the XCUIElement frames are the cross-check.
final class SheetUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var uikit: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_UIKIT"] == "1" }

    override func setUp() { continueAfterFailure = false }

    // MARK: harness

    private func launch(native: Bool, detents: String = "medium,large", start: String, interaction: String = "default",
                        noDismiss: Bool = false, introspect: Bool = false, yield: String = "none", plain: String? = nil) throws -> XCUIApplication {
        try XCTSkipIf(native && (forced || uikit), "the native variant ignores the fallback switches: preferred run only")
        let app = XCUIApplication()
        var args = ["-ZTronScreen", "sheet", "-ZTronSheetDetents", detents, "-ZTronSheetStart", start, "-ZTronSheetInteraction", interaction]
        if native { args.append("-ZTronSheetNative") }
        if noDismiss { args.append("-ZTronSheetNoDismiss") }
        if introspect { args.append("-ZTronSheetIntrospect") }
        if yield != "none" { args += ["-ZTronSheetYield", yield] }
        if let plain { args += ["-ZTronSheetPlain", plain] }
        if forced { args.append("-ZTronForceAllFallbacks") }
        if uikit { args.append("-ZTronForceUIKitObserver") }
        // Experiments (DBG-s7): `TEST_RUNNER_ZS_DEMO_PANMODE=gesture|high` attaches the pan the other way (DEBUG `PanGestureMode`).
        if let mode = ProcessInfo.processInfo.environment["ZS_DEMO_PANMODE"], !mode.isEmpty { args += ["-ZTronPanGestureMode", mode] }
        app.launchArguments = args
        app.launch()
        app.buttons["sheet.present"].tap()
        XCTAssertTrue(app.buttons["sheet.snapshot"].waitForExistence(timeout: 10), "the sheet appeared")
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    private var osTag: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion)"
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func parse(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for kv in s.split(separator: " ") {
            let p = kv.split(separator: "=", maxSplits: 1).map(String.init)
            if p.count == 2 { out[p[0]] = p[1] }
        }
        return out
    }

    /// Reads the readout (from the sheet if it is still up, else from the presenting screen) and prints one `SHEET` line.
    @discardableResult
    private func evidence(_ app: XCUIApplication, _ tag: String, wait: TimeInterval = 1.5) -> (dismissed: Bool, info: [String: String]) {
        Thread.sleep(forTimeInterval: wait)
        var dismissed = false
        var raw = ""
        var xcui = ""
        if app.buttons["sheet.snapshot"].exists {
            let sc = element(app, "sheet.scroller").frame
            let snap = app.buttons["sheet.snapshot"].frame
            let row0 = app.staticTexts["Row 0"]
            let rowOff = row0.exists ? "\(Int(sc.minY - row0.frame.minY))" : "-"
            xcui = "xcui snapY=\(Int(snap.minY)) scrollerY=\(Int(sc.minY)) scrollerH=\(Int(sc.height)) row0Off=\(rowOff)"
            app.buttons["sheet.snapshot"].tap()
            Thread.sleep(forTimeInterval: 0.3)
            raw = element(app, "sheet.info").value as? String ?? ""
            if element(app, "sheet.rec").exists {
                print("SHEETREC os=\(osTag) path=\(uikit ? "uikit" : forced ? "forced" : "preferred") \(tag) | \(element(app, "sheet.rec").value as? String ?? "")")
            }
        } else {
            dismissed = true
            XCTAssertTrue(app.buttons["sheet.present"].waitForExistence(timeout: 5), "the presenting screen is back")
            app.buttons["sheet.baseSnapshot"].tap()
            Thread.sleep(forTimeInterval: 0.3)
            raw = element(app, "sheet.baseInfo").value as? String ?? ""
            xcui = "xcui sheet-gone"
        }
        let dc = element(app, "sheet.dismissCount").exists ? (element(app, "sheet.dismissCount").value as? String ?? "?") : "hidden"
        print("SHEET os=\(osTag) path=\(uikit ? "uikit" : forced ? "forced" : "preferred") \(tag) | \(raw) | \(xcui) | presentingScreenDismissCount=\(dc)")
        return (dismissed, parse(raw))
    }

    private func resetProbe(_ app: XCUIApplication) {
        app.buttons["sheet.reset"].tap()
        Thread.sleep(forTimeInterval: 0.4)
    }

    private func point(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
    }

    /// A vertical drag inside the scroller: `down` > 0 drags the finger down from near the scroller's top, < 0 drags it up
    /// from near its bottom. `flick` lifts at speed (release velocity), otherwise the finger holds still before lifting.
    private func drag(_ app: XCUIApplication, dy: CGFloat, flick: Bool = false, fromHeader: Bool = false) {
        let f = element(app, "sheet.scroller").frame
        let x = fromHeader ? 24 : f.minX + f.width * 0.5
        let startY = fromHeader ? f.minY - 30 : dy > 0 ? f.minY + 24 : f.maxY - 60
        let endY = startY + dy
        point(app, x, startY).press(forDuration: 0.05, thenDragTo: point(app, x, endY),
                                    withVelocity: flick ? .fast : .slow, thenHoldForDuration: flick ? 0 : 0.3)
    }

    private func tapButton(_ app: XCUIApplication, _ id: String) {
        app.buttons[id].tap()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: (a) at offset 0, drag down

    private func caseA1(native: Bool) throws {
        let app = try launch(native: native, start: "medium")
        resetProbe(app)
        drag(app, dy: 250)
        evidence(app, "case=A1 variant=\(native ? "native" : "ours") medium offset0 downSlow250")
    }
    func testA1_ours() throws { try caseA1(native: false) }
    func testA1_native() throws { try caseA1(native: true) }

    private func caseA2(native: Bool) throws {
        let app = try launch(native: native, start: "medium")
        resetProbe(app)
        drag(app, dy: 250, flick: true)
        evidence(app, "case=A2 variant=\(native ? "native" : "ours") medium offset0 downFlick250")
    }
    func testA2_ours() throws { try caseA2(native: false) }
    func testA2_native() throws { try caseA2(native: true) }

    private func caseA3(native: Bool) throws {
        let app = try launch(native: native, start: "large")
        resetProbe(app)
        drag(app, dy: 250)
        evidence(app, "case=A3 variant=\(native ? "native" : "ours") large offset0 downSlow250")
    }
    func testA3_ours() throws { try caseA3(native: false) }
    func testA3_native() throws { try caseA3(native: true) }

    private func caseA4(native: Bool) throws {
        let app = try launch(native: native, detents: "large", start: "large")
        resetProbe(app)
        drag(app, dy: 250)
        evidence(app, "case=A4 variant=\(native ? "native" : "ours") largeOnly offset0 downSlow250")
    }
    func testA4_ours() throws { try caseA4(native: false) }
    func testA4_native() throws { try caseA4(native: true) }

    // MARK: (b) scrolled to the middle, drag down (and up as the control)

    private func caseB1(native: Bool) throws {
        let app = try launch(native: native, start: "large")
        tapButton(app, "sheet.mid")
        resetProbe(app)
        drag(app, dy: 150)
        evidence(app, "case=B1 variant=\(native ? "native" : "ours") large offsetMid downSlow150")
    }
    func testB1_ours() throws { try caseB1(native: false) }
    func testB1_native() throws { try caseB1(native: true) }

    private func caseB2(native: Bool) throws {
        let app = try launch(native: native, start: "large")
        tapButton(app, "sheet.mid")
        resetProbe(app)
        drag(app, dy: -150)
        evidence(app, "case=B2 variant=\(native ? "native" : "ours") large offsetMid upSlow150")
    }
    func testB2_ours() throws { try caseB2(native: false) }
    func testB2_native() throws { try caseB2(native: true) }

    // MARK: (c) at the medium detent, drag up

    private func caseC(native: Bool, interaction: String, name: String) throws {
        let app = try launch(native: native, start: "medium", interaction: interaction)
        resetProbe(app)
        drag(app, dy: -250)
        evidence(app, "case=\(name) variant=\(native ? "native" : "ours") medium offset0 upSlow250 interaction=\(interaction)")
    }
    func testC1_ours() throws { try caseC(native: false, interaction: "default", name: "C1") }
    func testC1_native() throws { try caseC(native: true, interaction: "default", name: "C1") }
    func testC2_ours() throws { try caseC(native: false, interaction: "scrolls", name: "C2") }
    func testC2_native() throws { try caseC(native: true, interaction: "scrolls", name: "C2") }
    func testC3_ours() throws { try caseC(native: false, interaction: "resizes", name: "C3") }
    func testC3_native() throws { try caseC(native: true, interaction: "resizes", name: "C3") }

    // MARK: (d) at the large detent, scroll, then drag down from the top

    private func caseD1(native: Bool) throws {
        let app = try launch(native: native, start: "large")
        tapButton(app, "sheet.mid")
        resetProbe(app)
        drag(app, dy: 700)
        let a = evidence(app, "case=D1a variant=\(native ? "native" : "ours") large offsetMid downSlow700 (content past the top)")
        if a.dismissed {
            // iOS 18.x (docs/progress/DBG-s7.md): SwiftUI shares our `.simultaneousGesture` drag with the sheet's pan, the finger takes the
            // sheet along and dismisses it while the content stays put (on 17.5, 26.5 and 27.0 the content wins and the sheet is still up).
            // D1b starts from a fresh sheet at the top, which is the same state the scroll would have ended in.
            app.buttons["sheet.present"].tap()
            XCTAssertTrue(app.buttons["sheet.snapshot"].waitForExistence(timeout: 10), "the sheet came back")
            Thread.sleep(forTimeInterval: 1.5)
        }
        resetProbe(app)
        drag(app, dy: 250)
        evidence(app, "case=D1b variant=\(native ? "native" : "ours") large offsetTop downSlow250 (from the top)")
    }
    func testD1_ours() throws { try caseD1(native: false) }
    func testD1_native() throws { try caseD1(native: true) }

    /// One gesture that scrolls the content to its top and keeps going: does the sheet take over mid-gesture?
    private func caseD2(native: Bool) throws {
        let app = try launch(native: native, start: "large")
        tapButton(app, "sheet.near")
        resetProbe(app)
        drag(app, dy: 520)
        evidence(app, "case=D2 variant=\(native ? "native" : "ours") large offset220 downSlow520 (one gesture past the top)")
    }
    func testD2_ours() throws { try caseD2(native: false) }
    func testD2_native() throws { try caseD2(native: true) }

    // MARK: (e) interactiveDismissDisabled

    private func caseE1(native: Bool) throws {
        let app = try launch(native: native, start: "medium", noDismiss: true)
        resetProbe(app)
        drag(app, dy: 300)
        evidence(app, "case=E1 variant=\(native ? "native" : "ours") medium offset0 downSlow300 noDismiss")
    }
    func testE1_ours() throws { try caseE1(native: false) }
    func testE1_native() throws { try caseE1(native: true) }

    private func caseE2(native: Bool) throws {
        let app = try launch(native: native, detents: "large", start: "large", noDismiss: true)
        resetProbe(app)
        drag(app, dy: 250)
        evidence(app, "case=E2 variant=\(native ? "native" : "ours") largeOnly offset0 downSlow250 noDismiss")
    }
    func testE2_ours() throws { try caseE2(native: false) }
    func testE2_native() throws { try caseE2(native: true) }

    // MARK: mechanism: which recognizers fire (passive target/action hooks, -ZTronSheetIntrospect)

    private func caseM(native: Bool, name: String, start: String, mid: Bool, dy: CGFloat) throws {
        let app = try launch(native: native, start: start, introspect: true)
        // let the sampler's scans hook every recognizer before the first touch
        Thread.sleep(forTimeInterval: 1)
        if mid { tapButton(app, "sheet.mid") }
        resetProbe(app)
        drag(app, dy: dy)
        evidence(app, "case=\(name) variant=\(native ? "native" : "ours") \(start) mid=\(mid) dy=\(Int(dy))")
    }
    func testM1_ours() throws { try caseM(native: false, name: "M1", start: "medium", mid: false, dy: 250) }
    func testM1_native() throws { try caseM(native: true, name: "M1", start: "medium", mid: false, dy: 250) }
    func testM2_ours() throws { try caseM(native: false, name: "M2", start: "medium", mid: false, dy: -250) }
    func testM2_native() throws { try caseM(native: true, name: "M2", start: "medium", mid: false, dy: -250) }
    func testM3_ours() throws { try caseM(native: false, name: "M3", start: "large", mid: true, dy: 150) }
    func testM3_native() throws { try caseM(native: true, name: "M3", start: "large", mid: true, dy: 150) }

    // MARK: control: a drag that starts on the sheet's own header (outside the scroller)

    private func caseH1(native: Bool, start: String, dy: CGFloat, name: String) throws {
        let app = try launch(native: native, start: start)
        resetProbe(app)
        drag(app, dy: dy, fromHeader: true)
        evidence(app, "case=\(name) variant=\(native ? "native" : "ours") \(start) fromHeader dy=\(Int(dy))")
    }
    func testH1_ours() throws { try caseH1(native: false, start: "medium", dy: 250, name: "H1") }
    func testH1_native() throws { try caseH1(native: true, start: "medium", dy: 250, name: "H1") }

    // MARK: what the app can do today in pure SwiftUI (ours only): -ZTronSheetYield

    /// Our view off while the sheet sits at medium: does an upward drag on the content expand the sheet, and does the
    /// content scroll once the sheet is large?
    private func caseV1(yield: String, name: String) throws {
        let app = try launch(native: false, start: "medium", yield: yield)
        resetProbe(app)
        drag(app, dy: -250)
        evidence(app, "case=\(name)a variant=ours medium offset0 upSlow250 yield=\(yield)")
        resetProbe(app)
        drag(app, dy: -250)
        evidence(app, "case=\(name)b variant=ours (large now?) upSlow250 yield=\(yield)")
        resetProbe(app)
        drag(app, dy: 250)
        evidence(app, "case=\(name)c variant=ours (scrolled) downSlow250 yield=\(yield)")
    }
    func testV1_scrollDisabled() throws { try caseV1(yield: "scrollDisabled", name: "V1") }
    func testV2_hitTest() throws { try caseV1(yield: "hitTest", name: "V2") }
    func testV6_ztronScrollDisabled() throws { try caseV1(yield: "ztronScrollDisabled", name: "V6") }

    /// Statically disabled (the effect of `scrollDisabled` alone, whatever the detent): does the sheet get the drag?
    private func caseV7(yield: String, name: String) throws {
        let app = try launch(native: false, start: "medium", yield: yield)
        resetProbe(app)
        drag(app, dy: -250)
        evidence(app, "case=\(name)a variant=ours medium offset0 upSlow250 yield=\(yield)")
        resetProbe(app)
        drag(app, dy: 250)
        evidence(app, "case=\(name)b variant=ours (then) downSlow250 yield=\(yield)")
    }
    func testV7_scrollDisabledAlways() throws { try caseV7(yield: "scrollDisabledAlways", name: "V7") }
    func testV8_ztronScrollDisabledAlways() throws { try caseV7(yield: "ztronScrollDisabledAlways", name: "V8") }

    /// Pull release: an overscroll > 60 pt at the lift hands the sheet to a detent change / dismissal.
    private func caseV3(start: String, noDismiss: Bool, name: String) throws {
        let app = try launch(native: false, start: start, noDismiss: noDismiss, yield: "pullRelease")
        resetProbe(app)
        drag(app, dy: 250)
        evidence(app, "case=\(name) variant=ours \(start) offset0 downSlow250 yield=pullRelease noDismiss=\(noDismiss)", wait: 2.5)
    }
    func testV3_pullReleaseMedium() throws { try caseV3(start: "medium", noDismiss: false, name: "V3") }
    func testV4_pullReleaseLarge() throws { try caseV3(start: "large", noDismiss: false, name: "V4") }
    func testV5_pullReleaseNoDismiss() throws { try caseV3(start: "medium", noDismiss: true, name: "V5") }

    // MARK: ztronScrollYieldsToSheet (SHEET-s2): `-ZTronSheetYield api` = `.ztronScrollYieldsToSheet(detent != .large)`

    /// An integer field of a readout (`nil` for "-" or a missing key).
    private func num(_ info: [String: String], _ key: String) -> Int? { info[key].flatMap { Int($0) } }

    /// Window-y of the sheet's top at the large detent per OS (27.0: 62, 17.5: 69); the medium detent is below 350.
    private let largeTopCeiling = 120, mediumTopFloor = 350

    /// Y1: at medium an upward drag on the content expands the sheet (the content does not move); once the sheet is large the
    /// flag is false again and the same drag scrolls the content with the sheet fixed. No content body ran for any of it.
    func testY1_mediumUpwardDragExpandsThenTheContentScrolls() throws {
        let app = try launch(native: false, start: "medium", yield: "api")
        resetProbe(app)
        drag(app, dy: -250)
        let a = evidence(app, "case=Y1a variant=ours medium offset0 upSlow250 yield=api")
        XCTAssertFalse(a.dismissed)
        XCTAssertEqual(a.info["det"], "large", "the detent selection followed the sheet")
        XCTAssertLessThan(num(a.info, "top") ?? 999, largeTopCeiling, "the sheet expanded")
        XCTAssertGreaterThan(num(a.info, "topMin") ?? 0, 0)
        XCTAssertGreaterThan(num(a.info, "topMax") ?? 0, mediumTopFloor, "it started at medium")
        XCTAssertEqual(num(a.info, "offMax"), 0, "the content did not scroll")
        XCTAssertEqual(num(a.info, "both"), 0, "no double movement")
        XCTAssertEqual(num(a.info, "c.content.body"), 0, "the flip re-evaluated no content body")
        XCTAssertEqual(num(a.info, "trk"), 0, "the view never tracked a finger")
        resetProbe(app)
        drag(app, dy: -250)
        let b = evidence(app, "case=Y1b variant=ours large upSlow250 yield=api")
        XCTAssertFalse(b.dismissed)
        XCTAssertEqual(num(b.info, "topMin"), num(b.info, "topMax"), "the sheet stayed where it was")
        XCTAssertGreaterThan(num(b.info, "offMax") ?? 0, 150, "now the content scrolls")
        XCTAssertGreaterThan(num(b.info, "dragBegan") ?? 0, 0)
        XCTAssertEqual(num(b.info, "c.content.body"), 0)
    }

    /// Y2: at the large detent the view scrolls and rubber-bands as ever; a drag that starts at the top does NOT move the
    /// sheet (the documented limitation, SPEC S12) and does not dismiss it.
    func testY2_atLargeTheContentScrollsAndATopDragNeverMovesTheSheet() throws {
        let app = try launch(native: false, start: "large", yield: "api")
        resetProbe(app)
        drag(app, dy: -250)
        let a = evidence(app, "case=Y2a variant=ours large offset0 upSlow250 yield=api")
        XCTAssertEqual(num(a.info, "topMin"), num(a.info, "topMax"))
        XCTAssertGreaterThan(num(a.info, "offMax") ?? 0, 150)
        resetProbe(app)
        drag(app, dy: 700)
        let b = evidence(app, "case=Y2b variant=ours large downSlow700 (to the top and past it) yield=api")
        XCTAssertEqual(num(b.info, "topMin"), num(b.info, "topMax"), "the sheet did not take over mid-gesture")
        resetProbe(app)
        drag(app, dy: 250)
        let c = evidence(app, "case=Y2c variant=ours large offsetTop downSlow250 yield=api")
        XCTAssertFalse(c.dismissed, "a content drag cannot dismiss")
        XCTAssertEqual(num(c.info, "topMin"), num(c.info, "topMax"), "documented limitation: no live top-edge hand-off")
        XCTAssertLessThan(num(c.info, "offMin") ?? 0, -20, "the content rubber-bands instead")
        XCTAssertEqual(c.info["det"], "large")
        XCTAssertEqual(num(c.info, "both"), 0)
    }

    /// Y3: the pull-release recipe (V3-V5) keeps working next to the API: at large the lift past -60 pt hands the sheet to
    /// medium; at medium (yielding) the drag belongs to the sheet, which `interactiveDismissDisabled` keeps up.
    func testY3_theRecipeAtLargeStillCollapsesTheSheet() throws {
        let app = try launch(native: false, start: "large", yield: "api,pullRelease")
        resetProbe(app)
        drag(app, dy: 250)
        let e = evidence(app, "case=Y3 variant=ours large offset0 downSlow250 yield=api,pullRelease", wait: 2.5)
        XCTAssertFalse(e.dismissed)
        XCTAssertEqual(num(e.info, "pull"), 1, "the delegate saw the pull release")
        XCTAssertEqual(e.info["det"], "medium", "large -> medium after the lift")
        XCTAssertGreaterThan(num(e.info, "top") ?? 0, mediumTopFloor)
    }

    func testY3b_atMediumWithNoDismissTheSheetGetsTheDragAndStaysUp() throws {
        let app = try launch(native: false, start: "medium", noDismiss: true, yield: "api,pullRelease")
        resetProbe(app)
        drag(app, dy: 300)
        let e = evidence(app, "case=Y3b variant=ours medium offset0 downSlow300 noDismiss yield=api,pullRelease", wait: 2.5)
        XCTAssertFalse(e.dismissed)
        XCTAssertEqual(num(e.info, "pull"), 0, "the content never pulled, so the recipe never fired")
        XCTAssertGreaterThanOrEqual(num(e.info, "offMin") ?? -999, 0, "the content did not rubber-band")
        XCTAssertGreaterThan((num(e.info, "topMax") ?? 0) - (num(e.info, "topMin") ?? 0), 30, "the sheet followed the finger")
        XCTAssertEqual(e.info["det"], "medium")
    }

    /// Y4: the view with the API behaves like SwiftUI's own ScrollView in a sheet: C1 (medium, up: the sheet expands first,
    /// native default = `.resizes`) and C2 (`.scrolls`: the content scrolls, the sheet stays) — ours without the API.
    func testY4_equivalentToNativeC1AndC2() throws {
        func run(native: Bool, interaction: String, yield: String) throws -> [String: String] {
            let app = try launch(native: native, start: "medium", interaction: interaction, yield: yield)
            resetProbe(app)
            drag(app, dy: -250)
            let e = evidence(app, "case=Y4 variant=\(native ? "native" : "ours") medium offset0 upSlow250 interaction=\(interaction) yield=\(yield)")
            app.terminate()
            return e.info
        }
        let nativeC1 = try run(native: true, interaction: "default", yield: "none")
        let oursC1 = try run(native: false, interaction: "default", yield: "api")
        XCTAssertEqual(Double(num(oursC1, "top") ?? -999), Double(num(nativeC1, "top") ?? 999), accuracy: 3, "C1: the sheet ends at the same top")
        XCTAssertLessThan(num(oursC1, "top") ?? 999, largeTopCeiling)
        XCTAssertEqual(num(oursC1, "offMax"), num(nativeC1, "offMax") ?? 0, "C1: the content stays where it was (0)")
        let nativeC2 = try run(native: true, interaction: "scrolls", yield: "none")
        let oursC2 = try run(native: false, interaction: "scrolls", yield: "none")
        XCTAssertEqual(num(oursC2, "topMin"), num(oursC2, "topMax"), "C2: the sheet stays")
        XCTAssertEqual(num(nativeC2, "topMin"), num(nativeC2, "topMax"))
        XCTAssertEqual(Double(num(oursC2, "top") ?? -999), Double(num(nativeC2, "top") ?? 999), accuracy: 3)
        XCTAssertEqual(Double(num(oursC2, "offMax") ?? -999), Double(num(nativeC2, "offMax") ?? 999), accuracy: 25, "C2: the content scrolls alike")
        XCTAssertGreaterThan(num(oursC2, "offMax") ?? 0, 150)
    }

    /// Y5: Buttons in the content stay tappable while the gestures are masked (medium) and unmasked (large).
    func testY5_aButtonInTheContentWorksWhileYielding() throws {
        let app = try launch(native: false, start: "medium", yield: "api")
        resetProbe(app)
        tapButton(app, "sheet.contentButton")
        let a = evidence(app, "case=Y5a variant=ours medium (yielding) tap content button yield=api")
        XCTAssertFalse(a.dismissed)
        XCTAssertEqual(num(a.info, "c.button.fired"), 1, "the Button fired while the gestures were masked")
        XCTAssertEqual(num(a.info, "topMin"), num(a.info, "topMax"), "a tap does not move the sheet")
        XCTAssertEqual(a.info["det"], "medium")
        XCTAssertEqual(num(a.info, "c.content.body"), 0)
        drag(app, dy: -250)                                   // expands: the flag turns false
        resetProbe(app)
        tapButton(app, "sheet.contentButton")
        let b = evidence(app, "case=Y5b variant=ours large (not yielding) tap content button yield=api")
        XCTAssertEqual(num(b.info, "c.button.fired"), 1, "and the same Button fires with the gestures attached")
        XCTAssertEqual(b.info["det"], "large")
    }

    /// Y6: the flag turns true while the content decelerates (a header drag takes the sheet to medium during a fling): the
    /// motion settles by itself, nothing stays tracking, and the next upward drag at medium expands the sheet again.
    func testY6_flippingWhileTheContentMoves() throws {
        let app = try launch(native: false, start: "large", yield: "api")
        resetProbe(app)
        drag(app, dy: -300, flick: true)                      // a fling: the content decelerates for a while
        drag(app, dy: 250, fromHeader: true)                  // the sheet goes to medium meanwhile (the flag turns true)
        Thread.sleep(forTimeInterval: 3)
        resetProbe(app)
        Thread.sleep(forTimeInterval: 1)
        let rest = evidence(app, "case=Y6a variant=ours (after the fling and the collapse) yield=api")
        XCTAssertFalse(rest.dismissed)
        XCTAssertEqual(rest.info["det"], "medium")
        XCTAssertEqual(num(rest.info, "trk"), 0, "nothing stayed tracking")
        XCTAssertEqual(num(rest.info, "offMin"), num(rest.info, "offMax"), "the content is at rest")
        XCTAssertEqual(num(rest.info, "c.content.body"), 0)
        resetProbe(app)
        drag(app, dy: -250)
        let up = evidence(app, "case=Y6b variant=ours medium upSlow250 yield=api")
        XCTAssertLessThan(num(up.info, "top") ?? 999, largeTopCeiling, "the inert view still lets the sheet expand")
        XCTAssertEqual(num(up.info, "c.content.body"), 0)
    }

    // MARK: control: no scroll view, a plain SwiftUI DragGesture (or none) in the scroller's place

    private func caseP(plain: String, name: String, introspect: Bool = false, dy: CGFloat = 250, then: CGFloat? = nil) throws {
        let app = try launch(native: false, start: "medium", introspect: introspect, plain: plain)
        Thread.sleep(forTimeInterval: 1)
        resetProbe(app)
        drag(app, dy: dy)
        evidence(app, "case=\(name)a variant=plain-\(plain) medium drag\(Int(dy))")
        if let then {
            resetProbe(app)
            drag(app, dy: then)
            evidence(app, "case=\(name)b variant=plain-\(plain) (then) drag\(Int(then))")
        }
    }
    func testP1_plainSimultaneous() throws { try caseP(plain: "simultaneous", name: "P1") }
    func testP2_plainSimultaneous0() throws { try caseP(plain: "simultaneous0", name: "P2") }
    func testP3_plainGesture() throws { try caseP(plain: "gesture", name: "P3") }
    func testP4_plainHighPriority() throws { try caseP(plain: "highPriority", name: "P4") }
    func testP5_plainNone() throws { try caseP(plain: "none", name: "P5") }
    func testP9_plainSpatial() throws { try caseP(plain: "spatial", name: "P9") }
    func testP10_plainMagnify() throws { try caseP(plain: "magnify", name: "P10") }
    func testP11_plainDoubleTap() throws { try caseP(plain: "doubleTap", name: "P11") }
    func testP12_plainAllMaskedAtMedium() throws { try caseP(plain: "allMaskedAtMedium", name: "P12", dy: -250, then: 250) }
    func testP7_plainMaskedSubviews() throws { try caseP(plain: "maskedSubviews", name: "P7", dy: -250) }
    func testP8_plainMaskedAtMedium() throws { try caseP(plain: "maskedAtMedium", name: "P8", dy: -250, then: 250) }
    func testP6_plainSimultaneousIntrospect() throws { try caseP(plain: "simultaneous", name: "P6", introspect: true) }

    // MARK: DBG-s7: who decides whether the sheet gets the drag

    /// Whether a drag that starts on the content moves the sheet is SwiftUI's decision, not the library's: ours does what a plain pane with
    /// one `.simultaneousGesture(DragGesture)` does. On 17.5, 26.5 and 27.0 both freeze the sheet (SHEET-s1 P1); on 18.x (18.0 to 18.6 measured)
    /// SwiftUI shares the drag with the sheet's pan and both move it (docs/progress/DBG-s7.md). `.gesture` (exclusive) is the control that
    /// freezes the sheet on every OS measured: printed, not asserted, since the library does not attach that way.
    func testTheSheetTreatsOursLikeAPlainSimultaneousDrag() throws {
        var moved: [String: Bool] = [:]
        for (name, plain) in [("ours", nil), ("plain-simultaneous", "simultaneous"), ("plain-gesture", "gesture")] as [(String, String?)] {
            let app = try launch(native: false, start: "medium", plain: plain)
            resetProbe(app)
            drag(app, dy: 250)
            let e = evidence(app, "case=S1 variant=\(name) medium downSlow250")
            let travel = (Int(e.info["topMax"] ?? "") ?? 0) - (Int(e.info["topMin"] ?? "") ?? 0)
            moved[name] = e.dismissed || travel > 40
            app.terminate()
        }
        print("SHEET os=\(osTag) path=\(uikit ? "uikit" : forced ? "forced" : "preferred") case=S1 sheetMoved \(moved.sorted { $0.key < $1.key })")
        XCTAssertEqual(moved["ours"], moved["plain-simultaneous"], "the sheet treats our pan like a plain simultaneous drag")
    }
}
