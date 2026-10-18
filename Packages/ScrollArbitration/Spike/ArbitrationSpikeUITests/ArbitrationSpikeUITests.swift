import XCTest

@MainActor
final class ArbitrationSpikeUITests: XCTestCase {
    private let s = SpikeApp()
    private var is18: Bool { if #available(iOS 18, *) { return true } else { return false } }

    override func setUp() async throws { continueAfterFailure = true }

    private let angles: [(String, CGFloat, CGFloat)] = [("0", 120, 0), ("20", 120, 43.7), ("40", 120, 100.7), ("90", 0, 120)]

    /// Finger moves leftwards (page 0) or rightwards (page 1); 90 moves up.
    private func runDrag(_ name: String, dx: CGFloat, dy: CGFloat, page: Int, canFollow: Bool) {
        s.launch()
        if page == 1 { s.goToPageOne() }
        s.setSwitch("page.\(page).canFollow", on: canFollow)
        let sign: CGFloat = page == 0 ? -1 : 1
        let vector = dx == 0 ? CGVector(dx: 0, dy: -120) : CGVector(dx: sign * dx, dy: dy)
        let before = s.count()
        s.drag(from: s.el("page.\(page).box"), vector)
        let r = s.settle(after: before)
        let tag = "\(name) page\(page) canFollow=\(canFollow)"
        let participantExpected = name == "40" || name == "90" || canFollow
        XCTAssertEqual(r.decided, 1, "\(tag) decided: \(r.raw)")
        XCTAssertEqual(r.owner, participantExpected ? "participant" : "container", "\(tag) owner: \(r.raw)")
        let (b, a) = r.pages
        if participantExpected {
            XCTAssertFalse(r.pagerMoved, "\(tag) pagerMoved: \(r.raw)")
            XCTAssertEqual(a, b, "\(tag) page: \(r.raw)")
            XCTAssertTrue(r.box, "\(tag) box: \(r.raw)")
            if is18 { XCTAssertFalse(r.panBegan, "\(tag) Q1 pan must not begin: \(r.raw)") }
        } else {
            XCTAssertTrue(r.pagerMoved, "\(tag) pagerMoved: \(r.raw)")
            XCTAssertNotEqual(a, b, "\(tag) page: \(r.raw)")
            XCTAssertFalse(r.box, "\(tag) box: \(r.raw)")
            XCTAssertTrue(r.panBegan, "\(tag) pan began: \(r.raw)")
            XCTAssertTrue(r.pEnd, "\(tag) Q3 pEnd: \(r.raw)")
        }
        if let d = r.delta { XCTAssertLessThanOrEqual(d, 0.5, "\(tag) Q4 delta: \(r.raw)") }
        s.dump(self, tag.replacingOccurrences(of: " ", with: "_"))
    }

    func testDragsPageZero() {
        for (name, dx, dy) in angles {
            for canFollow in [true, false] { runDrag(name, dx: dx, dy: dy, page: 0, canFollow: canFollow) }
        }
        print("SPIKE[summary-page0] maxDelta=\(s.maxDelta) first=\(s.firstCounts)")
    }

    func testDragsPageOne() {
        for (name, dx, dy) in angles {
            for canFollow in [true, false] { runDrag(name, dx: dx, dy: dy, page: 1, canFollow: canFollow) }
        }
        print("SPIKE[summary-page1] maxDelta=\(s.maxDelta) first=\(s.firstCounts)")
    }

    func testPinch() {
        s.launch()
        let before = s.count()
        s.el("page.0.box").pinch(withScale: 1.5, velocity: 1)
        let r = s.settle(after: before)
        XCTAssertTrue(r.decided == 0 || r.owner == "participant", "pinch: \(r.raw)")
        XCTAssertEqual(s.pageIndex(), 0)
        let v = "\(s.el("page.0.box").value ?? "")"
        XCTAssertFalse(v.hasSuffix(",1.00"), "box scaled: \(v)")
        s.dump(self, "pinch")
    }

    func testTaps() {
        s.launch()
        for i in 1...3 {
            let before = s.count()
            s.app.buttons["page.0.button"].tap()
            let r = s.settle(after: before)
            XCTAssertEqual(s.el("page.0.buttonCount").label, "\(i)")
            XCTAssertEqual(r.button, 1, "tap \(i): \(r.raw)")
            if is18 { XCTAssertFalse(r.foreign, "Q2 tap foreign: \(r.raw)") }
        }
        XCTAssertEqual(s.pageIndex(), 0)
        s.dump(self, "taps")
    }

    func testDragStartingOnButton() {
        for canFollow in [false, true] {
            s.launch()
            s.setSwitch("page.0.canFollow", on: canFollow)
            let before = s.count()
            s.drag(from: s.app.buttons["page.0.button"], CGVector(dx: -120, dy: 0))
            let r = s.settle(after: before)
            XCTAssertEqual(s.el("page.0.buttonCount").label, "0", "button count canFollow=\(canFollow): \(r.raw)")
            if canFollow {
                XCTAssertTrue(r.box, "box moved: \(r.raw)"); XCTAssertEqual(s.pageIndex(), 0)
            } else {
                XCTAssertEqual(s.pageIndex(), 1, "page changes: \(r.raw)"); XCTAssertFalse(r.box)
            }
            if is18 { XCTAssertEqual(r.button, 0, "Q2 \(r.raw)") }
            s.dump(self, "buttonDrag_canFollow=\(canFollow)")
        }
    }

    func testParticipantMovingRule3() {
        s.launch()
        s.setSwitch("page.0.moving", on: true)
        s.setSwitch("page.0.canFollow", on: false)
        let before = s.count()
        s.drag(from: s.el("page.0.box"), CGVector(dx: -120, dy: 0))
        let r = s.settle(after: before)
        XCTAssertEqual(r.owner, "participant", r.raw)
        XCTAssertEqual(r.decided, 1, r.raw)
        s.dump(self, "moving")
    }

    func testFlingThenHold() {
        s.launch()
        s.setSwitch("page.0.canFollow", on: false)
        let start = s.pager.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.88))
        start.press(forDuration: 0.02, thenDragTo: start.withOffset(CGVector(dx: -250, dy: 0)), withVelocity: .fast, thenHoldForDuration: 0)
        let hold = s.pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        hold.press(forDuration: 0.4)
        usleep(900_000)
        s.dump(self, "flingHold")
    }
}
