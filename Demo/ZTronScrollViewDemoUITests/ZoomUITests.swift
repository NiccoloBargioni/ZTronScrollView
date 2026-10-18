import XCTest

final class ZoomUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private var centroidMode: String? { ProcessInfo.processInfo.environment["ZS_PINCH_CENTROID"] }

    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "zoom"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (centroidMode.map { ["-ZTronPinchCentroid", $0] } ?? []) + extra
        app.launch()
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    struct Info { var c: [String: Int]; var z: Double; var ux: Double; var uy: Double; var raw: String }

    private func info(_ app: XCUIApplication) -> Info {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        var c: [String: Int] = [:]
        for k in ["content.body", "zoom.didZoom", "zoom.didScroll", "zoom.bounce", "reader.zoomOnly", "button.fired"] {
            c[k] = Int(app.staticTexts["counter.\(k)"].value as? String ?? "") ?? -2
        }
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        func f(_ n: String) -> Double {
            s.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.flatMap { Double($0.dropFirst(n.count + 1)) } ?? -9999
        }
        print("ZOOM \(forced ? "forced" : "preferred") \(s) \(c.sorted { $0.key < $1.key })")
        return Info(c: c, z: f("z"), ux: f("ux"), uy: f("uy"), raw: s)
    }

    private func scroller(_ app: XCUIApplication) -> XCUIElement { app.otherElements["scroller"] }

    func testPinchInKeepsCenterCell() {
        let app = launch()
        scroller(app).pinch(withScale: 2, velocity: 1)
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app)
        XCTAssertGreaterThan(i.z, 1.2, "zoomed in")
        XCTAssertLessThan(i.z, 8.0001)
        XCTAssertEqual(i.c["content.body"], 0)
        // Focal error in viewport points: the content point under the pinch center (150, 180) must stay.
        let err = hypot(i.ux - 150, i.uy - 180) * i.z
        print("ZOOMERR \(forced ? "forced" : "preferred") centroid=\(centroidMode ?? "default") viewportPt=\(err)")
        XCTAssertLessThan(err, 30)
        XCTAssertGreaterThan(i.c["zoom.didZoom"]!, 3)
    }

    func testPinchOutBouncesToMin() {
        let app = launch()
        scroller(app).pinch(withScale: 2, velocity: 1)
        Thread.sleep(forTimeInterval: 1.0)
        scroller(app).pinch(withScale: 0.2, velocity: -1)
        Thread.sleep(forTimeInterval: 2.0)
        let i = info(app)
        XCTAssertEqual(i.z, 1.0, accuracy: 0.0005, "bounced back to the minimum")
        XCTAssertEqual(i.c["content.body"], 0)
        XCTAssertGreaterThanOrEqual(i.c["zoom.bounce"]!, 1)
        XCTAssertTrue(i.raw.contains("didEndZooming(1.000)"), i.raw)
    }

    func testPinchPastMaxBouncesToMax() {
        let app = launch(["-ZTronZoomMax", "2"])
        scroller(app).pinch(withScale: 4, velocity: 2)
        Thread.sleep(forTimeInterval: 2.0)
        let i = info(app)
        XCTAssertEqual(i.z, 2.0, accuracy: 0.0005)
        XCTAssertEqual(i.c["zoom.bounce"], 1)
        XCTAssertEqual(i.c["content.body"], 0)
        XCTAssertTrue(i.raw.hasSuffix("didEndZooming(2.000)"), i.raw)
        XCTAssertTrue(i.raw.contains("zooming=0 bouncing=0"), i.raw)
    }

    func testPanAfterZoomLeavesZoomReaderSilent() {
        let app = launch()
        scroller(app).pinch(withScale: 2, velocity: 1)
        Thread.sleep(forTimeInterval: 1.0)
        let before = info(app)
        let a = scroller(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let b = scroller(app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        let after = info(app)
        XCTAssertEqual(after.c["reader.zoomOnly"], before.c["reader.zoomOnly"], "zoom-only reader silent during pan")
        XCTAssertGreaterThan(after.c["zoom.didScroll"]!, before.c["zoom.didScroll"]!)
        XCTAssertEqual(after.c["zoom.didZoom"], before.c["zoom.didZoom"])
        XCTAssertEqual(after.c["content.body"], 0)
        XCTAssertEqual(after.z, before.z, accuracy: 0.0001)
    }

    func testButtonStillFires() {
        let app = launch()
        app.buttons["cell.button"].tap()
        let i = info(app)
        XCTAssertEqual(i.c["button.fired"], 1)
    }

    func testDoubleTapZoomsToMaxAndBack() {
        let app = launch(["-ZTronDoubleTap"])
        scroller(app).doubleTap()
        Thread.sleep(forTimeInterval: 1.5)
        let i = info(app)
        XCTAssertEqual(i.z, 8.0, accuracy: 0.001)
        scroller(app).doubleTap()
        Thread.sleep(forTimeInterval: 1.5)
        let j = info(app)
        XCTAssertEqual(j.z, 1.0, accuracy: 0.001)
        XCTAssertEqual(j.c["content.body"], 0)
    }
}
