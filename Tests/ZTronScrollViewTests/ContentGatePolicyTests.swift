import Testing
import Foundation
@testable import ZTronScrollView

/// The content gate (M3b, DBG-s3b): which touches the content takes, and by which means.
@Suite struct ContentGatePolicyTests {
    private func lock(_ phase: ZTronScrollPhase, tracking: Bool = false, dragging: Bool = false, editing: Bool = false) -> ContentLock {
        ContentGatePolicy.lock(phase: phase, isTracking: tracking, isDragging: dragging, isEditingText: editing)
    }

    /// Every combination the state can be in (a drag needs a finger, so it implies tracking).
    private var states: [(phase: ZTronScrollPhase, tracking: Bool, dragging: Bool)] {
        ZTronScrollPhase.allCases.flatMap { phase in
            [(phase, false, false), (phase, true, false), (phase, true, true)]
        }
    }

    @Test func contentIsOpenWhileNothingMovesWithoutAFinger() {
        for editing in [false, true] {
            #expect(lock(.idle, editing: editing) == .open)
            #expect(lock(.tracking, tracking: true, editing: editing) == .open)
            #expect(lock(.interacting, tracking: true, editing: editing) == .open)
        }
    }

    @Test func aNewTouchIsBlockedByHitTestingWhileTheContentMovesWithoutAFinger() {
        for phase in [ZTronScrollPhase.decelerating, .animating] {
            #expect(lock(phase) == ContentLock(blocksHits: true), "nothing is disabled: \(phase)")
        }
    }

    @Test func theCatchingTouchOpensTheGate() {
        for editing in [false, true] {
            #expect(lock(.decelerating, tracking: true, editing: editing) == .open)
            #expect(lock(.animating, tracking: true, editing: editing) == .open)
        }
    }

    @Test func aRecognizedDragDisablesTheContentToEndThePressUnderTheFinger() {
        for phase in [ZTronScrollPhase.interacting, .tracking] {
            #expect(lock(phase, tracking: true, dragging: true) == ContentLock(blocksHits: true, disables: true), "\(phase)")
        }
    }

    @Test func whileATextInputIsEditedTheShieldAndTheMaskStandInForHitTestingAndDisabled() {
        for phase in [ZTronScrollPhase.decelerating, .animating] {
            #expect(lock(phase, editing: true) == ContentLock(shields: true), "\(phase)")
        }
        for phase in [ZTronScrollPhase.interacting, .tracking] {
            #expect(lock(phase, tracking: true, dragging: true, editing: true) == ContentLock(shields: true, masksGestures: true), "\(phase)")
        }
    }

    @Test func whileATextInputIsEditedNeitherDisabledNorHitTestingIsEverUsed() {
        // UIKit resigns the focused field for either (and SwiftUI only gives the focus back after hit-testing).
        for s in states {
            let l = lock(s.phase, tracking: s.tracking, dragging: s.dragging, editing: true)
            #expect(!l.disables && !l.blocksHits, "\(s)")
        }
    }

    @Test func nothingButADragEverDisablesTheContent() {
        // A fling's deceleration, an animated scroll and a resize used to disable it and dismissed the keyboard.
        for s in states {
            #expect(lock(s.phase, tracking: s.tracking, dragging: s.dragging).disables == s.dragging, "\(s)")
        }
    }

    @Test func editingChangesTheMeansNeverWhichTouchesAreTaken() {
        for s in states {
            let plain = lock(s.phase, tracking: s.tracking, dragging: s.dragging)
            let editing = lock(s.phase, tracking: s.tracking, dragging: s.dragging, editing: true)
            #expect((plain.blocksHits || plain.shields) == (editing.blocksHits || editing.shields), "\(s)")
            #expect((plain.disables || plain.masksGestures) == (editing.disables || editing.masksGestures), "\(s)")
        }
    }
}
