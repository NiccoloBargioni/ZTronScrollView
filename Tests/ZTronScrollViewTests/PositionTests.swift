import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

@MainActor
final class BindingBox {
    /// Int ids are reported (SwiftUI reports only views of the position's id type).
    var position = ZTronScrollPosition(idType: Int.self)
    var sets: [ZTronScrollPosition] = []
    var binding: Binding<ZTronScrollPosition> {
        Binding(get: { self.position }, set: { self.position = $0; self.sets.append($0) })
    }
}

/// `scrollPosition` write-back and requests (M6 session 3, tests 7 and 8). Viewport 100 x 200, content 300 x 900 of nine
/// 100 pt cells (`ztronScrollID(0...8)`), so the vertical bounds are 0...700.
@MainActor
@Suite(.serialized)
struct PositionTests {
    func make(_ path: OSPath, anchor: UnitPoint? = nil, bind: Bool = true, offset: CGPoint = .zero)
        -> (ZTronScrollState, BindingBox) {
        let s = makeState(path)
        s.now = { 100 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900),
                                   displayScale: 2))
        for i in 0..<9 { s.targets.register(i, frame: CGRect(x: 0, y: CGFloat(i) * 100, width: 300, height: 100)) }
        let box = BindingBox()
        if bind { s.positionDriver.bind(PositionBinding(box.binding, anchor: anchor)) }
        s.track(offset: offset, zoom: 1)
        return (s, box)
    }

    static let env = TargetBehaviorTests.env

    func tracker(vy: CGFloat, lift: TimeInterval = 100) -> PointVelocityTracker {
        var t = PointVelocityTracker()
        for i in 0...8 {
            let time = lift - 0.12 + Double(i) * 0.015
            t.add(CGPoint(x: 0, y: -vy * CGFloat(time - (lift - 0.12))), at: time)
        }
        return t
    }

    func flingToTheNextCell(_ s: ZTronScrollState, from y: CGFloat = 300) {
        s.targetBehavior = AnyZTronScrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior(limitBehavior: .never))
        s.beginTracking(); s.beginDragging()
        s.endDrag(ReleaseRequest(origin: CGPoint(x: 0, y: y), dragStart: CGPoint(x: 0, y: y), liftTime: 100, fallbackVelocity: nil),
                  tracker: tracker(vy: 1500), env: PanSessionTests.env(), settings: ReleaseSettings())
    }

    func run(_ s: ZTronScrollState, frames: Int = 600) {
        var t = 100.0
        var n = 0
        while s.isClockRunning && n < frames {
            t += 1.0 / 60
            n += 1
            s.step(to: Date(timeIntervalSinceReferenceDate: t))
        }
    }

    // MARK: write-back (SwiftUI's, PARITY-s1: one write per view passed while the user moves the view)

    /// A finger drag to `y` from where the view is: tracking, then the drag frames, each delivered like a frame.
    func drag(_ s: ZTronScrollState, to ys: [CGFloat]) {
        s.beginTracking(); s.beginDragging()
        for y in ys { s.writeDragOffset(CGPoint(x: 0, y: y)); s.deliverPending() }
    }

    func release(_ s: ZTronScrollState, at y: CGFloat) {
        s.endDrag(ReleaseRequest(origin: CGPoint(x: 0, y: y), dragStart: CGPoint(x: 0, y: y), liftTime: 100, fallbackVelocity: nil),
                  tracker: tracker(vy: 0), env: PanSessionTests.env(), settings: ReleaseSettings())
    }

    @Test(arguments: OSPath.allCases) func aUserScrollWritesEachViewItPassesEndingOnTheLandedOne(path: OSPath) {
        let (s, box) = make(path, offset: CGPoint(x: 0, y: 300))
        drag(s, to: [310, 330])
        #expect(box.sets.map { $0.viewID(type: Int.self) } == [3])                // the view it is at, once, on the first move
        flingToTheNextCell(s, from: 330)
        run(s)
        let ids = box.sets.compactMap { $0.viewID(type: Int.self) }
        let landed = Int((s.peek.presentationOffset.y / 100).rounded())
        #expect(ids.last == landed && ids.count >= 2, "ids \(ids)")
        #expect(ids == Array(ids.first!...ids.last!), "one write per view passed: \(ids)")
        #expect(box.sets.allSatisfy(\.isPositionedByUser) && s.positionDriver.writes == box.sets.count)
    }

    /// The reported view is the one whose anchor point is nearest the visible area's (SwiftUI 26.5 / 27.0 sweep: at offset
    /// 34 over 44 pt rows SwiftUI reports row 1, not row 0 under the top edge): here 100 pt cells, top anchor.
    @Test(arguments: OSPath.allCases) func theReportedViewIsTheNearestAnchorNotTheOneUnderIt(path: OSPath) {
        let (s, box) = make(path, offset: CGPoint(x: 0, y: 300))
        drag(s, to: [334])
        #expect(box.position.viewID(type: Int.self) == 3)                          // tops 300 (34 away) and 400 (66)
        drag(s, to: [360])
        #expect(box.position.viewID(type: Int.self) == 4)                          // 300 is 60 away, 400 only 40
    }

    @Test(arguments: OSPath.allCases) func writeBackIsNeverAppliedAgain(path: OSPath) {
        let (s, box) = make(path, offset: CGPoint(x: 0, y: 300))
        flingToTheNextCell(s)
        run(s)
        let applied = s.positionDriver.applied
        s.positionDriver.receive(box.position)                      // SwiftUI reading its own write back
        #expect(s.positionDriver.applied == applied)
    }

    @Test(arguments: OSPath.allCases) func programmaticRequestsNeverWriteBack(path: OSPath) {
        let (s, box) = make(path)
        s.positionDriver.receive(ZTronScrollPosition(id: 5))
        #expect(s.peek.presentationOffset.y == 400)                 // unanimated minimal scroll: cell 5's bottom (600) meets the viewport bottom
        run(s)
        s.positionDriver.receive(ZTronScrollPosition(edge: .bottom))
        run(s)
        s.setContentOffset(CGPoint(x: 0, y: 250), animated: true)  // an animated command passes views too
        run(s)
        #expect(s.positionDriver.writes == 0 && box.sets.isEmpty)
    }

    /// The binding was reset to something else after a write-back (the demo's Reset button): landing on the same view again
    /// must write again, and asking for the view the user left must scroll again.
    @Test(arguments: OSPath.allCases) func aWriteBackIsNotSkippedAfterTheBindingChangedAndAnEarlierRequestReapplies(path: OSPath) {
        let (s, box) = make(path, offset: CGPoint(x: 0, y: 300))
        flingToTheNextCell(s)
        run(s)
        let landed = box.position.viewID(type: Int.self) ?? -1
        let writes = s.positionDriver.writes
        box.position = ZTronScrollPosition(idType: Int.self, edge: .top)            // the app moves the binding
        s.positionDriver.receive(box.position)
        #expect(s.peek.presentationOffset.y == 0)
        s.track(offset: CGPoint(x: 0, y: 300), zoom: 1)
        flingToTheNextCell(s)
        run(s)
        #expect(s.positionDriver.writes > writes)
        #expect(box.position.viewID(type: Int.self) == landed && box.position.isPositionedByUser)
        // And the request the app made before the user scrolled is a new request when made again.
        let applied = s.positionDriver.applied
        box.position = ZTronScrollPosition(edge: .top)
        s.positionDriver.receive(box.position)
        #expect(s.positionDriver.applied == applied + 1)
    }

    @Test(arguments: OSPath.allCases) func theModifiersAnchorPicksTheReportedView(path: OSPath) {
        // At 300 the viewport shows cells 3 and 4; a tie (the center, 400, is 50 from both centers) goes to the later view.
        for (anchor, expected) in [(UnitPoint.topLeading, 3), (UnitPoint.center, 4), (UnitPoint.bottom, 4)] {
            let (s, box) = make(path, anchor: anchor, offset: CGPoint(x: 0, y: 290))
            drag(s, to: [300])
            release(s, at: 300)
            #expect(box.position.viewID(type: Int.self) == expected, "anchor \(anchor)")
        }
    }

    /// SwiftUI writes no view for a position whose id type no view has (`ScrollPosition()` is `idType: Never`) and never a
    /// point: once per gesture, only that the user moved it.
    @Test(arguments: OSPath.allCases) func withoutViewsOfItsIDTypeAUserScrollWritesOnlyThatTheUserMovedIt(path: OSPath) {
        for position in [ZTronScrollPosition(), ZTronScrollPosition(idType: String.self)] {
            let (s, box) = make(path, offset: CGPoint(x: 0, y: 300))
            box.position = position
            drag(s, to: [320, 360, 420])
            #expect(box.sets.count == 1)
            #expect(box.position.viewID == nil && box.position.point == nil && box.position.isPositionedByUser)
        }
    }

    // MARK: requests

    @Test(arguments: OSPath.allCases) func edgesPointsAndAxesMove(path: OSPath) {
        let (s, _) = make(path, offset: CGPoint(x: 50, y: 100))
        let d = s.positionDriver
        d.receive(ZTronScrollPosition(edge: .bottom))
        #expect(s.peek.presentationOffset == CGPoint(x: 50, y: 700))                // bottom: y = max, x unchanged
        d.receive(ZTronScrollPosition(edge: .trailing))
        #expect(s.peek.presentationOffset == CGPoint(x: 200, y: 700))
        d.receive(ZTronScrollPosition(edge: .top))
        d.receive(ZTronScrollPosition(edge: .leading))
        #expect(s.peek.presentationOffset == .zero)
        d.receive(ZTronScrollPosition(x: 120))
        #expect(s.peek.presentationOffset == CGPoint(x: 120, y: 0))                 // one axis
        d.receive(ZTronScrollPosition(y: 9999))
        #expect(s.peek.presentationOffset == CGPoint(x: 120, y: 700))               // clamped
        d.receive(ZTronScrollPosition(point: CGPoint(x: 30, y: 40)))
        #expect(s.peek.presentationOffset == CGPoint(x: 30, y: 40))
        d.receive(ZTronScrollPosition(x: 5, y: 6))
        #expect(s.peek.presentationOffset == CGPoint(x: 5, y: 6))
    }

    /// PARITY-s1: SwiftUI's points are in content space, so under a leading inset the point lands at the top-leading corner of
    /// the unobscured area (offset = point − inset); clamping uses the inset bounds (native, 18.6 / 26.5 / 27.0: under a 50 pt
    /// top inset `scrollTo(point: (0, 300))` is offset 250, `scrollTo(y: 500)` is 450, `(0, -100)` rests at the top, -50).
    @Test(arguments: OSPath.allCases) func pointsAreInContentSpaceLikeSwiftUIs(path: OSPath) {
        let (s, _) = make(path)
        s.contentInsetAdjustmentBehavior = .never
        s.contentInset = EdgeInsets(top: 50, leading: 20, bottom: 0, trailing: 0)
        let d = s.positionDriver
        d.receive(ZTronScrollPosition(point: CGPoint(x: 0, y: 300)))
        #expect(s.peek.presentationOffset == CGPoint(x: -20, y: 250))
        d.receive(ZTronScrollPosition(y: 500))
        #expect(s.peek.presentationOffset == CGPoint(x: -20, y: 450))              // one axis: x stays
        d.receive(ZTronScrollPosition(x: 120))
        #expect(s.peek.presentationOffset == CGPoint(x: 100, y: 450))
        d.receive(ZTronScrollPosition(point: CGPoint(x: 0, y: -100)))
        #expect(s.peek.presentationOffset == CGPoint(x: -20, y: -50))              // clamped to the resting top-leading corner
        d.receive(ZTronScrollPosition(x: 30, y: 9999))
        #expect(s.peek.presentationOffset == CGPoint(x: 10, y: 700))               // max = 900 + 0 − 200
    }

    @Test func oneAxisRequestsReadBackLikeSwiftUIs() {
        #expect(ZTronScrollPosition(x: 4).x == 4 && ZTronScrollPosition(x: 4).y == nil && ZTronScrollPosition(x: 4).point == nil)
        #expect(ZTronScrollPosition(y: 5).y == 5 && ZTronScrollPosition(y: 5).x == nil)
        let xy = ZTronScrollPosition(x: 4, y: 5)
        #expect(xy.x == nil && xy.y == nil && xy.point == CGPoint(x: 4, y: 5))     // SwiftUI 18.6 / 26.5 / 27.0: a point, no x / y
        #expect(ZTronScrollPosition(point: CGPoint(x: 1, y: 2)).x == nil)
    }

    @Test(arguments: OSPath.allCases) func viewRequestsUseTheAnchorOfTheModifierUnlessTheRequestHasOne(path: OSPath) {
        let (s, _) = make(path, anchor: .bottom)
        s.positionDriver.receive(ZTronScrollPosition(id: 4))
        #expect(s.peek.presentationOffset.y == 300)                                 // bottom of cell 4 (500) on the viewport bottom
        s.positionDriver.receive(ZTronScrollPosition(id: 6, anchor: .top))
        #expect(s.peek.presentationOffset.y == 600)
    }

    @Test(arguments: OSPath.allCases) func aRepeatedRequestReappliesAndTheSameValueDoesNot(path: OSPath) {
        let (s, _) = make(path)
        let d = s.positionDriver
        let p = ZTronScrollPosition(edge: .bottom)
        d.receive(p)
        #expect(d.applied == 1)
        d.receive(p)                                                                // the same value read again
        #expect(d.applied == 1)
        s.track(offset: CGPoint(x: 0, y: 100), zoom: 1)
        var q = p
        q.scrollTo(edge: .bottom)                                                   // asking again
        d.receive(q)
        #expect(d.applied == 2 && s.peek.presentationOffset.y == 700)
    }

    @Test(arguments: OSPath.allCases) func aRequestBeforeTheFirstLayoutIsHeldAndAppliedOnce(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        let box = BindingBox()
        s.positionDriver.bind(PositionBinding(box.binding, anchor: nil))
        s.positionDriver.receive(ZTronScrollPosition(id: 5))
        #expect(s.positionDriver.hasPending && s.positionDriver.applied == 0)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900),
                                   displayScale: 2))
        #expect(s.positionDriver.hasPending)                                        // no target registered yet (lazy content)
        for i in 0..<9 { s.targets.register(i, frame: CGRect(x: 0, y: CGFloat(i) * 100, width: 300, height: 100)) }
        #expect(!s.positionDriver.hasPending && s.positionDriver.applied == 1 && s.peek.presentationOffset.y == 400)
        s.targets.register(5, frame: CGRect(x: 0, y: 450, width: 300, height: 100))
        #expect(s.positionDriver.applied == 1)
    }

    @Test(arguments: OSPath.allCases) func aTouchDropsAHeldRequest(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.positionDriver.bind(PositionBinding(BindingBox().binding, anchor: nil))
        s.positionDriver.receive(ZTronScrollPosition(id: 5))
        s.beginTracking()
        #expect(!s.positionDriver.hasPending)
    }

    // MARK: the id binding

    @Test(arguments: OSPath.allCases) func theIDBindingReadsAndWritesTheIDAndSkipsUnchangedWrites(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900),
                                   displayScale: 2))
        for i in 0..<9 { s.targets.register(i, frame: CGRect(x: 0, y: CGFloat(i) * 100, width: 300, height: 100)) }
        final class Model { var id: Int? = 2; var sets = 0 }
        let m = Model()
        let b = Binding<Int?>(get: { m.id }, set: { m.id = $0; m.sets += 1 })
        s.positionDriver.bind(PositionBinding(id: b, anchor: nil))
        s.positionDriver.receive(PositionBinding(id: b, anchor: nil).read())
        // 18+: cell 2's bottom (300) meets the viewport bottom (the least scroll); before 18 its top meets the top, like SwiftUI 17.
        #expect(s.peek.presentationOffset.y == (PositionBinding.idBindingDefaultAnchor == nil ? 100 : 200))
        s.track(offset: CGPoint(x: 0, y: 100), zoom: 1)
        flingToTheNextCell(s, from: 100)
        run(s)
        let landed = Int((s.peek.presentationOffset.y / 100).rounded())
        #expect(m.id == landed && m.id != 2 && m.sets >= 1 && m.sets <= landed)  // one write per id change, none unchanged
        let before = m.sets
        s.positionDriver.receive(PositionBinding(id: b, anchor: nil).read())        // its own write read back: not applied again
        #expect(m.sets == before && s.positionDriver.applied == 1)
    }

    // MARK: hosted carousel (test 8)

    final class Model: ObservableObject {
        @Published var id: Int?
        @Published var position = ZTronScrollPosition()
        init(id: Int? = nil) { self.id = id }
    }

    struct Carousel: View {
        let state: ZTronScrollState
        let counts: BodyCount
        @ObservedObject var model: Model
        var body: some View {
            ZTronScrollView(.horizontal, state: state) {
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in Color(white: CGFloat(i) / 5).frame(width: 200, height: 200).ztronScrollID(i) }
                    ScrollToTests.BodyProbe(counts: counts)
                }
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $model.id)
        }
    }

    func hostedCarousel(_ path: OSPath, id: Int? = nil) -> (ZTronScrollState, Model, BodyCount, UIWindow) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        let model = Model(id: id), counts = BodyCount()
        let w = withOSPath(path) { host(Carousel(state: s, counts: counts, model: model)) }
        return (s, model, counts, w)
    }

    // MARK: twins (test 10)

    struct TwinHost: View {
        let state: ZTronScrollState
        @ObservedObject var model: Model
        var memberWins = false
        var body: some View {
            if memberWins {
                ZTronScrollView(.vertical, state: state) { VStack(spacing: 0) { ForEach(0..<10, id: \.self) { Color.red.frame(height: 100).ztronScrollID($0) } } }
                    .scrollPosition(id: $model.id, anchor: .top)
                    .ztronScrollPosition($model.position)
            } else {
                ZTronScrollView(.vertical, state: state) { VStack(spacing: 0) { ForEach(0..<10, id: \.self) { Color.red.frame(height: 100).ztronScrollID($0) } } }
                    .ztronScrollPosition($model.position)
            }
        }
    }

    @Test(arguments: OSPath.allCases) func theTwinAboveBindsAndTheMemberWins(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        let model = Model()
        let w = withOSPath(path) { host(TwinHost(state: s, model: model)) }
        pump(0.3)
        model.position = ZTronScrollPosition(edge: .bottom)
        pump(0.3)
        let maxY = s.makeZoomGeometry().y.bounds(at: 1).max                             // the window has safe areas: the viewport is shorter than 200
        #expect(maxY > 700 && abs(s.contentOffset.y - maxY) < 0.5)
        model.position = ZTronScrollPosition(id: 3, anchor: .top)
        pump(0.3)
        #expect(abs(s.contentOffset.y - 300) < 0.5)
        unhost(w)

        let t = makeState(path)
        t.contentInsetAdjustmentBehavior = .never
        let m2 = Model()
        let w2 = withOSPath(path) { host(TwinHost(state: t, model: m2, memberWins: true)) }
        pump(0.3)
        m2.position = ZTronScrollPosition(edge: .bottom)                            // the twin's binding is ignored
        pump(0.3)
        #expect(t.contentOffset.y == 0)
        m2.id = 5
        pump(0.3)
        #expect(abs(t.contentOffset.y - 500) < 0.5)                                 // the member's id binding: cell 5 at the top
        unhost(w2)
    }

    @Test(arguments: OSPath.allCases) func aPendingIDBeforeTheFirstLayoutAppliesOnce(path: OSPath) {
        let (s, model, _, w) = hostedCarousel(path, id: 3)
        pump(0.4)
        #expect(abs(s.contentOffset.x - 600) < 0.5 && s.positionDriver.applied == 1)
        #expect(model.id == 3 && s.positionDriver.writes == 0)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func settingTheIDScrollsAndAnimatesOnlyInsideWithAnimation(path: OSPath) {
        let (s, model, counts, w) = hostedCarousel(path)
        pump(0.3)
        #expect(s.targets.frames.count == 5)
        let bodies = counts.bodies
        model.id = 4
        pump(0.3)
        #expect(abs(s.contentOffset.x - 800) < 0.5)                                 // unanimated: already there
        withAnimation(.linear(duration: 1)) { model.id = 1 }
        pump(0.35)
        let mid = s.contentOffset.x
        #expect(mid > 205 && mid < 795, "mid-flight \(mid)")
        pump(1.4)
        #expect(abs(s.contentOffset.x - 200) < 0.5)
        #expect(s.positionDriver.writes == 0)
        _ = bodies
        unhost(w)
    }

    /// The page is written when the motion passes the middle between pages (SwiftUI: the binding follows the view it is
    /// positioned at), once for one page, and no content body runs.
    @Test(arguments: OSPath.allCases) func aSwipeWritesThePageItReachesOnceAndRunsNoContentBody(path: OSPath) {
        let (s, model, counts, w) = hostedCarousel(path, id: 0)
        pump(0.3)
        let bodies = counts.bodies
        ZTronRenderCounters.reset()
        var env = PanSessionTests.env()
        env.axes = .horizontal
        env.boundsX = AxisBounds(min: 0, max: 800)
        env.boundsY = AxisBounds(min: 0, max: 0)
        env.viewport = CGSize(width: 200, height: 200)
        var t = PointVelocityTracker()
        let lift = s.now()
        for i in 0...8 {
            let time = lift - 0.12 + Double(i) * 0.015
            t.add(CGPoint(x: -1500 * CGFloat(time - (lift - 0.12)), y: 0), at: time)
        }
        s.beginTracking(); s.beginDragging()
        s.endDrag(ReleaseRequest(origin: CGPoint(x: 80, y: 0), dragStart: .zero, liftTime: lift, fallbackVelocity: nil),
                  tracker: t, env: env, settings: ReleaseSettings())
        #expect(model.id == 0)                                                      // released at 80: page 0 is still the nearest
        pump(1.6)
        #expect(abs(s.contentOffset.x - 200) < 0.5 && model.id == 1)
        #expect(s.positionDriver.writes == 1)
        #expect(counts.bodies == bodies)
        unhost(w)
    }
}
