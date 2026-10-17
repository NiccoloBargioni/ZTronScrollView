import Foundation
import SwiftUI
import Testing
import ScrollArbitration

private func degrees(_ value: Double) -> Double { value * .pi / 180 }

/// One row of the rules truth table: the five rule conditions and the owner S16's order implies.
struct TruthRow: Sendable, Hashable, CustomTestStringConvertible {
    var offAxis: Bool
    var multiTouchZoom: Bool
    var participantMoving: Bool
    var containerMoving: Bool
    var canFollow: Bool
    var expected: ScrollOwner

    init(_ offAxis: Bool, _ multiTouchZoom: Bool, _ participantMoving: Bool, _ containerMoving: Bool,
         _ canFollow: Bool, _ expected: ScrollOwner) {
        self.offAxis = offAxis
        self.multiTouchZoom = multiTouchZoom
        self.participantMoving = participantMoving
        self.containerMoving = containerMoving
        self.canFollow = canFollow
        self.expected = expected
    }

    var testDescription: String {
        let flags = [offAxis, multiTouchZoom, participantMoving, containerMoving, canFollow]
        return flags.map { $0 ? "1" : "0" }.joined() + " → \(expected)"
    }

    func input(axis: Axis) -> ScrollArbitrationInput {
        // 31° off-axis vs 29° (on-axis); 2 touches + zoom vs 1 touch + zoom (zoom alone never matches).
        makeInput(axis: axis, translation: offAxis ? oriented(-100, 60.1, for: axis) : oriented(-100, 55.4, for: axis),
                  touchCount: multiTouchZoom ? 2 : 1, canFollow: canFollow, participantMoving: participantMoving,
                  zoom: true, containerMoving: containerMoving)
    }
}

/// Columns: offAxis, multiTouchZoom, participantMoving, containerMoving, canFollow → owner (first match).
let rulesTruthTable: [TruthRow] = [
    TruthRow(false, false, false, false, false, .container),
    TruthRow(false, false, false, false, true, .participant),
    TruthRow(false, false, false, true, false, .container),
    TruthRow(false, false, false, true, true, .container),
    TruthRow(false, false, true, false, false, .participant),
    TruthRow(false, false, true, false, true, .participant),
    TruthRow(false, false, true, true, false, .participant),
    TruthRow(false, false, true, true, true, .participant),
    TruthRow(false, true, false, false, false, .participant),
    TruthRow(false, true, false, false, true, .participant),
    TruthRow(false, true, false, true, false, .participant),
    TruthRow(false, true, false, true, true, .participant),
    TruthRow(false, true, true, false, false, .participant),
    TruthRow(false, true, true, false, true, .participant),
    TruthRow(false, true, true, true, false, .participant),
    TruthRow(false, true, true, true, true, .participant),
    TruthRow(true, false, false, false, false, .participant),
    TruthRow(true, false, false, false, true, .participant),
    TruthRow(true, false, false, true, false, .participant),
    TruthRow(true, false, false, true, true, .participant),
    TruthRow(true, false, true, false, false, .participant),
    TruthRow(true, false, true, false, true, .participant),
    TruthRow(true, false, true, true, false, .participant),
    TruthRow(true, false, true, true, true, .participant),
    TruthRow(true, true, false, false, false, .participant),
    TruthRow(true, true, false, false, true, .participant),
    TruthRow(true, true, false, true, false, .participant),
    TruthRow(true, true, false, true, true, .participant),
    TruthRow(true, true, true, false, false, .participant),
    TruthRow(true, true, true, false, true, .participant),
    TruthRow(true, true, true, true, false, .participant),
    TruthRow(true, true, true, true, true, .participant),
]

@Suite struct RulesTests {
    @Test func inputInitDefaultsToleranceTo30() {
        let input = ScrollArbitrationInput(pagingAxis: .vertical, translation: .zero, touchCount: 1,
                                           participantCanFollow: false, participantMovingAtTouchDown: false,
                                           participantZoomEnabled: false, containerMovingAtTouchDown: false)
        #expect(input.directionTolerance == 30)
        #expect(input.pagingAxis == .vertical)
    }

    @Test func rule1WinsOverEverything() {
        let off = makeInput(translation: CGSize(width: 100, height: 60.1), canFollow: false, containerMoving: true)
        #expect(ScrollArbitrationRules.decide(off) == .participant)
        let on = makeInput(translation: CGSize(width: 100, height: 55.4), canFollow: false, containerMoving: true)
        #expect(ScrollArbitrationRules.decide(on) == .container)
    }

    @Test func boundaryBothSidesOf30Degrees() {
        let above = makeInput(translation: CGSize(width: 100, height: tan(degrees(30.1)) * 100))
        #expect(ScrollArbitrationRules.decide(above) == .participant)
        let below = makeInput(translation: CGSize(width: 100, height: tan(degrees(29.9)) * 100))
        #expect(ScrollArbitrationRules.decide(below) == .container)
    }

    @Test func exactlyAtToleranceIsOnAxis() {
        let tolerance = atan2(50.0, 100.0) * 180 / .pi
        let translation = CGSize(width: 100, height: 50)
        #expect(ScrollArbitrationRules.decide(makeInput(tolerance: tolerance, translation: translation)) == .container)
        #expect(ScrollArbitrationRules.decide(makeInput(tolerance: tolerance - 1e-6, translation: translation))
                == .participant)
    }

    /// Translations built at the tolerance angle with `tan` or `cos`/`sin` land up to a few ulps above it in
    /// `atan2`; they must still count as exactly at the tolerance. 1e-6° past it is off-axis.
    @Test(arguments: [Axis.horizontal, Axis.vertical])
    func trigBuiltBoundaryIsOnAxisAtEveryTolerance(axis: Axis) {
        func owner(_ on: Double, _ off: Double, tolerance: Double) -> ScrollOwner {
            ScrollArbitrationRules.decide(makeInput(axis: axis, tolerance: tolerance,
                                                    translation: oriented(-on, off, for: axis)))
        }
        // 25 is the reviewer's case; the sweep covers every whole-degree tolerance and a fractional one.
        #expect(owner(100, tan(degrees(25)) * 100, tolerance: 25) == .container)
        #expect(owner(cos(degrees(25)) * 100, sin(degrees(25)) * 100, tolerance: 25) == .container)
        for tolerance in Array(stride(from: 1.0, through: 89, by: 1)) + [12.34] {
            for magnitude in [0.5, 1, 10, 37, 100, 333, 1_000, 2_000] {
                let at = degrees(tolerance)
                let past = degrees(tolerance + 1e-6)
                #expect(owner(magnitude, tan(at) * magnitude, tolerance: tolerance) == .container)
                #expect(owner(cos(at) * magnitude, sin(at) * magnitude, tolerance: tolerance) == .container)
                #expect(owner(magnitude, tan(past) * magnitude, tolerance: tolerance) == .participant)
                #expect(owner(cos(past) * magnitude, sin(past) * magnitude, tolerance: tolerance) == .participant)
            }
        }
        #expect(owner(100, 0, tolerance: 0) == .container)
    }

    /// Every flag is false, so on-axis falls through to rule 6 (`.container`) and off-axis is rule 1.
    @Test(arguments: [Axis.horizontal, Axis.vertical])
    func degenerateAngles(axis: Axis) {
        func owner(_ width: CGFloat, _ height: CGFloat, tolerance: Double = 30) -> ScrollOwner {
            ScrollArbitrationRules.decide(makeInput(axis: axis, tolerance: tolerance,
                                                    translation: oriented(width, height, for: axis)))
        }
        #expect(owner(0, 0) == .container)
        #expect(owner(0, 120) == .participant)
        #expect(owner(0, -120) == .participant)
        #expect(owner(-120, 0) == .container)
        for (width, height) in [(100.0, 60.1), (-100, 60.1), (100, -60.1), (-100, -60.1)] {
            #expect(owner(width, height) == .participant)
        }
        #expect(owner(0, 120, tolerance: 90) == .container)
        #expect(owner(100, 0, tolerance: -1) == .participant)
        #expect(owner(0, 0, tolerance: -1) == .container)
        #expect(owner(.nan, 10) == .container)
    }

    @Test func rule2MultiTouchZoom() {
        func owner(touches: Int, zoom: Bool) -> ScrollOwner {
            ScrollArbitrationRules.decide(makeInput(touchCount: touches, canFollow: false, zoom: zoom,
                                                    containerMoving: true))
        }
        #expect(owner(touches: 2, zoom: true) == .participant)
        #expect(owner(touches: 3, zoom: true) == .participant)
        #expect(owner(touches: 2, zoom: false) == .container)
        #expect(owner(touches: 1, zoom: true) == .container)
        #expect(owner(touches: 0, zoom: true) == .container)
    }

    @Test func rule3ParticipantMovingAtTouchDown() {
        let input = makeInput(canFollow: false, participantMoving: true, containerMoving: true)
        #expect(ScrollArbitrationRules.decide(input) == .participant)
    }

    @Test func rule4ContainerMovingAtTouchDown() {
        let input = makeInput(touchCount: 1, canFollow: true, zoom: true, containerMoving: true)
        #expect(ScrollArbitrationRules.decide(input) == .container)
    }

    @Test func rule5ParticipantCanFollow() {
        #expect(ScrollArbitrationRules.decide(makeInput(canFollow: true)) == .participant)
    }

    @Test func rule6Otherwise() {
        #expect(ScrollArbitrationRules.decide(makeInput()) == .container)
    }

    @Test func truthTableCoversAllCombinations() {
        #expect(rulesTruthTable.count == 32)
        let keys = Set(rulesTruthTable.map {
            [$0.offAxis, $0.multiTouchZoom, $0.participantMoving, $0.containerMoving, $0.canFollow]
        })
        #expect(keys.count == 32)
    }

    @Test(arguments: rulesTruthTable, [Axis.horizontal, Axis.vertical])
    func truthTableRow(row: TruthRow, axis: Axis) {
        #expect(ScrollArbitrationRules.decide(row.input(axis: axis)) == row.expected)
    }
}

@Suite struct DirectionTests {
    @Test func horizontal() {
        func direction(_ width: CGFloat, _ height: CGFloat) -> FingerDirection {
            ScrollArbitrationRules.fingerDirection(CGSize(width: width, height: height), along: .horizontal)
        }
        #expect(direction(50, 0) == .right)
        #expect(direction(-50, 0) == .left)
        #expect(direction(0, 0) == .right)
        #expect(direction(-0.0, 80) == .right)
        #expect(direction(1, -500) == .right)
        #expect(direction(.nan, 0) == .right)
    }

    @Test func vertical() {
        func direction(_ width: CGFloat, _ height: CGFloat) -> FingerDirection {
            ScrollArbitrationRules.fingerDirection(CGSize(width: width, height: height), along: .vertical)
        }
        #expect(direction(0, 50) == .down)
        #expect(direction(0, -50) == .up)
        #expect(direction(0, 0) == .down)
        #expect(direction(-500, 1) == .down)
        #expect(direction(0, -0.0) == .down)
    }
}
