import XCTest

/// One parsed `log.last` line (fixed grammar, see MC-contract section 5).
struct SeqRecord {
    let raw: String
    let fields: [String: String]
    init(_ raw: String) {
        self.raw = raw
        var f: [String: String] = [:]
        for part in raw.split(separator: " ") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { f[kv[0]] = kv[1] }
        }
        fields = f
    }
    var id: Int { Int(fields["seq"] ?? "") ?? -1 }
    var first: String { fields["first"] ?? "" }
    var owner: String { fields["owner"] ?? "" }
    var decided: Int { Int(fields["decided"] ?? "") ?? -1 }
    var panStates: [String] { (fields["pan"] ?? "").split(separator: ">").map(String.init) }
    var panBegan: Bool { panStates.contains("began") }
    var pagerMoved: Bool { fields["pagerMoved"] == "1" }
    var pages: (Int, Int) {
        let p = (fields["page"] ?? "0>0").split(separator: ">").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : (-1, -1)
    }
    var box: Bool { fields["box"] == "1" }
    var button: Int { Int(fields["button"] ?? "") ?? -1 }
    var delta: Double? { fields["delta"].flatMap(Double.init) }
    var pEnd: Bool { fields["pEnd"] == "1" }
    var foreign: Bool { fields["foreign"] == "1" }
    var fn: String { fields["fn"] ?? "" }
}

@MainActor
final class SpikeApp {
    let app = XCUIApplication()
    var maxDelta = 0.0
    var firstCounts: [String: Int] = [:]

    func launch(extra: [String] = []) {
        app.terminate()
        var args = extra
        if let mode = ProcessInfo.processInfo.environment["SPIKE_MODE"] { args += ["-gestureMode", mode] }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
    }

    var pager: XCUIElement { app.descendants(matching: .any)["pager"] }
    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func pageIndex() -> Int { Int(el("pageIndex").label) ?? -1 }
    func lastLine() -> String { el("log.last").label }
    func count() -> Int { Int(el("log.count").label) ?? 0 }

    func setSwitch(_ id: String, on: Bool) {
        let sw = app.switches[id]
        if !sw.waitForExistence(timeout: 5) { print("SPIKEDEBUG \(app.debugDescription)") }
        func isOn() -> Bool { "\(sw.value ?? "0")" == "1" }
        if isOn() == on { return }
        func waitFor() { let d = Date().addingTimeInterval(1.2); while isOn() != on && Date() < d { usleep(100_000) } }
        sw.tap()
        waitFor()
        if isOn() != on { sw.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); waitFor() }
        XCTAssertEqual(isOn(), on, "switch \(id)")
    }

    /// Press and drag; `vector` is the finger movement in points (positive dy moves down).
    func drag(from element: XCUIElement, _ vector: CGVector, hold: Double = 0.05) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(vector)
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: hold)
    }

    /// Waits for the record count to change from `before`, then lets paging settle.
    func settle(after before: Int) -> SeqRecord {
        let deadline = Date().addingTimeInterval(4)
        while count() == before && Date() < deadline { usleep(100_000) }
        usleep(900_000)
        let r = SeqRecord(lastLine())
        maxDelta = max(maxDelta, r.delta ?? 0)
        firstCounts[r.first, default: 0] += 1
        return r
    }

    func dump(_ test: XCTestCase, _ name: String) {
        var lines: [String] = []
        for n in 1...max(1, count()) { lines.append(el("log.\(n)").label) }
        let a = XCTAttachment(string: lines.joined(separator: "\n"))
        a.name = name; a.lifetime = .keepAlways
        test.add(a)
        print("SPIKE[\(name)] maxDelta=\(maxDelta) first=\(firstCounts)")
        for l in lines { print("SPIKE[\(name)] \(l)") }
    }

    /// Moves to page 1 deterministically (page 0 canFollow off, swipe on blank area).
    func goToPageOne() {
        setSwitch("page.0.canFollow", on: false)
        let before = count()
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.88))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -300, dy: 0)), withVelocity: .default, thenHoldForDuration: 0.05)
        _ = settle(after: before)
        XCTAssertEqual(pageIndex(), 1, "goToPageOne")
    }
}
