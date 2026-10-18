import XCTest

/// M3-c: the scroller inside a SwiftUI-driven pager with a ReferenceScrollArbiter (design M3-pan §7, §10). iOS 27.0 only.
final class PagerUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "pager"]
        app.launch()
        return app
    }

    private func state(_ app: XCUIApplication) -> (page: Int, x: Int, y: Int) {
        app.buttons["Info"].tap()
        Thread.sleep(forTimeInterval: 0.3)
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        print("PAGER \(s)")
        func field(_ n: String) -> Int {
            s.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.flatMap { Int($0.dropFirst(n.count + 1)) } ?? -9999
        }
        return (field("page"), field("x"), field("y"))
    }

    private func swipe(_ app: XCUIApplication, frame: CGRect, from: (CGFloat, CGFloat), to: (CGFloat, CGFloat)) {
        func p(_ n: (CGFloat, CGFloat)) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.minX + frame.width * n.0, dy: frame.minY + frame.height * n.1))
        }
        p(from).press(forDuration: 0.05, thenDragTo: p(to), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1.2)
    }

    func testPagerArbitration() {
        let app = launch()
        let frame = app.otherElements["pager.scroller"].frame
        XCTAssertGreaterThan(frame.width, 100)

        // Vertical swipe always scrolls the scroll view.
        swipe(app, frame: frame, from: (0.5, 0.8), to: (0.5, 0.2))
        var s = state(app)
        XCTAssertEqual(s.page, 0)
        XCTAssertGreaterThan(s.y, 50, "vertical swipe scrolls the scroller")

        // A horizontal swipe the scroller can follow scrolls it and does not page.
        swipe(app, frame: frame, from: (0.8, 0.5), to: (0.3, 0.5))
        s = state(app)
        XCTAssertEqual(s.page, 0, "followable swipe does not page")
        XCTAssertGreaterThan(s.x, 50, "followable swipe scrolls the scroller")

        // A swipe toward the leading edge while at it (x == 0) is the container's (finger right at min edge).
        app.buttons["Reset"].tap(); Thread.sleep(forTimeInterval: 0.5)
        swipe(app, frame: frame, from: (0.2, 0.5), to: (0.8, 0.5))
        s = state(app)
        XCTAssertEqual(s.x, 0, "swipe at the leading edge leaves the scroller alone")
        XCTAssertEqual(s.page, 0)

        // Scroll to the trailing edge, then one more swipe the scroller cannot follow pages.
        for _ in 0..<4 {
            s = state(app)
            if s.x >= 500 { break }
            swipe(app, frame: frame, from: (0.9, 0.5), to: (0.2, 0.5))
        }
        s = state(app)
        XCTAssertEqual(s.page, 0, "page stays while the scroller can follow")
        XCTAssertGreaterThan(s.x, 400)
        swipe(app, frame: frame, from: (0.9, 0.5), to: (0.2, 0.5))
        s = state(app)
        XCTAssertEqual(s.page, 1, "swipe at the trailing edge pages")
    }
}
