import XCTest

/// The user's scenario: vertical ZTronScrollView around a fit image with zoomRange 1...4 (D15).
final class ImageUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "image"] + (forced ? ["-ZTronForceAllFallbacks"] : []) + extra
        app.launch()
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    private struct Info { var z: Double; var ox: Double; var oy: Double; var miny: Double; var body: Int }

    private func info(_ app: XCUIApplication) -> Info {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        func f(_ n: String) -> Double {
            s.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.flatMap { Double($0.dropFirst(n.count + 1)) } ?? -9999
        }
        let body = Int(app.staticTexts["counter.content.body"].value as? String ?? "") ?? -2
        print("IMAGE \(forced ? "forced" : "preferred") \(s) body=\(body)")
        return Info(z: f("z"), ox: f("ox"), oy: f("oy"), miny: f("miny"), body: body)
    }

    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let sc = app.otherElements["scroller"]
        let a = sc.coordinate(withNormalizedOffset: from), b = sc.coordinate(withNormalizedOffset: to)
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.0)
    }

    func testZoomedPansHorizontallyAndVertically() {
        let app = launch()
        let base = info(app).body
        app.otherElements["scroller"].pinch(withScale: 2.5, velocity: 1)
        Thread.sleep(forTimeInterval: 1.0)
        let z = info(app)
        XCTAssertGreaterThan(z.z, 1.2)
        drag(app, from: CGVector(dx: 0.8, dy: 0.5), to: CGVector(dx: 0.2, dy: 0.5))
        let h = info(app)
        XCTAssertGreaterThan(h.ox, z.ox + 40, "horizontal drag moves contentOffset.x although axes = .vertical")
        drag(app, from: CGVector(dx: 0.5, dy: 0.8), to: CGVector(dx: 0.5, dy: 0.2))
        let v = info(app)
        XCTAssertGreaterThan(v.oy, h.oy + 40, "vertical drag scrolls")
        XCTAssertEqual(v.body, base, "content body not re-evaluated")
    }

    func testVerticalScrollsWhenTallAtOneX() {
        let app = launch()
        let base = info(app).body
        drag(app, from: CGVector(dx: 0.5, dy: 0.8), to: CGVector(dx: 0.5, dy: 0.2))
        let v = info(app)
        XCTAssertGreaterThan(v.oy, 40)
        XCTAssertEqual(v.ox, 0, accuracy: 0.5, "no horizontal pan at 1x")
        XCTAssertEqual(v.body, base, "content body not re-evaluated")
    }

    func testFittingImageRubberBandsVertically() {
        let app = launch(["-ZTronImageFits"])
        let base = info(app).body
        let a = app.otherElements["scroller"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let b = app.otherElements["scroller"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.3)
        Thread.sleep(forTimeInterval: 1.5)
        let v = info(app)
        XCTAssertLessThan(v.miny, -15, "rubber-banded past the top")
        XCTAssertEqual(v.body, base, "content body not re-evaluated")
        XCTAssertEqual(v.oy, 0, accuracy: 1, "settled back")
    }

    func testStatelessSnippetZooms() {
        let app = launch(["-ZTronImageStateless"])
        app.otherElements["scroller"].pinch(withScale: 2.5, velocity: 1)
        Thread.sleep(forTimeInterval: 1.0)
        let z = Double(app.staticTexts["zoomReadout"].value as? String ?? "") ?? -1
        XCTAssertGreaterThan(z, 1.2)
    }
}
