import SwiftUI
import Testing
@testable import ZTronScrollView

// M8b header behaviors (design docs/design/M8b-header-behaviors.md §1, build step 1): the `collapse:` / `pull:` parameters,
// the deprecated `scalingBehavior:` overload, `ZTronHeaderCollapseBehavior` and the `ZTronHeaderFade` set.

/// Stand-ins for the user's theme color (`Color(source:value:)`) in the call shape below.
private struct StandInTheme {
    var appBackground = Color(red: 0.08, green: 0.09, blue: 0.11)
}

private extension Color {
    init(source: StandInTheme, value: KeyPath<StandInTheme, Color>) { self = source[keyPath: value] }
}

/// The user's call, exactly as spelled (request 2026-11-01), with a stand-in color and image: the deprecated
/// `scalingBehavior:` overload must keep compiling (with its deprecation warning). After D69 a pull grows the image.
private struct UserBannerScreen: View {
    let theme = StandInTheme()

    var body: some View {
        NavigationView {
            GeometryReader { _ in
                ZTronScrollView(.vertical) {
                    VStack(spacing: 0) { ForEach(0..<30, id: \.self) { Text("Row \($0)").frame(height: 44) } }
                }
                .withScalingHeader(size: .aspectRatio(16.0/9.0, min: 0.0), scalingBehavior: .stretch,
                                   fade: .linear(to: Color(source: self.theme, value: \.appBackground)), overflow: .refit,
                                   header: { _ in Image("app.global.about.us.snapshot").resizable().aspectRatio(16.0/9.0, contentMode: .fit)
                                       .frame(maxWidth: .infinity) })
            }
        }
    }
}

@MainActor @Suite struct ScalingHeaderAPITests {
    static let bg = Color(red: 0.08, green: 0.09, blue: 0.11)

    @Test func theDeprecatedOverloadForwardsToPull() throws {
        let v = ZTronScrollView { Color.clear }
            .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 0.0), scalingBehavior: .stretch,
                               fade: .linear(to: Self.bg), overflow: .refit, header: { _ in Color.red })
        let spec = try #require(v.config.header)
        #expect(spec.behavior == .stretch && spec.collapse == .compress)
        #expect(spec.size == .aspectRatio(16.0 / 9.0, min: 0) && spec.overflow == .refit && spec.snap == .disabled)
        #expect(spec.fade == .linear(to: Self.bg))
        #expect(spec.stretchContent == .keepTextMagnified, "D76: the deprecated spelling forwards the default")
        _ = UserBannerScreen().body   // the user's shape builds (its body is a value; nothing is rendered)
    }

    @Test func theDefaultsAreCompressAndPreserve() throws {
        let spec = try #require(ZTronScrollView { Color.clear }.withScalingHeader(size: .fixed(max: 200)) { _ in Color.red }
            .config.header)
        #expect(spec.collapse == .compress && spec.behavior == .preserve && spec.fade == nil)
        #expect(spec.stretchContent == .keepTextMagnified, "D76: the default is D69's look")
        // D76: carried, render-only (not in the sizing: a change runs no headerSpecChanged()).
        let grow = try #require(ZTronScrollView { Color.clear }
            .withScalingHeader(size: .fixed(max: 200), pull: .stretch, stretchContent: .keepTextSize) { _ in Color.red }
            .config.header)
        #expect(grow.stretchContent == .keepTextSize)
        #expect(grow.sizing(pull: .openGap) == ZTronScrollView { Color.clear }
            .withScalingHeader(size: .fixed(max: 200), pull: .stretch) { _ in Color.red }.config.header?.sizing(pull: .openGap))
        #expect(spec.sizing(pull: .openGap).collapse == .compress)
    }

    @Test func collapseAndPullAreCarriedToTheSizingAndTheMetrics() throws {
        let spec = try #require(ZTronScrollView { Color.clear }
            .withScalingHeader(size: .fixed(min: 64, max: 240), collapse: .slideBehind(parallax: 0.25), pull: .stretch) { _ in
                Color.red
            }.config.header)
        #expect(spec.collapse == .slideBehind(parallax: 0.25) && spec.behavior == .stretch)
        let sizing = spec.sizing(pull: .followContent)
        #expect(sizing.collapse == .slideBehind(parallax: 0.25) && sizing.pull == .followContent)
        let m = try #require(sizing.resolve(width: 402, natural: nil, vertical: true, containerHeight: 778))
        #expect(m.collapse == .slideBehind(parallax: 0.25) && m.behavior == .stretch && m.pull == .followContent)
        let compress = try #require(HeaderMath.metrics(size: .fixed(min: 64, max: 240), width: 402, natural: nil))
        #expect(compress.collapse == .compress, "the default mode")
    }

    @Test func slideBehindSpellings() {
        #expect(ZTronHeaderCollapseBehavior.slideBehind == .slideBehind(parallax: 0.5))
        #expect(ZTronHeaderCollapseBehavior.slideBehind == .slideBehind())
        #expect(ZTronHeaderCollapseBehavior.slideBehind.parallax == 0.5)
        #expect(ZTronHeaderCollapseBehavior.slideBehind.backdrop == nil)
        #expect(ZTronHeaderCollapseBehavior.compress.parallax == nil && !ZTronHeaderCollapseBehavior.compress.isSlideBehind)
        #expect(ZTronHeaderCollapseBehavior.slideBehind.isSlideBehind)
        let backed = ZTronHeaderCollapseBehavior.slideBehind(parallax: 1, backdrop: Self.bg)
        #expect(backed.parallax == 1 && backed.backdrop == Self.bg)
        #expect(backed != .slideBehind(parallax: 1), "the backdrop is part of the value")
        #expect(backed.kind == ZTronHeaderCollapseBehavior.slideBehind(parallax: 1).kind, "but not of the mode")
    }

    @Test(arguments: [(CGFloat(0), CGFloat(0)), (1, 1), (0.3, 0.3), (-2, 0), (7, 1), (.nan, 0.5), (.infinity, 1),
                      (-.infinity, 0)])
    func parallaxIsClampedAndNaNSafe(written: CGFloat, read: CGFloat) {
        let b = ZTronHeaderCollapseBehavior.slideBehind(parallax: written)
        #expect(b.parallax == read)
        #expect(b == .slideBehind(parallax: read), "equal to the clamped spelling (NaN included: reflexive)")
        #expect(b == b)
        let inRange = !written.isNaN && written >= 0 && written <= 1
        #expect((b.requestedParallax == nil) == inRange, "the DEBUG note's input is kept only when it was adjusted")
    }

    @Test func theFadeSet() {
        let g = ZTronHeaderFade.Gradient.linear(to: Self.bg)
        #expect(g.start == 0.5 && g.color == Self.bg)
        #expect(ZTronHeaderFade.linear(to: Self.bg) == ZTronHeaderFade(rest: g, collapse: g, pull: g),
                ".linear(to:from:) is the same gradient in every state")
        #expect(ZTronHeaderFade.linear(to: .red, from: 0.2) == .init(rest: .linear(to: .red, from: 0.2),
                                                                     collapse: .linear(to: .red, from: 0.2),
                                                                     pull: .linear(to: .red, from: 0.2)))
        // The user's split spelling.
        let split: ZTronHeaderFade = .init(rest: .linear(to: Self.bg), collapse: .linear(to: Self.bg, from: 0), pull: nil)
        #expect(split.rest?.start == 0.5 && split.collapse?.start == 0 && split.pull == nil)
        let restOnly = ZTronHeaderFade(rest: .linear(to: .red))
        #expect(restOnly.collapse == nil && restOnly.pull == nil, "a state left out draws no fade")
        #expect(ZTronHeaderFade.Gradient.linear(to: .red, from: -1).start == 0)
        #expect(ZTronHeaderFade.Gradient.linear(to: .red, from: 3).start == 1)
        #expect(ZTronHeaderFade.Gradient.linear(to: .red, from: .nan).start == 0.5)
        #expect(ZTronHeaderFade.Gradient.linear(to: .red, from: .nan) == .linear(to: .red, from: .nan), "reflexive")
    }
}
