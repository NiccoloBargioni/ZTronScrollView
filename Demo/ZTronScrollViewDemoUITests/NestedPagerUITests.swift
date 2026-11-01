import XCTest

/// N-b: nested arbitration in the demo (docs/design/NESTED-arbitration.md §1, §4). Outer horizontal paging ZTronScrollView,
/// page 0 = zoomer (zoom 1…4, double tap), page 1 = vertical list. The inner's policy is the launch argument
/// `-ZTronNestedPolicy`. The zoomer's content is 300 x 168.75 pt in a 300 x 220 viewport: at zoom 4 the offset ranges over
/// x 0…900, y 0…455. Diagnostics: `TEST_RUNNER_ZS_NESTED_ARGS="-ZTronNestedPlain"` appends launch arguments.
final class NestedPagerUITests: XCTestCase {
    private var forced: Bool { ProcessInfo.processInfo.environment["ZS_DEMO_FORCED"] == "1" }
    private static let maxX = 900.0

    override func setUp() { continueAfterFailure = false }

    private func launch(_ policy: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ZTronScreen", "nestedPager"] + (forced ? ["-ZTronForceAllFallbacks"] : [])
            + (policy.map { ["-ZTronNestedPolicy", $0] } ?? [])
            + (ProcessInfo.processInfo.environment["ZS_NESTED_ARGS"]?.split(separator: " ").map(String.init) ?? [])
        app.launch()
        app.buttons["Reset"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        return app
    }

    struct Info { var page: Int; var ox: Double; var z: Double; var ix: Double; var iy: Double; var ly: Double
        var bodies: Int; var raw: String }

    private func info(_ app: XCUIApplication) -> Info {
        app.buttons["Snapshot"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        let s = app.staticTexts["stateInfo"].value as? String ?? ""
        func f(_ n: String) -> Double {
            s.components(separatedBy: " ").first { $0.hasPrefix(n + "=") }.flatMap { Double($0.dropFirst(n.count + 1)) } ?? -9999
        }
        let bodies = Int(app.staticTexts["counter.content.body"].value as? String ?? "") ?? -2
        let catches = app.staticTexts["counter.pan.catch"].value as? String ?? "?"
        print("NESTED \(forced ? "forced" : "preferred") \(s) content.body=\(bodies) pan.catch=\(catches)")
        return Info(page: Int(f("page")), ox: f("ox"), z: f("z"), ix: f("ix"), iy: f("iy"), ly: f("ly"), bodies: bodies, raw: s)
    }

    private func outer(_ app: XCUIApplication) -> XCUIElement { app.otherElements["nested.outer"] }

    private func swipe(_ app: XCUIApplication, from: (CGFloat, CGFloat), to: (CGFloat, CGFloat)) {
        let o = outer(app)
        func p(_ n: (CGFloat, CGFloat)) -> XCUICoordinate { o.coordinate(withNormalizedOffset: CGVector(dx: n.0, dy: n.1)) }
        p(from).press(forDuration: 0.05, thenDragTo: p(to), withVelocity: .slow, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 1.3)
    }

    private func swipeLeft(_ app: XCUIApplication) { swipe(app, from: (0.92, 0.5), to: (0.08, 0.5)) }
    private func swipeRight(_ app: XCUIApplication) { swipe(app, from: (0.08, 0.5), to: (0.92, 0.5)) }
    private func swipeUp(_ app: XCUIApplication) { swipe(app, from: (0.5, 0.85), to: (0.5, 0.15)) }

    private func zoomIn(_ app: XCUIApplication) -> Info {
        outer(app).doubleTap()
        Thread.sleep(forTimeInterval: 1.5)
        let i = info(app)
        XCTAssertEqual(i.z, 4.0, accuracy: 0.001, "double tap zooms the inner to 4x")
        XCTAssertEqual(i.page, 0)
        return i
    }

    /// Swipes left (inner pans) until the zoomed image is at its trailing edge; the page must not move on the way.
    private func panToTrailingEdge(_ app: XCUIApplication) -> Info {
        var i = info(app)
        for _ in 0..<8 where i.ix < Self.maxX - 1 {
            swipeLeft(app)
            i = info(app)
            XCTAssertEqual(i.page, 0, "page stays while the image can still follow")
            XCTAssertEqual(i.ox, 0, accuracy: 0.5)
        }
        XCTAssertGreaterThanOrEqual(i.ix, Self.maxX - 1, "image at its trailing edge")
        return i
    }

    // MARK: any policy except .independent

    private func checkSwipeAtZoom1PagesAndBack(_ policy: String?) {
        let app = launch(policy)
        swipeLeft(app)
        var i = info(app)
        XCTAssertEqual(i.page, 1, "swipe left at zoom 1 pages")
        XCTAssertEqual(i.z, 1, accuracy: 0.001)
        XCTAssertEqual(i.ix, 0, accuracy: 0.5, "zoomer did not move")
        XCTAssertEqual(i.bodies, 0, "content bodies untouched")
        swipeRight(app)
        i = info(app)
        XCTAssertEqual(i.page, 0, "swipe right on the list pages back")
        XCTAssertEqual(i.bodies, 0)
    }

    private func checkVerticalAtZoom1DoesNotPage(_ policy: String?) {
        let app = launch(policy)
        swipeUp(app)
        let i = info(app)
        XCTAssertEqual(i.page, 0, "vertical swipe at zoom 1 pages nothing")
        XCTAssertEqual(i.ox, 0, accuracy: 0.5)
        XCTAssertEqual(i.iy, 0, accuracy: 0.5, "the 16:9 content fits: nothing to scroll")
        XCTAssertEqual(i.bodies, 0)
    }

    private func checkZoomedPansImageAndPageStays(_ policy: String?) {
        let app = launch(policy)
        let z = zoomIn(app)
        swipeLeft(app)
        let i = info(app)
        XCTAssertEqual(i.page, 0, "a horizontal swipe on the zoomed image does not page")
        XCTAssertEqual(i.ox, 0, accuracy: 0.5, "outer did not move")
        XCTAssertGreaterThan(i.ix, z.ix + 100, "the image pans")
        XCTAssertEqual(i.z, 4.0, accuracy: 0.001)
        XCTAssertEqual(i.bodies, 0)
    }

    private func checkPinchZoomsInner(_ policy: String?) {
        let app = launch(policy)
        outer(app).pinch(withScale: 2, velocity: 1)
        Thread.sleep(forTimeInterval: 1.0)
        let i = info(app)
        XCTAssertGreaterThan(i.z, 1.2, "pinch on the zoomer zooms it (the outer never takes a pinch)")
        XCTAssertEqual(i.page, 0)
        XCTAssertEqual(i.ox, 0, accuracy: 0.5)
        XCTAssertEqual(i.bodies, 0)
    }

    // MARK: .automatic (UIScrollView parity)

    func testAutomaticSwipeAtZoom1PagesAndBack() { checkSwipeAtZoom1PagesAndBack(nil) }
    func testAutomaticVerticalAtZoom1DoesNotPage() { checkVerticalAtZoom1DoesNotPage(nil) }
    func testAutomaticZoomedPansImageAndPageStays() { checkZoomedPansImageAndPageStays(nil) }
    func testAutomaticPinchZoomsInner() { checkPinchZoomsInner(nil) }

    /// Zoomed and at the image's trailing edge, the next swipe pages (contract rule 5 fails -> 6; UIScrollView).
    func testAutomaticAtTrailingEdgePages() {
        let app = launch(nil)
        _ = zoomIn(app)
        _ = panToTrailingEdge(app)
        swipeLeft(app)
        let i = info(app)
        XCTAssertEqual(i.page, 1, "swipe at the zoomed image's edge pages")
        XCTAssertEqual(i.ix, Self.maxX, accuracy: 1, "image stays at its edge")
        XCTAssertEqual(i.bodies, 0)
    }

    /// Different axes: a vertical list in the horizontal pager (rule 1 and 5).
    func testAutomaticVerticalListScrollsAndHorizontalPages() {
        let app = launch(nil)
        swipeLeft(app)
        XCTAssertEqual(info(app).page, 1)
        swipeUp(app)
        let i = info(app)
        XCTAssertEqual(i.page, 1, "vertical swipe on the list does not page")
        XCTAssertGreaterThan(i.ly, 50, "the list scrolls")
        XCTAssertEqual(i.bodies, 0)
    }

    /// Content-space registration with the outer scrolled (N-a open point): on page 1 the touch is converted to the outer's
    /// content space (x 300…600, the list's frame), not matched against the zoomed image's frame at x 0…300, which could
    /// still follow a rightward swipe. The list cannot follow a horizontal swipe, so the outer pages back.
    func testAutomaticPageBackFromListWithZoomedNeighbour() {
        let app = launch(nil)
        _ = zoomIn(app)
        _ = panToTrailingEdge(app)
        swipeLeft(app)
        XCTAssertEqual(info(app).page, 1)
        swipeRight(app)
        let i = info(app)
        XCTAssertEqual(i.page, 0, "the list's swipe belongs to the outer, not to the zoomed neighbour")
        XCTAssertEqual(i.z, 4.0, accuracy: 0.001, "the zoomed image is untouched")
        XCTAssertEqual(i.ix, Self.maxX, accuracy: 1)
        XCTAssertEqual(i.bodies, 0)
    }

    // MARK: .innerWhenZoomed (outer iff zoom == min)

    func testInnerWhenZoomedSwipeAtZoom1PagesAndBack() { checkSwipeAtZoom1PagesAndBack("innerWhenZoomed") }
    func testInnerWhenZoomedVerticalAtZoom1DoesNotPage() { checkVerticalAtZoom1DoesNotPage("innerWhenZoomed") }
    func testInnerWhenZoomedZoomedPansImageAndPageStays() { checkZoomedPansImageAndPageStays("innerWhenZoomed") }
    func testInnerWhenZoomedPinchZoomsInner() { checkPinchZoomsInner("innerWhenZoomed") }

    /// Zoomed and at the image's trailing edge, the inner still owns the swipe: it rubber-bands and the page stays.
    func testInnerWhenZoomedAtTrailingEdgeRubberBandsAndStays() {
        let app = launch("innerWhenZoomed")
        _ = zoomIn(app)
        _ = panToTrailingEdge(app)
        swipeLeft(app)
        let i = info(app)
        XCTAssertEqual(i.page, 0, "inner owns the swipe at its edge while zoomed")
        XCTAssertEqual(i.ox, 0, accuracy: 0.5)
        XCTAssertEqual(i.ix, Self.maxX, accuracy: 1, "rubber band settled back to the edge")
        XCTAssertEqual(i.bodies, 0)
        // Back at zoom 1 the outer owns the horizontal swipe again.
        outer(app).doubleTap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(info(app).z, 1.0, accuracy: 0.001)
        swipeLeft(app)
        XCTAssertEqual(info(app).page, 1, "zoom back to min: the outer pages again")
    }

    // MARK: .independent (no arbitration: today's behaviour)

    /// Observed (17.5 preferred; docs/progress/NESTED-s2.md): nobody is told to ignore the sequence, so BOTH recognize
    /// the drag; the outer's DragGesture reaches its hysteresis, starts dragging and locks its content (`.disabled`
    /// while dragging and no text input is edited, DBG-s3b), which cuts the inner's drag after a few points. Net effect: the outer pages, the zoomed image
    /// barely moves (here +3 pt of a 252 pt swipe). Before nested arbitration this was the only behaviour.
    func testIndependentZoomedSwipePagesAndImageBarelyMoves() {
        let app = launch("independent")
        let z = zoomIn(app)
        swipeLeft(app)
        let i = info(app)
        print("NESTED independent zoomed swipe: inner x \(z.ix) -> \(i.ix), outer x 0 -> \(i.ox), page \(i.page)")
        XCTAssertEqual(i.page, 1, "no arbitration: the outer takes the swipe although the image could follow")
        XCTAssertLessThan(i.ix - z.ix, 100, "the outer's drag lock cuts the inner short")
    }
}
