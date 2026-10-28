import Foundation
import CoreGraphics
import Testing
@testable import ZTronScrollView

/// `UIKitPanCore` (D60; docs/design/UIKIT-pan.md §2 at 9e6d448): exhaustive truth tables of the axis rule, the raw-state
/// mapping, the second finger, the reset-armed swallow, the decline and the dangling-pan cancel. Pure: no UIKit, no
/// clock, no state object.
@Suite struct UIKitPanCoreTests {
    typealias Core = UIKitPanCore
    typealias Raw = UIKitPanCore.RawState

    /// A drag `length` pt long, `degrees` above horizontal (screen space: up is negative y).
    static func drag(_ degrees: Double, _ length: CGFloat = 41) -> CGSize {
        let r = degrees * .pi / 180
        return CGSize(width: length * CGFloat(cos(r)), height: -length * CGFloat(sin(r)))
    }

    static let moves = Core.AxisInput(isInAxes: true, isScrollable: true)
    static let fixed = Core.AxisInput()

    enum Mover: String, CaseIterable, Sendable {
        case carousel, list, twoAxis, fitted

        var input: Core.Input {
            var i = Core.Input()
            i.horizontal = self == .carousel || self == .twoAxis ? UIKitPanCoreTests.moves : UIKitPanCoreTests.fixed
            i.vertical = self == .list || self == .twoAxis ? UIKitPanCoreTests.moves : UIKitPanCoreTests.fixed
            return i
        }
    }

    enum ConeSet: String, CaseIterable, Sendable {
        case standard, nativePage26, nativePage27

        var cones: UIKitPanCones {
            switch self {
            case .standard: return .standard
            case .nativePage26: return .nativePage26
            case .nativePage27: return .nativePage27
            }
        }
    }

    // MARK: Constants

    @Test func coneConstantsAreTheConfirmedPerOSAngles() {
        #expect(UIKitPanCones.standard == UIKitPanCones(horizontal: 45, vertical: 45))
        #expect(UIKitPanCones.nativePage26 == UIKitPanCones(horizontal: 45, vertical: 85))
        #expect(UIKitPanCones.nativePage27 == UIKitPanCones(horizontal: 45, vertical: 65))
        #expect(Core.minimumDisplacement == 8)
        #expect(Raw.possible == 0 && Raw.began == 1 && Raw.changed == 2 && Raw.ended == 3 && Raw.cancelled == 4 && Raw.failed == 5)
        #expect(Core.Axis.horizontal.cross == .vertical && Core.Axis.vertical.cross == .horizontal)
    }

    // MARK: Geometry

    @Test func anglesAreMagnitudesInZeroToNinety() {
        #expect(Core.angle(of: CGSize(width: 10, height: 0), to: .horizontal) == 0)
        #expect(abs(Core.angle(of: CGSize(width: -10, height: 0), to: .vertical) - 90) < 1e-12)
        #expect(Core.angle(of: CGSize(width: 0, height: -10), to: .vertical) == 0)
        #expect(abs(Core.angle(of: CGSize(width: -10, height: 10), to: .horizontal) - 45) < 1e-12)
        #expect(abs(Core.angle(of: Self.drag(30), to: .horizontal) - 30) < 1e-9)
        #expect(abs(Core.angle(of: Self.drag(30), to: .vertical) - 60) < 1e-9)
        // A zero vector reads 0 on both axes; NaN reads NaN.
        #expect(Core.angle(of: .zero, to: .horizontal) == 0 && Core.angle(of: .zero, to: .vertical) == 0)
        #expect(Core.angle(of: CGSize(width: CGFloat.nan, height: 1), to: .horizontal).isNaN)
    }

    /// Strictly inside; a tie (up to rounding) goes outside.
    @Test func conesHoldStrictlyLessThanTheHalfAngle() {
        #expect(Core.lies(Self.drag(44.9), inConeOf: .horizontal, halfAngle: 45))
        #expect(!Core.lies(Self.drag(45), inConeOf: .horizontal, halfAngle: 45))
        #expect(!Core.lies(CGSize(width: 7, height: 7), inConeOf: .horizontal, halfAngle: 45))
        #expect(!Core.lies(CGSize(width: 7, height: 7), inConeOf: .vertical, halfAngle: 45))
        #expect(!Core.lies(Self.drag(45.1), inConeOf: .horizontal, halfAngle: 45))
        #expect(!Core.lies(Self.drag(5), inConeOf: .vertical, halfAngle: 85), "5° above horizontal is 85° off vertical: a tie")
        #expect(Core.lies(Self.drag(5.1), inConeOf: .vertical, halfAngle: 85))
        #expect(!Core.lies(Self.drag(25), inConeOf: .vertical, halfAngle: 65))
        #expect(Core.lies(Self.drag(25.1), inConeOf: .vertical, halfAngle: 65))
        #expect(Core.lies(.zero, inConeOf: .horizontal, halfAngle: 45) && Core.lies(.zero, inConeOf: .vertical, halfAngle: 45))
        #expect(!Core.lies(CGSize(width: CGFloat.nan, height: 0), inConeOf: .horizontal, halfAngle: 45))
    }

    /// The arbiter's rule 1 numbers: more than the tolerance; exactly at it is on-axis; zero and NaN never are.
    @Test func offAxisMirrorsTheArbitersRuleOne() {
        #expect(Core.isOffAxis(Self.drag(30.1), from: .horizontal, tolerance: 30))
        #expect(!Core.isOffAxis(Self.drag(30), from: .horizontal, tolerance: 30))
        #expect(!Core.isOffAxis(Self.drag(29.9), from: .horizontal, tolerance: 30))
        #expect(Core.isOffAxis(Self.drag(59.9), from: .vertical, tolerance: 30))
        #expect(!Core.isOffAxis(Self.drag(60), from: .vertical, tolerance: 30))
        #expect(!Core.isOffAxis(.zero, from: .horizontal, tolerance: -1), "zero is on-axis even for a negative tolerance")
        #expect(Core.isOffAxis(CGSize(width: 0, height: 1), from: .horizontal, tolerance: -1))
        #expect(Core.isOffAxis(CGSize(width: 1, height: 0), from: .horizontal, tolerance: -1))
        #expect(!Core.isOffAxis(CGSize(width: CGFloat.nan, height: 1), from: .horizontal, tolerance: 30))
    }

    /// U1 Q5: at the first `shouldBegin` the finger has travelled 10.3 / 17.7 / 41 pt (150 / 600 / 2500 pt/s); UIKit's
    /// translation there excludes the 10 pt hysteresis per axis (40° read (1.7, 0) and (21.7, 16.3) = 36.9°), so the
    /// direction is the displacement, and the velocity only below 8 pt or without a touch-down.
    @Test func directionIsTheDisplacementFromEightPoints() {
        let v = CGVector(dx: 0, dy: -900)
        for travel: CGFloat in [10.3, 17.7, 41] {
            let d = Self.drag(40, travel)
            #expect(Core.direction(displacement: d, velocity: v) == d)
            #expect(abs(Core.angle(of: Core.direction(displacement: d, velocity: v), to: .horizontal) - 40) < 1e-9)
        }
        #expect(Core.direction(displacement: CGSize(width: 8, height: 0), velocity: v) == CGSize(width: 8, height: 0))
        #expect(Core.direction(displacement: CGSize(width: 7.9, height: 0), velocity: v) == CGSize(width: 0, height: -900))
        #expect(Core.direction(displacement: nil, velocity: v) == CGSize(width: 0, height: -900))
        // The bent translation would read 0° and 36.9°: neither is what the finger did.
        #expect(Core.angle(of: CGSize(width: 1.7, height: 0), to: .horizontal) == 0)
        #expect(abs(Core.angle(of: CGSize(width: 21.7, height: 16.3), to: .horizontal) - 36.9) < 0.05)
    }

    // MARK: Axis rule: "can move"

    @Test(arguments: 0..<32) func canMoveIsInAxesAndAnyReason(bits: Int) {
        let a = Core.AxisInput(isInAxes: bits & 1 != 0, isScrollable: bits & 2 != 0, bouncesAlways: bits & 4 != 0,
                               alwaysBounces: bits & 8 != 0, refresherBounces: bits & 16 != 0)
        #expect(a.canMove == (bits & 1 != 0 && bits > 1), "bits \(bits)")
    }

    // MARK: Axis rule: precedence

    /// Rule 1: each reason alone declines a drag the view would otherwise take.
    @Test func ruleOneDeclinesEverything() {
        var i = Mover.twoAxis.input
        i.direction = Self.drag(0)
        #expect(Core.decide(i))
        var a = i; a.isScrollEnabled = false; #expect(!Core.decide(a))
        var b = i; b.yieldsToSheet = true; #expect(!Core.decide(b))
        var c = i; c.isEnvironmentEnabled = false; #expect(!Core.decide(c))
        var d = i; d.sawSecondFinger = true; #expect(!Core.decide(d))
        // Rule 1 also beats rule 2.
        var e = Mover.list.input
        e.container = .init(pagingAxis: .horizontal)
        e.direction = Self.drag(35)
        #expect(Core.decide(e))
        e.sawSecondFinger = true
        #expect(!Core.decide(e))
    }

    struct RuleTwoRow: Sendable, CustomStringConvertible {
        var mover: Mover
        var paging: Core.Axis
        var degrees: Double
        var accepts: Bool
        var why: String
        var description: String { "\(mover) in a \(paging) container at \(degrees)°: \(why)" }
    }

    /// Rule 2 under S's cones (45° / 45°): a participant of a one-axis container (tolerance 30°) takes a drag the arbiter's
    /// rule 1 gives it, when it can move on the cross axis; otherwise rule 3 decides.
    static let ruleTwoRows: [RuleTwoRow] = [
        .init(mover: .list, paging: .horizontal, degrees: 35, accepts: true, why: "35° off the pager, list moves vertically"),
        .init(mover: .list, paging: .horizontal, degrees: 44, accepts: true, why: "rule 2 covers the 30–45° hole"),
        .init(mover: .list, paging: .horizontal, degrees: 30, accepts: false, why: "exactly the tolerance is on-axis; outside the vertical cone"),
        .init(mover: .list, paging: .horizontal, degrees: 20, accepts: false, why: "on-axis: the pager pages"),
        .init(mover: .list, paging: .horizontal, degrees: 60, accepts: true, why: "rule 2 and rule 3 agree"),
        .init(mover: .fitted, paging: .horizontal, degrees: 35, accepts: false, why: "a 1× zoomer cannot move on the cross axis"),
        .init(mover: .carousel, paging: .horizontal, degrees: 35, accepts: true, why: "rule 3: inside the horizontal cone"),
        .init(mover: .carousel, paging: .horizontal, degrees: 50, accepts: false, why: "cannot move vertically, outside the horizontal cone"),
        .init(mover: .carousel, paging: .vertical, degrees: 55, accepts: true, why: "35° off a vertical pager, carousel moves horizontally"),
        .init(mover: .carousel, paging: .vertical, degrees: 65, accepts: false, why: "25° off a vertical pager: on-axis"),
        .init(mover: .list, paging: .vertical, degrees: 55, accepts: true, why: "rule 3: inside the vertical cone"),
        .init(mover: .twoAxis, paging: .horizontal, degrees: 35, accepts: true, why: "two axes: rule 2"),
        .init(mover: .twoAxis, paging: .horizontal, degrees: 10, accepts: true, why: "two axes: rule 3"),
    ]

    @Test(arguments: ruleTwoRows) func ruleTwoParticipantOfAOneAxisContainer(row: RuleTwoRow) {
        var i = row.mover.input
        i.container = .init(pagingAxis: row.paging)
        i.direction = Self.drag(row.degrees)
        #expect(Core.decide(i) == row.accepts)
        // Without the container only rule 3 runs.
        i.container = nil
        let ruleThree = Core.decide(i)
        if row.why.hasPrefix("rule 3") || row.why == "two axes: rule 3" { #expect(ruleThree == row.accepts) }
    }

    /// Rule 3 over U1's Q3e sweep (10–80° in 10° steps, plus 0° and 90° from Q3), at 41 pt: every cone set, every mover.
    /// The expected sets are written out: a carousel takes what lies within 45° of horizontal; a list what lies within
    /// the vertical half-angle of vertical; a two-axis view the union; a fitted view nothing.
    @Test(arguments: ConeSet.allCases, Mover.allCases) func ruleThreeSweep(set: ConeSet, mover: Mover) {
        let expected: Set<Int>
        switch (mover, set) {
        case (.carousel, _): expected = [0, 10, 20, 30, 40]
        case (.list, .standard): expected = [50, 60, 70, 80, 90]
        case (.list, .nativePage26): expected = [10, 20, 30, 40, 50, 60, 70, 80, 90]
        case (.list, .nativePage27): expected = [30, 40, 50, 60, 70, 80, 90]
        case (.twoAxis, _): expected = Set(stride(from: 0, through: 90, by: 10))
        case (.fitted, _): expected = []
        }
        var i = mover.input
        i.cones = set.cones
        for degrees in stride(from: 0, through: 90, by: 10) {
            i.direction = Self.drag(Double(degrees))
            #expect(Core.decide(i) == expected.contains(degrees), "\(mover) \(set) \(degrees)°")
        }
    }

    /// The same rule for every quadrant: only magnitudes count.
    @Test func ruleThreeIgnoresSigns() {
        var i = Mover.carousel.input
        for (dx, dy) in [(30.0, 10.0), (-30.0, 10.0), (30.0, -10.0), (-30.0, -10.0)] {
            i.direction = CGSize(width: dx, height: dy)
            #expect(Core.decide(i))
            i.direction = CGSize(width: dy, height: dx)
            #expect(!Core.decide(i))
        }
    }

    /// Ties go outside: under S an exact 45° lies in neither cone, so even a two-axis view declines it; zero lies in
    /// every cone; NaN in none.
    @Test func ruleThreeTiesZeroAndNaN() {
        for mover in [Mover.carousel, .list, .twoAxis] {
            var i = mover.input
            i.direction = CGSize(width: 10, height: -10)
            #expect(!Core.decide(i), "\(mover) at exactly 45°")
            i.direction = .zero
            #expect(Core.decide(i), "\(mover) zero")
            i.direction = CGSize(width: CGFloat.nan, height: 0)
            #expect(!Core.decide(i), "\(mover) NaN")
        }
        var n = Mover.list.input
        n.cones = .nativePage26
        n.direction = Self.drag(5)
        #expect(!Core.decide(n), "N 26.x: exactly 5° above horizontal is a tie")
        var f = Mover.fitted.input
        f.direction = .zero
        #expect(!Core.decide(f))
        // In N a two-axis view takes every angle, the old S tie included.
        var t = Mover.twoAxis.input
        t.cones = .nativePage27
        t.direction = CGSize(width: 10, height: -10)
        #expect(Core.decide(t))
    }

    /// "Can move" reasons other than scrollable bounds, per axis; never the bounce flag of `.automatic`.
    @Test func ruleThreeReadsEveryMoveReason() {
        let reasons: [Core.AxisInput] = [
            .init(isInAxes: true, bouncesAlways: true), .init(isInAxes: true, alwaysBounces: true),
            .init(isInAxes: true, refresherBounces: true),
        ]
        for r in reasons {
            var i = Core.Input()
            i.vertical = r
            i.direction = Self.drag(80)
            #expect(Core.decide(i))
            i.direction = Self.drag(10)
            #expect(!Core.decide(i))
            var h = Core.Input()
            h.horizontal = r
            h.direction = Self.drag(10)
            #expect(Core.decide(h))
        }
        var undeclared = Core.Input()
        undeclared.horizontal = .init(isInAxes: false, isScrollable: true, bouncesAlways: true)
        undeclared.direction = Self.drag(0)
        #expect(!Core.decide(undeclared))
    }

    // MARK: Sequence: decline, direction source

    struct Answer: Equatable {
        var begins: Bool
        var events: [PanEvent]
    }
    struct Count: Equatable {
        var events: [PanEvent]
        var resets: Bool
    }
    func ask(_ c: inout Core, _ i: Core.Input, _ location: CGPoint, _ velocity: CGVector = .zero) -> Answer {
        let r = c.shouldBegin(i, location: location, velocity: velocity)
        return Answer(begins: r.begins, events: r.events)
    }
    func count(_ c: inout Core, _ n: Int, _ time: TimeInterval) -> Count {
        let r = c.touchCountChanged(to: n, time: time)
        return Count(events: r.events, resets: r.resetsRecognizer)
    }

    func live(at p: CGPoint = CGPoint(x: 100, y: 100), touches: Int = 1) -> Core {
        var c = Core()
        #expect(c.touchDown(at: p, touchCount: touches).isEmpty)
        return c
    }

    @Test func declineIsForwardedOncePerSequence() {
        var c = live()
        let i = Mover.list.input
        let flat = CGPoint(x: 141, y: 100)
        #expect(ask(&c, i, flat) == Answer(begins: false, events: [.declined]))
        #expect(c.didDecline)
        #expect(ask(&c, i, flat) == Answer(begins: false, events: []))
        c.sequenceEnded()
        #expect(!c.didDecline)
        #expect(c.touchDown(at: CGPoint(x: 100, y: 100), touchCount: 1).isEmpty)
        #expect(ask(&c, i, flat) == Answer(begins: false, events: [.declined]))
        // An accepting answer emits nothing.
        #expect(ask(&c, i, CGPoint(x: 100, y: 59)) == Answer(begins: true, events: []))
    }

    @Test func shouldBeginReadsTheDisplacementThenTheVelocity() {
        let i = Mover.carousel.input
        var c = live()
        let vertical = CGVector(dx: 0, dy: -800)
        #expect(c.shouldBegin(i, location: CGPoint(x: 110.3, y: 100), velocity: vertical).begins, "displacement 10.3 pt")
        var short = live()
        #expect(!short.shouldBegin(i, location: CGPoint(x: 105, y: 100), velocity: vertical).begins, "5 pt: the velocity decides")
        var missed = Core()
        #expect(missed.startLocation == nil)
        #expect(!missed.shouldBegin(i, location: CGPoint(x: 300, y: 100), velocity: vertical).begins, "no touch-down")
        #expect(missed.shouldBegin(i, location: CGPoint(x: 300, y: 100), velocity: CGVector(dx: 800, dy: 10)).begins)
    }

    @Test func twoTouchesDownTogetherNeverBegin() {
        var c = live(touches: 2)
        #expect(c.sawSecondFinger)
        #expect(ask(&c, Mover.twoAxis.input, CGPoint(x: 141, y: 100)) == Answer(begins: false, events: [.declined]))
        #expect(count(&c, 2, 1) == Count(events: [], resets: false), "already counted")
    }

    // MARK: Sequence: raw-state table

    struct RawRow: @unchecked Sendable, CustomStringConvertible {
        var raw: Int
        var active: Bool
        var armed: Bool
        var event: PanEvent?
        var activeAfter: Bool
        var armedAfter: Bool
        var description: String { "raw \(raw) active \(active) armed \(armed)" }
    }

    static let t = CGSize(width: -12, height: 3)
    static let v = CGVector(dx: -900, dy: 40)
    static let start = CGPoint(x: 100, y: 100)
    static let rawRows: [RawRow] = [
        .init(raw: Raw.possible, active: false, armed: false, event: nil, activeAfter: false, armedAfter: false),
        .init(raw: Raw.possible, active: true, armed: false, event: nil, activeAfter: true, armedAfter: false),
        .init(raw: Raw.began, active: false, armed: false, event: .dragChanged(translation: t, startLocation: start, time: 7),
              activeAfter: true, armedAfter: false),
        .init(raw: Raw.changed, active: true, armed: false, event: .dragChanged(translation: t, startLocation: start, time: 7),
              activeAfter: true, armedAfter: false),
        .init(raw: Raw.changed, active: true, armed: true, event: .dragChanged(translation: t, startLocation: start, time: 7),
              activeAfter: true, armedAfter: true),
        .init(raw: Raw.ended, active: true, armed: false, event: .dragEnded(translation: t, time: 7, fallbackVelocity: v),
              activeAfter: false, armedAfter: false),
        .init(raw: Raw.ended, active: false, armed: false, event: nil, activeAfter: false, armedAfter: false),
        .init(raw: Raw.cancelled, active: true, armed: false, event: .cancelled, activeAfter: false, armedAfter: false),
        .init(raw: Raw.cancelled, active: false, armed: false, event: .cancelled, activeAfter: false, armedAfter: false),
        .init(raw: Raw.cancelled, active: true, armed: true, event: nil, activeAfter: false, armedAfter: false),
        .init(raw: Raw.cancelled, active: false, armed: true, event: nil, activeAfter: false, armedAfter: false),
        .init(raw: Raw.failed, active: true, armed: false, event: nil, activeAfter: true, armedAfter: false),
        .init(raw: Raw.failed, active: false, armed: true, event: nil, activeAfter: false, armedAfter: true),
        .init(raw: -1, active: true, armed: false, event: nil, activeAfter: true, armedAfter: false),
        .init(raw: 6, active: false, armed: false, event: nil, activeAfter: false, armedAfter: false),
        .init(raw: 99, active: true, armed: true, event: nil, activeAfter: true, armedAfter: true),
        .init(raw: Int.max, active: false, armed: false, event: nil, activeAfter: false, armedAfter: false),
    ]

    /// Builds a live core in the row's state, through the public calls only.
    func core(active: Bool, armed: Bool) -> Core {
        var c = live(at: Self.start)
        if active || armed {
            _ = c.handle(stateRaw: Raw.began, translation: .zero, velocity: .zero, location: Self.start, time: 1)
        }
        if armed { c.willReset(stateRaw: Raw.changed) }
        if armed && !active {
            // The second touch ended the pan; the reset's `.cancelled` is still to come.
            _ = c.touchCountChanged(to: 2, time: 2)
            c.willReset(stateRaw: Raw.changed)
        }
        #expect(c.isPanActive == active && c.isSwallowArmed == armed)
        return c
    }

    @Test(arguments: rawRows) func rawStateTable(row: RawRow) {
        var c = core(active: row.active, armed: row.armed)
        let location = CGPoint(x: Self.start.x + Self.t.width, y: Self.start.y + Self.t.height)
        #expect(c.handle(stateRaw: row.raw, translation: Self.t, velocity: Self.v, location: location, time: 7) == row.event)
        #expect(c.isPanActive == row.activeAfter && c.isSwallowArmed == row.armedAfter)
    }

    /// Without the observer's touch-down the start point comes from the pan's first sample and stays put.
    @Test func startFallsBackToTheFirstSample() {
        var c = Core()
        let first = c.handle(stateRaw: Raw.began, translation: CGSize(width: 3, height: 0), velocity: .zero,
                             location: CGPoint(x: 113, y: 50), time: 1)
        #expect(first == .dragChanged(translation: CGSize(width: 3, height: 0), startLocation: CGPoint(x: 110, y: 50), time: 1))
        let next = c.handle(stateRaw: Raw.changed, translation: CGSize(width: 20, height: 1), velocity: .zero,
                            location: CGPoint(x: 135, y: 51), time: 2)
        #expect(next == .dragChanged(translation: CGSize(width: 20, height: 1), startLocation: CGPoint(x: 110, y: 50), time: 2))
        // The observer's point wins whenever it exists.
        var d = live(at: CGPoint(x: 90, y: 50))
        #expect(d.handle(stateRaw: Raw.began, translation: CGSize(width: 3, height: 0), velocity: .zero,
                         location: CGPoint(x: 113, y: 50), time: 1)
                == .dragChanged(translation: CGSize(width: 3, height: 0), startLocation: CGPoint(x: 90, y: 50), time: 1))
    }

    // MARK: Sequence: second finger and swallow

    func began(_ c: inout Core, translation: CGSize = CGSize(width: -15, height: 0), velocity: CGVector = CGVector(dx: -600, dy: 0)) {
        _ = c.handle(stateRaw: Raw.began, translation: translation, velocity: velocity, location: Self.start, time: 1)
        _ = c.handle(stateRaw: Raw.changed, translation: translation, velocity: velocity, location: Self.start, time: 1.1)
    }

    @Test func secondFingerEndsAnActivePanOnceAndAsksForAReset() {
        var c = live()
        began(&c)
        #expect(count(&c, 2, 3) == Count(events: [.dragEnded(translation: CGSize(width: -15, height: 0), time: 3,
                                                             fallbackVelocity: CGVector(dx: -600, dy: 0))], resets: true))
        #expect(!c.isPanActive && c.sawSecondFinger)
        #expect(count(&c, 3, 4) == Count(events: [], resets: false), "once per sequence")
        #expect(count(&c, 1, 5) == Count(events: [], resets: false))
        // The finger still down never begins the pan again, and stray samples are dropped.
        #expect(!c.shouldBegin(Mover.twoAxis.input, location: CGPoint(x: 141, y: 100), velocity: .zero).begins)
        #expect(c.handle(stateRaw: Raw.changed, translation: .zero, velocity: .zero, location: Self.start, time: 6) == nil)
        #expect(c.handle(stateRaw: Raw.began, translation: .zero, velocity: .zero, location: Self.start, time: 6) == nil)
        #expect(c.handle(stateRaw: Raw.ended, translation: .zero, velocity: .zero, location: Self.start, time: 6) == nil)
        #expect(!c.isPanActive)
    }

    @Test func secondFingerWithoutAnActivePanOnlyResets() {
        var c = live()
        #expect(count(&c, 2, 1) == Count(events: [], resets: true))
        var idle = Core()
        #expect(count(&idle, 2, 1) == Count(events: [], resets: false), "no live sequence")
        #expect(!idle.sawSecondFinger)
        var one = live()
        #expect(count(&one, 1, 1) == Count(events: [], resets: false))
    }

    /// U1 C4: the reset of an active pan yields exactly one `.cancelled`, inside the call on 17.5 / 18.x and after it on
    /// 26+. Both timings are swallowed; the arm is spent by that one `.cancelled`.
    @Test(arguments: [false, true]) func resetSwallowsItsOneCancelInBothTimings(afterTheCall: Bool) {
        var c = live()
        began(&c)
        #expect(count(&c, 2, 3).resets)
        c.willReset(stateRaw: Raw.changed)
        if afterTheCall {
            #expect(count(&c, 2, 3.01) == Count(events: [], resets: false))
            #expect(count(&c, 1, 3.02) == Count(events: [], resets: false))
        }
        #expect(c.handle(stateRaw: Raw.cancelled, translation: .zero, velocity: .zero, location: Self.start, time: 3.03) == nil)
        #expect(!c.isSwallowArmed)
        #expect(c.handle(stateRaw: Raw.cancelled, translation: .zero, velocity: .zero, location: Self.start, time: 3.04) == .cancelled,
                "a second cancel is real")
    }

    @Test(arguments: [Raw.possible, Raw.ended, Raw.cancelled, Raw.failed, -1, 7]) func resetOutsideBeganOrChangedArmsNothing(raw: Int) {
        var c = live()
        c.willReset(stateRaw: raw)
        #expect(!c.isSwallowArmed)
        c.willReset(stateRaw: Raw.began)
        #expect(c.isSwallowArmed)
    }

    @Test func theArmClearsWhenTheSequenceEnds() {
        var c = live()
        began(&c)
        c.willReset(stateRaw: Raw.began)
        c.sequenceEnded()
        #expect(!c.isSwallowArmed && c.isPanActive, "the lift leaves the pan alone")
        #expect(c.handle(stateRaw: Raw.cancelled, translation: .zero, velocity: .zero, location: Self.start, time: 9) == .cancelled)
        var d = live()
        d.willReset(stateRaw: Raw.changed)
        #expect(d.touchDown(at: Self.start, touchCount: 1).isEmpty)
        #expect(!d.isSwallowArmed)
    }

    // MARK: Sequence: lift order and dangling pan

    /// U1 C5: the observer's last lift comes before the pan's `.ended`: the pan's `.ended` is still the release, with
    /// UIKit's velocity, and the next touch-down finds nothing open.
    @Test func liftBeforeTheEndedIsStillTheRelease() {
        var c = live()
        began(&c)
        c.sequenceEnded()
        #expect(!c.isSequenceLive && c.startLocation == nil && c.isPanActive)
        let end = c.handle(stateRaw: Raw.ended, translation: CGSize(width: -40, height: 2), velocity: CGVector(dx: -1500, dy: 9),
                           location: .zero, time: 4)
        #expect(end == .dragEnded(translation: CGSize(width: -40, height: 2), time: 4, fallbackVelocity: CGVector(dx: -1500, dy: 9)))
        #expect(c.touchDown(at: Self.start, touchCount: 1).isEmpty)
    }

    @Test func aPanLeftOpenEndsAsCancelledAtTheNextTouchDown() {
        var c = live()
        began(&c)
        c.sequenceEnded()
        #expect(c.touchDown(at: CGPoint(x: 20, y: 30), touchCount: 1) == [.cancelled])
        #expect(!c.isPanActive && c.isSequenceLive && c.startLocation == CGPoint(x: 20, y: 30))
        #expect(c.touchDown(at: CGPoint(x: 20, y: 30), touchCount: 1).isEmpty)
        // An open pan whose sequence never closed (a missed lift) ends the same way.
        var d = live()
        began(&d)
        #expect(d.touchDown(at: Self.start, touchCount: 2) == [.cancelled])
        #expect(d.sawSecondFinger)
    }
}
