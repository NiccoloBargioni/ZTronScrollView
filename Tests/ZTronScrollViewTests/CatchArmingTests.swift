import Testing
@testable import ZTronScrollView

@Suite struct CatchArmingTests {
    @Test func armsWhileMovingAndDisarmsAtRest() {
        let a = CatchArming()
        #expect(!a.isArmed)
        a.setMoving(true, observerDown: false)
        #expect(a.isArmed)
        a.setMoving(false, observerDown: false)
        #expect(!a.isArmed)
    }

    @Test func staysArmedWhileATouchIsDownAndDisarmsAtItsEnd() {
        let a = CatchArming()
        a.setMoving(true, observerDown: false)
        a.setMoving(false, observerDown: true)   // the catch stopped the motion with the finger still down
        #expect(a.isArmed)
        a.touchEnded()
        #expect(!a.isArmed)
    }

    @Test func touchEndWhileStillMovingStaysArmed() {
        let a = CatchArming()
        a.setMoving(true, observerDown: false)
        a.touchEnded()
        #expect(a.isArmed)
    }
}
