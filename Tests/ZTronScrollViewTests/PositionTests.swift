import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

@MainActor
final class BindingBox {
    var position = ZTronScrollPosition()
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

    // MARK: write-back

    @Test(arguments: OSPath.allCases) func aFlingWritesTheLandedViewAtTheReleaseAndSettleWritesNothingNew(path: OSPath) {
        let (s, box) = make(path, offset: CGPoint(x: 0, y: 300))
        s.writeDragOffset(CGPoint(x: 0, y: 310)); s.writeDragOffset(CGPoint(x: 0, y: 330))
        #expect(s.positionDriver.writes == 0)                       // nothing per drag frame
        flingToTheNextCell(s, from: 330)
        #expect(s.positionDriver.writes == 1)                       // the release target decided
        let landed = box.position.viewID(type: Int.self)
        #expect(landed != nil && box.position.isPositionedByUser)
        run(s)
        #expect(abs(s.peek.presentationOffset.y - CGFloat((landed ?? 0) * 100)) < 0.5)
        #expect(s.positionDriver.writes <= 2 && s.positionDriver.writes == box.sets.count)
        #expect(box.position.viewID(type: Int.self) == landed)
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
        box.position = ZTronScrollPosition(edge: .top)                              // the app moves the binding
        s.positionDriver.receive(box.position)
        #expect(s.peek.presentationOffset.y == 0)
        s.track(offset: CGPoint(x: 0, y: 300), zoom: 1)
        flingToTheNextCell(s)
        run(s)
        #expect(s.positionDriver.writes == writes + 1 || s.positionDriver.writes == writes + 2)
        #expect(box.position.viewID(type: Int.self) == landed && box.position.isPositionedByUser)
        // And the request the app made before the user scrolled is a new request when made again.
        let applied = s.positionDriver.applied
        box.position = ZTronScrollPosition(edge: .top)
        s.positionDriver.receive(box.position)
        #expect(s.positionDriver.applied == applied + 1)
    }

    @Test(arguments: OSPath.allCases) func theValueUnderTheAnchorIsWritten(path: OSPath) {
        for (anchor, expected) in [(UnitPoint.topLeading, 3), (UnitPoint.center, 4), (UnitPoint.bottom, 4)]   // the bottom edge (500) belongs to the cell above it
 {
            let (s, box) = make(path, anchor: anchor, offset: CGPoint(x: 0, y: 300))
            s.targetBehavior = AnyZTronScrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior(limitBehavior: .never))
            // A release that stays at 300 (zero velocity): the viewport shows cells 3 and 4.
            s.beginTracking(); s.beginDragging()
            s.endDrag(ReleaseRequest(origin: CGPoint(x: 0, y: 300), dragStart: CGPoint(x: 0, y: 300), liftTime: 100, fallbackVelocity: nil),
                      tracker: tracker(vy: 0), env: PanSessionTests.env(), settings: ReleaseSettings())
            #expect(box.position.viewID(type: Int.self) == expected, "anchor \(anchor)")
        }
    }

    @Test(arguments: OSPath.allCases) func withoutAViewUnderTheAnchorThePointIsWritten(path: OSPath) {
        let (s, box) = make(path, offset: CGPoint(x: 0, y: 300))
        s.targets.unregister(3); s.targets.unregister(4)
        s.beginTracking(); s.beginDragging()
        s.endDrag(ReleaseRequest(origin: CGPoint(x: 0, y: 300), dragStart: CGPoint(x: 0, y: 300), liftTime: 100, fallbackVelocity: nil),
                  tracker: tracker(vy: 0), env: PanSessionTests.env(), settings: ReleaseSettings())
        #expect(box.position.point == CGPoint(x: 0, y: 300) && box.position.viewID == nil && box.position.isPositionedByUser)
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
        #expect(s.peek.presentationOffset.y == 100)                                 // cell 2's bottom (300) meets the viewport bottom
        flingToTheNextCell(s, from: 100)
        run(s)
        #expect(m.id != nil && m.id != 2 && m.sets <= 2)
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

    @Test(arguments: OSPath.allCases) func aSwipeWritesThePageOnceOrTwiceAndRunsNoContentBody(path: OSPath) {
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
        let written = model.id
        #expect(written == 1)
        pump(1.6)
        #expect(abs(s.contentOffset.x - 200) < 0.5 && model.id == 1)
        #expect(s.positionDriver.writes <= 2 && s.positionDriver.writes >= 1)
        #expect(counts.bodies == bodies)
        unhost(w)
    }
}
