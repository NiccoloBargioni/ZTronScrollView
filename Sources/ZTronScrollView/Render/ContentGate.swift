import SwiftUI

/// What the content gate does to the content right now (M3b; reworked in DBG-s3, `docs/progress/DBG-s3.md`).
struct ContentLock: Equatable {
    /// `allowsHitTesting(false)`: a new touch reaches neither a SwiftUI control nor a UIKit-backed one (Toggle, Slider, TextField).
    var blocksHits = false
    /// `.disabled(true)`: a press that is already running (a pan that began on a Button) ends without firing.
    var disables = false
    /// An overlay above the viewport absorbs the new touches (SwiftUI controls on every OS, UIKit-backed ones on iOS 27).
    var shields = false
    /// GestureMask `.none`: SwiftUI drops the gestures of the content subtree, which ends the same running press where SwiftUI
    /// honours it (iOS 17.5 yes; 18.6, 26.5 and 27.0 no, for a Button) and leaves every UIKit-backed control alone.
    var masksGestures = false

    static let open = ContentLock()
}

/// When the content must not take touches, and how (S6, S12). Pure, so it is unit-tested on the host.
///
/// The touches: content that moves without a finger (`.decelerating`, `.animating`, the resize watch's included) takes no new
/// touch unless a finger already tracks it (the touch that caught it): a catching touch must not fire a Button. A recognized
/// drag takes none either and ends the press that began under the finger, so a Button does not fire on lift.
///
/// The means. `.disabled` and `allowsHitTesting(false)` both make UIKit resign a focused text field (measured on 17.5 and 27.0:
/// UIKit posts the end of editing at once; SwiftUI takes the focus back after the second one, never after the first), so a
/// drag, a fling, an animated scroll or a resize would dismiss the keyboard where a native `ScrollView` keeps it. While a text
/// input is being edited the gate therefore uses the two levers that leave UIKit alone: the shield for new touches and the mask
/// for the press under the finger. Otherwise it is the pair that reaches every control on every OS: hit-testing for new
/// touches, `.disabled` (a drag only) for the press under the finger.
enum ContentGatePolicy {
    static func lock(phase: ZTronScrollPhase, isTracking: Bool, isDragging: Bool, isEditingText: Bool) -> ContentLock {
        let movesWithoutFinger = (phase == .decelerating || phase == .animating) && !isTracking
        let blocksNewTouches = movesWithoutFinger || isDragging
        var lock = ContentLock()
        if isEditingText {
            lock.shields = blocksNewTouches
            lock.masksGestures = isDragging
        } else {
            lock.blocksHits = blocksNewTouches
            lock.disables = isDragging
        }
        return lock
    }
}

/// Applies a ``ContentLock`` to the content placeholder. Leaf modifier changes, so content bodies are not re-evaluated (S4).
/// The gesture only carries the mask: it can never begin (`.subviews` switches it off while unlocked, `.none` while masked).
struct ContentGate: ViewModifier {
    let lock: ContentLock

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!lock.blocksHits)
            .disabled(lock.disables)
            .simultaneousGesture(DragGesture(minimumDistance: .greatestFiniteMagnitude),
                                 including: lock.masksGestures ? .none : .subviews)
    }
}

/// The viewport-sized overlay of ``ContentLock/shields``: it takes the touch (hit-testable, with a tap gesture so SwiftUI hands it
/// the touch before the content) and shows nothing; hidden from accessibility, so VoiceOver still reaches the content.
struct ContentShield: View {
    let active: Bool

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {}
            .allowsHitTesting(active)
            .accessibilityHidden(true)
    }
}
