import SwiftUI

/// D79 (M8b-s8 s3, open item 33): the catch pin. A touch that catches the content while the library's own SwiftUI-animated
/// write draws it away from the model (a refresh reset: `ZTronScrollState.drawnAway()`) makes the model the drawn state
/// (`interrupt()`). Whether SwiftUI then keeps the rest of that animation in an effect that interpolates the offset is
/// up to the OS (17.x keeps it through the catch's unanimated write and every finger write after it; 27.0 cancels it at
/// once, the per-frame refresh leaf two updates later): an effect that kept it would draw the model plus the residual.
/// So every effect that follows the offset draws its MODEL value (the non-animatable copy its host hands it) instead of
/// its interpolation while the pin holds, until its own interpolation reaches the model; that ends its latch for this
/// catch, and it draws its interpolation again (a later animation of the same inputs is drawn as usual). One latch per
/// effect: they converge separately (measured on 17.5 without the 17+ cut: the content's at its third evaluation, the
/// header's after 2.7 s, which drew an app's animation of the same inputs in that time at its final value). On 17+ the catch
/// also ends the reset itself (`CatchableResetAnimation`): every pin ends at the next update. Where SwiftUI cancels at the
/// write (27.0), the first evaluation converges and the pin is a no-op. On 15–16 the pin is the only mechanism.
///
/// Any effect that animates the offset (`ContentTransform`, the refresh placement, the header's six) reads the pin; a
/// future one must too, or 17.x draws the residual over its neighbours again (D79). Lock-protected like the presentation
/// probe: effects may be evaluated off the main thread (SwiftUI's async renderer lays out animation frames).
final class CatchPin: @unchecked Sendable {
    /// The effects that pin, one latch each.
    enum Key: Hashable, Sendable {
        case content
        case refresh(Edge)
        /// The same edge's placement in the slot behind the content (D80: 15–16 and the forced fallbacks lay the leaf out
        /// in both slots; each effect keeps its own latch, so the one that does not draw never ends the drawn one's).
        case refreshBehind(Edge)
        case headerStretch, headerClip, headerTranslation, headerSlot, headerFallback, headerFade
    }

    /// What a host hands its effect while the pin holds: the catch's number and the pin. Equal by number and identity.
    struct Ref: Equatable, @unchecked Sendable {
        let seq: Int
        let pin: CatchPin

        static func == (a: Ref, b: Ref) -> Bool { a.seq == b.seq && a.pin === b.pin }

        /// Whether `key` draws its model value now: until its interpolation reaches the model (`converged`), which ends
        /// its latch for this catch for good.
        func pins(_ key: Key, converged: Bool) -> Bool { pin.pins(key, seq: seq, converged: converged) }
    }

    /// Same value within 0.01 pt: an interpolation that reached the model.
    static let tolerance: CGFloat = 0.01
    /// Same zoom within 1e-5.
    static let zoomTolerance: CGFloat = 1e-5

    private let lock = NSLock()
    private var ended: [Key: Int] = [:]
    #if DEBUG
    private var started: [Key: Int] = [:]
    private var firstNoted: [Key: Int] = [:]
    #endif

    func pins(_ key: Key, seq: Int, converged: Bool) -> Bool {
        lock.lock()
        if ended[key] == seq { lock.unlock(); return false }
        if converged {
            ended[key] = seq
            #if DEBUG
            let wasStarted = started[key] == seq
            lock.unlock()
            Self.note("pin end \(key) seq \(seq)\(wasStarted ? "" : " (first evaluation)")", counter: "pin.end")
            #else
            lock.unlock()
            #endif
            return false
        }
        #if DEBUG
        let first = started[key] != seq
        started[key] = seq
        lock.unlock()
        if first { Self.note("pin start \(key) seq \(seq)", counter: "pin.start") }
        #else
        lock.unlock()
        #endif
        return true
    }

    #if DEBUG
    /// DEBUG: `text` once per key and catch, at the key's first evaluation after it (the acceptance reads the content's
    /// first drawn offset after a catch from it).
    func noteFirst(_ key: Key, seq: Int, _ text: @autoclosure () -> String) {
        lock.lock()
        let first = firstNoted[key] != seq
        firstNoted[key] = seq
        lock.unlock()
        if first { Self.note(text(), counter: "pin.first") }
    }

    /// DEBUG events (C17): the render counters' event log and a counter, on the main thread (an effect may run elsewhere).
    static func note(_ text: String, counter: String) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                ZTronRenderCounters.increment(counter)
                ZTronRenderCounters.event(text)
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ZTronRenderCounters.increment(counter)
                    ZTronRenderCounters.event(text + " (async)")
                }
            }
        }
    }
    #endif
}

extension CatchPin.Ref {
    /// The pinned value of a `CGFloat` effect input: `model` while `key` pins, else `interpolated`.
    func resolve(_ key: CatchPin.Key, interpolated: CGFloat, model: CGFloat) -> CGFloat {
        pins(key, converged: abs(interpolated - model) <= CatchPin.tolerance) ? model : interpolated
    }
}

extension TransformVector {
    /// Every scalar within the pin's tolerance of `other` (offsets and insets 0.01 pt, the zoom 1e-5).
    func within(_ other: TransformVector) -> Bool {
        let t = CatchPin.tolerance
        return abs(ox - other.ox) <= t && abs(oy - other.oy) <= t && abs(s - other.s) <= CatchPin.zoomTolerance
            && abs(top - other.top) <= t && abs(leading - other.leading) <= t && abs(bottom - other.bottom) <= t
            && abs(trailing - other.trailing) <= t
    }
}

extension ContentTransform {
    /// D79: this effect with the pin of the last drawn catch (`ZTronScrollState.catchPinRef`) and, as the pin's model, the
    /// values it is built with (the host's target values: the effect's animatable data before SwiftUI interpolates it).
    /// `nil`: unchanged (no pin, every frame its interpolation).
    func pinned(_ ref: CatchPin.Ref?) -> ContentTransform {
        guard let ref else { return self }
        var c = self
        c.pin = ref
        c.pinModel = animatableData
        return c
    }
}
