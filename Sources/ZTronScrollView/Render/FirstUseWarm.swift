import SwiftUI

/// The container's first-use warm-up (cost3-O, C2). SwiftUI pays one-time work on the first animated change of each
/// animatable leaf type (27.0: a Swift-runtime conformance lookup per type, `AnimatableAttributeHelper` ->
/// `swift_dynamicCast`, about 1 ms each in Debug) and on the frame clock's first schedule change and first tick; with no
/// warm-up all of it lands on the first frame of the first pull (27.0: 11-19 ms against native's 4-5). The warm-up makes
/// those first changes at appear, inside the appear transaction, in values whose drawn result is identical by
/// construction:
/// - the header frame leaf: its share is written outside [0, 1] (`-1` / `2`) and returns to `0` / `1`; every reader
///   clamps it (`HeaderLiveInput.layoutStretch`), so every drawn value is bit-identical;
/// - the content transform: a spare animatable scalar (`TransformVector.w`) that feeds nothing drawn;
/// - the frame clock: one tick, a no-op `step` (the clock flag is off).
enum FirstUseWarm {
    /// The warm change: an animated transaction (zero duration) is what makes SwiftUI resolve the animatable types.
    @MainActor static func run(_ body: () -> Void) {
        withAnimation(.linear(duration: 0)) { body() }
    }
}
