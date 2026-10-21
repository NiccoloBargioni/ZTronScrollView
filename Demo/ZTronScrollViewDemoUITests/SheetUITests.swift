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
        evidence(app, "case=D1a variant=\(native ? "native" : "ours") large offsetMid downSlow700 (content past the top)")
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
}
