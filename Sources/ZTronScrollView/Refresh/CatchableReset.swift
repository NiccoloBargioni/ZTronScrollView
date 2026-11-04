import SwiftUI

/// D79 (M8b-s8 s3, open item 33): the token a SwiftUI-drawn refresh reset (D39) carries on 17+ (`CatchableResetAnimation`).
/// A drawn catch cuts it (`ZTronScrollState.interrupt(catching:)`); every animation that carries it then reports itself
/// finished. Lock-protected: SwiftUI may run an animation off the main thread (its async renderer).
final class DrawnResetToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cutFlag = false

    var isCut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cutFlag
    }

    func cut() {
        lock.lock()
        cutFlag = true
        lock.unlock()
    }
}

/// D79, iOS 17+ (`ZTronCapability.customAnimation`): the library's SwiftUI-drawn refresh reset as an animation a drawn
/// catch ends. SwiftUI 17.x keeps an animation running through an unanimated write of its value and adds the rest of it to
/// the new value: measured on 17.5, the header's six effects drew the reset's remainder 2.7 s past a catch of the lab's 4 s
/// reset. The catch pin (`CatchPin`) drew their model values meanwhile, which also drew an app's animation of the same inputs
/// in that time at its final value (`withAnimation { contentInset.top += 40 }` 0.1 s after the catch: the header 41 pt in one
/// frame, where it follows the app's curve without a catch). Wrapped in this, every value of the reset follows the base
/// animation until the catch cuts the token; from its next frame `animate` reports the animation finished, so SwiftUI drops
/// the rest and draws the model (the caught state): the pins end at their first evaluations, as on 27.0, where SwiftUI ends
/// the animation at the catch's write itself. 15–16 (and the forced lane): no `CustomAnimation`, the pin alone.
@available(iOS 17.0, *)
struct CatchableResetAnimation: CustomAnimation {
    let base: Animation
    let token: DrawnResetToken

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        token.isCut ? nil : base.animate(value: value, time: time, context: &context)
    }

    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        token.isCut ? nil : base.velocity(value: value, time: time, context: context)
    }

    func shouldMerge<V: VectorArithmetic>(previous: Animation, value: V, time: TimeInterval,
                                          context: inout AnimationContext<V>) -> Bool {
        base.shouldMerge(previous: previous, value: value, time: time, context: &context)
    }

    static func == (a: Self, b: Self) -> Bool { a.base == b.base && a.token === b.token }

    func hash(into hasher: inout Hasher) {
        hasher.combine(base)
        hasher.combine(ObjectIdentifier(token))
    }
}
