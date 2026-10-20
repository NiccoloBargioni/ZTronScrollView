import XCTest

/// M7 session 2 / M8-8 on the demo `EventLogScreen`: the delegate, the 13 delegate modifiers and the phase observer in one
/// sequence-numbered log, and (iOS 18+) a native ScrollView's phases next to ours.
final class ObservationUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }

    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "eventLog"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
        app.launch()
        return app
    }

    /// Entries as `(sequence, tag, name)`.
    private func entries(_ app: XCUIApplication, _ id: String) -> [(Int, String, String)] {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let text = app.staticTexts[id].value as? String ?? ""
        print("OBS \(forced ? "forced" : "preferred") \(id): \(text)")
        return text.components(separatedBy: " | ").compactMap { item in
            let parts = item.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, let n = Int(parts[0]) else { return nil }
            let kv = parts[1].split(separator: ":", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { return nil }
            return (n, kv[0], kv[1])
        }
    }

    private func swipe(_ scroller: XCUIElement) {
        let a = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let b = scroller.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .fast, thenHoldForDuration: 0)
    }

    func testDelegateModifiersAndPhasesShareOneOrder() {
        let app = launch()
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        swipe(app.descendants(matching: .any)["zscroller"])
        Thread.sleep(forTimeInterval: 4)
        let e = entries(app, "eventLog")
        XCTAssertFalse(e.isEmpty)
        XCTAssertEqual(e.map(\.0), Array(1...e.count), "one sequence, no gaps")
        let d = e.filter { $0.1 == "d" }.map(\.2), m = e.filter { $0.1 == "m" }.map(\.2)
        XCTAssertTrue(d.contains("willBeginDragging") && d.contains("willEndDragging") && d.contains("didEndDecelerating"), "\(d)")
        XCTAssertEqual(d, m, "the modifiers saw the delegate's sequence")
        // A modifier entry follows its delegate entry at once; a phase transition follows the call it belongs to.
        let flat = e.map { "\($0.1):\($0.2)" }
        func next(after item: String, skipping tag: String = "m") -> String? {
            guard let i = flat.firstIndex(of: item) else { return nil }
            return flat[(i + 1)...].first { !$0.hasPrefix(tag + ":") }
        }
        XCTAssertEqual(next(after: "d:willBeginDragging"), "p:tracking>interacting", "\(flat)")
        XCTAssertEqual(next(after: "d:willBeginDecelerating"), "p:interacting>decelerating", "\(flat)")
        XCTAssertEqual(next(after: "d:didEndDecelerating"), "p:decelerating>idle", "\(flat)")
        XCTAssertEqual(flat.filter { $0.hasPrefix("p:") },
                       ["p:idle>tracking", "p:tracking>interacting", "p:interacting>decelerating", "p:decelerating>idle"])
        XCTAssertTrue(flat.contains("g:offsetPositive=true"))
        XCTAssertTrue(flat.contains { $0.hasPrefix("v:") }, "target visibility reported")
    }

    func testScrollToTopAsksTheDelegateAndTheModifierThenReportsBoth() {
        let app = launch()
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        swipe(app.descendants(matching: .any)["zscroller"])
        Thread.sleep(forTimeInterval: 4)
        app.buttons["Top"].tap()
        Thread.sleep(forTimeInterval: 2)
        let flat = entries(app, "eventLog").map { "\($0.1):\($0.2)" }
        guard let ask = flat.lastIndex(of: "d:shouldScrollToTop") else { return XCTFail("no shouldScrollToTop: \(flat)") }
        let tail = Array(flat[ask...]).filter { $0.hasPrefix("d:") || $0.hasPrefix("m:") }
        XCTAssertEqual(tail.first, "d:shouldScrollToTop")
        XCTAssertEqual(tail.dropFirst().first, "m:shouldScrollToTop")
        XCTAssertEqual(Array(tail.suffix(4)), ["d:didEndScrollingAnimation", "m:didEndScrollingAnimation", "d:didScrollToTop", "m:didScrollToTop"], "\(tail)")
        XCTAssertEqual(flat.last, "p:animating>idle", "the phase follows the end callbacks: \(flat)")
    }

    func testNativeScrollViewPhasesMatchOurs() throws {
        if #unavailable(iOS 18) { throw XCTSkip("the native twin needs iOS 18") }
        let app = launch()
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        swipe(app.descendants(matching: .any)["zscroller"])
        swipe(app.descendants(matching: .any)["nscroller"])
        Thread.sleep(forTimeInterval: 4)
        let ours = entries(app, "eventLog").filter { $0.1 == "p" }.map(\.2)
        let native = entries(app, "nativeLog").filter { $0.1 == "n" && $0.2.contains(">") && !$0.2.hasPrefix("g:") }.map(\.2)
        // R2, measured on 27.0: for a synthesized press-and-drag native reports `idle>interacting` where ours reports the
        // touch-down `idle>tracking` and `tracking>interacting` (the instant `.tracking` is coalesced natively). Everything
        // after the drag begins is compared as it is.
        var normalized = ours
        if normalized.starts(with: ["idle>tracking", "tracking>interacting"]) {
            normalized.replaceSubrange(0..<2, with: ["idle>interacting"])
        }
        XCTAssertEqual(normalized, native, "ours \(ours) native \(native)")
    }
}
