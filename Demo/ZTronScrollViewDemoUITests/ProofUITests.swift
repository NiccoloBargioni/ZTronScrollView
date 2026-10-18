import XCTest

final class ProofUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronProof"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        return app
    }

    private func reset(_ app: XCUIApplication) {
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func snapshot(_ app: XCUIApplication) -> [String: Int] {
        app.buttons["Snapshot"].tap()
        var out: [String: Int] = [:]
        for key in ["content.body", "transformHost.body", "transform.effect", "clock.tick", "didScroll",
                    "reader.zoom", "reader.offset"] {
            let v = app.staticTexts["counter.\(key)"].value as? String ?? "?"
            out[key] = Int(v) ?? -2
        }
        print("COUNTERS \(forced ? "forced" : "preferred") \(out.sorted { $0.key < $1.key })")
        return out
    }

    func testRequestedPathIsActive() {
        let app = launch()
        let v = app.staticTexts["path"].value as? String
        XCTAssertEqual(v, forced ? "forcedFallback" : "preferred")
    }

    func testAnimatedProgrammaticScroll() {
        let app = launch(); reset(app)
        app.buttons["AnimatedScroll"].tap()
        Thread.sleep(forTimeInterval: 2.5)
        let c = snapshot(app)
        XCTAssertEqual(c["content.body"], 0)
        XCTAssertGreaterThanOrEqual(c["clock.tick"]!, 20)
        let ticks = Double(c["clock.tick"]!)
        XCTAssertEqual(Double(c["transformHost.body"]!), ticks, accuracy: ticks * 0.1 + 3, "transform wakes every frame")
        XCTAssertEqual(c["didScroll"], c["clock.tick"])
    }

    func testWithAnimationScroll() {
        let app = launch(); reset(app)
        app.buttons["WithAnimationScroll"].tap()
        Thread.sleep(forTimeInterval: 2.5)
        let c = snapshot(app)
        XCTAssertEqual(c["content.body"], 0)
        XCTAssertGreaterThanOrEqual(c["transform.effect"]!, 20)
        XCTAssertLessThanOrEqual(c["transformHost.body"]!, 4)
        XCTAssertGreaterThanOrEqual(c["clock.tick"]!, 20)
    }

    func testZoomOnlyReaderSilentDuringPan() {
        let app = launch(); reset(app)
        app.buttons["AnimatedScroll"].tap()
        Thread.sleep(forTimeInterval: 2.0)
        var c = snapshot(app)
        XCTAssertEqual(c["reader.zoom"], 0)
        XCTAssertGreaterThan(c["reader.offset"]!, 3)
        app.buttons["Zoom"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        c = snapshot(app)
        XCTAssertEqual(c["reader.zoom"], 1)
    }

    func testNoClockTicksAtRest() {
        let app = launch(); reset(app)
        Thread.sleep(forTimeInterval: 1.0)
        let c = snapshot(app)
        XCTAssertEqual(c["clock.tick"], 0)
        XCTAssertEqual(c["transform.effect"], 0)
    }

    func testContentStateSurvives() {
        let app = launch(); reset(app)
        app.buttons["content.toggle"].tap()
        XCTAssertEqual(app.buttons["content.toggle"].value as? String, "on")
        app.buttons["Zoom"].tap()
        app.buttons["AnimatedScroll"].tap()
        Thread.sleep(forTimeInterval: 2.0)
        let c = snapshot(app)
        XCTAssertEqual(c["content.body"], 1, "only the toggle's own body run")
    }
}
