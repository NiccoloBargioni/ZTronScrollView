import SwiftUI
import ZTronScrollPhysics

/// The container's first-use warm-up (cost3-O, C2). SwiftUI pays one-time work on the first animated change of each
/// animatable leaf type (27.0: a Swift-runtime conformance lookup per type, `AnimatableAttributeHelper` ->
/// `swift_dynamicCast`, about 1 ms each in Debug) and on the frame clock's first schedule change and first tick; with no
/// warm-up all of it lands on the first frame of the first pull (27.0: 11-19 ms against native's 4-5). The warm-up makes
/// those first changes at appear, in leaves of their own that draw nothing:
/// - the content transform's type: `ContentWarmLeaf` (in `FrameClockDriver`'s background), its own `ContentTransform`
///   whose spare scalar (`TransformVector.w`) goes 1 -> 0;
/// - the header chain's types (`HeaderFrameChain`: slot layout or fallback frame, fade, stretch effect, clip,
///   translation): `HeaderWarmLeaf` (in the header frame leaf's background), its own chain whose share goes 1 -> 0;
/// - the frame clock: one tick, a no-op `step` (the clock flag is off).
///
/// The warm change never touches an attribute that draws the view's state. In the drawing leaves themselves
/// (`TransformHost`, `HeaderFrameModifier`, until the fold review's F1), the warm's zero-duration transaction re-ran
/// those leaves in the same update as an app's animated change made in its own appear action (an `onAppear`
/// `withAnimation { scroll(to:) }`: SwiftUI runs the inner appear actions first, and the state is already moved when
/// the warm's update runs), so that change was drawn in the warm's transaction: the content jumped to the target and the
/// motion completed at once, on both paths (`FirstUseWarmTests`); the header's leaf had the same pattern.
enum FirstUseWarm {
    /// The warm change: an animated transaction (zero duration) is what makes SwiftUI resolve the animatable types.
    @MainActor static func run(_ body: () -> Void) {
        withAnimation(.linear(duration: 0)) { body() }
    }
}

/// `FirstUseWarm`'s content leaf: a 0 × 0 clear view with its own `ContentTransform` (`warmOnly`: identity, no probe, no
/// counters). No input, so a re-run of its parent never re-runs it; only its own `warm` does, once.
struct ContentWarmLeaf: View {
    @State private var warm: CGFloat = 1

    var body: some View {
        var t = HeaderLift.transform(offset: .zero, scale: 1, metrics: ScrollMetrics(), limits: ZoomLimits(), paging: [])
        t.warm = warm
        t.warmOnly = true
        return Color.clear.frame(width: 0, height: 0)
            .modifier(t)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { if warm != 0 { FirstUseWarm.run { warm = 0 } } }
    }
}

/// `FirstUseWarm`'s header leaf: the header's frame chain (`HeaderFrameChain`, the leaf's path) around a 0 × 0 clear view,
/// built from an input without metrics (nothing drawn, nothing measured or reported: `HeaderSlotLayout` and
/// `HeaderFallbackFrame` report only a `.fit` size, and the slot note skips it), its share 1 -> 0 at appear. `state` and
/// `reporter` are the frame leaf's (references: equal on every re-run of that leaf, so this one never re-runs with it).
struct HeaderWarmLeaf: View {
    let state: ZTronScrollState
    let reporter: HeaderNaturalReporter
    @State private var warm: CGFloat = 1

    var body: some View {
        var live = HeaderLiveInput(size: nil, overflow: .uncapped, metrics: nil, tracksPull: false)
        live.layoutShare = warm
        return HeaderFrameChain(live: live, state: state, fade: nil, slot: nil, reporter: reporter, displayScale: 0)
            .build(Color.clear.frame(width: 0, height: 0), lift: 0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { if warm != 0 { FirstUseWarm.run { warm = 0 } } }
    }
}
