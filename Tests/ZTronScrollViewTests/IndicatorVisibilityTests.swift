import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// M8-1 (design M8 §2, §10): which visibility each axis ends up with. The pure resolution first (member > twin > native
/// environment > `.automatic`, with `showsIndicators: false` deciding what `.automatic` means), then the same facts
/// through a hosted `ZTronScrollView` on both OS paths, and the SwiftUI round trips (16+, runtime-gated).
@MainActor
@Suite(.serialized)
struct IndicatorVisibilityTests {
    typealias V = ZTronScrollIndicatorVisibility

    func config(_ h: V? = nil, _ v: V? = nil, shows: Bool? = nil) -> ChromeConfig {
        var c = ChromeConfig()
        c.indicators = AxisPair(horizontal: h, vertical: v)
        c.showsIndicators = shows
        return c
    }

    func resolve(member: ChromeConfig = ChromeConfig(), twin: ChromeConfig = ChromeConfig(),
                 native: AxisPair<V>? = nil) -> ResolvedIndicators {
        IndicatorResolution.resolve(member: member, twin: twin, native: native)
    }

    // MARK: pure resolution

    @Test func nothingSetIsAutomaticOnBothAxes() {
        let r = resolve()
        #expect(r.horizontal == .automatic && r.vertical == .automatic && r.drawsAnything && r.hasAutomatic)
    }

    @Test func memberBeatsTwinBeatsNativeBeatsAutomaticPerAxis() {
        let native = AxisPair<V>(horizontal: .never, vertical: .never)
        #expect(resolve(member: config(.visible, .visible), twin: config(.hidden, .hidden), native: native).vertical == .visible)
        #expect(resolve(twin: config(.hidden, .hidden), native: native).vertical == .hidden)
        #expect(resolve(native: native).vertical == .never)
        // Per axis: the member decides only the axes it names.
        let mixed = resolve(member: config(nil, .visible), twin: config(.hidden, .hidden))
        #expect(mixed.horizontal == .hidden && mixed.vertical == .visible)
        // An explicit `.automatic` is a value, not "unset": it overrides an outer `.hidden`.
        #expect(resolve(member: config(.automatic, .automatic), twin: config(.hidden, .hidden)).vertical == .automatic)
    }

    @Test func neverAndHiddenStayDistinctButDrawTheSame() {
        let r = resolve(member: config(.hidden, .never))
        #expect(r.horizontal == .hidden && r.vertical == .never && r.horizontal != r.vertical)
        #expect(!r.drawsAnything && !r.hasAutomatic)
        #expect(ZTronScrollIndicatorVisibility.hidden != .never)
    }

    @Test func visibleDrawsButIsNeverAutomatic() {
        let r = resolve(member: config(.visible, .hidden))
        #expect(r.drawsAnything && !r.hasAutomatic, "an always-visible thumb has nothing to fade")
    }

    @Test func showsIndicatorsFalseDecidesWhatAutomaticMeans() {
        // The view's own default: hidden. SwiftUI's ScrollView agrees (measured in `NativeIndicatorFixtureTests`).
        #expect(resolve(member: config(shows: false)).vertical == .hidden)
        #expect(resolve(member: config(.automatic, .automatic, shows: false)).vertical == .hidden)
        #expect(resolve(member: config(shows: true)).vertical == .automatic)
        #expect(resolve(member: config(shows: nil)).vertical == .automatic)
        // An explicit value beats it, from the member, the twin or the native environment; per axis.
        #expect(resolve(member: config(.visible, nil, shows: false)).horizontal == .visible)
        #expect(resolve(member: config(.visible, nil, shows: false)).vertical == .hidden)
        #expect(resolve(member: config(shows: false), twin: config(.visible, .visible)).vertical == .visible)
        #expect(resolve(member: config(shows: false), native: AxisPair(horizontal: .visible, vertical: .visible)).vertical == .visible)
        #expect(resolve(member: config(.never, .never, shows: false)).vertical == .never)
        // The init flag lives on the member only; a twin cannot carry one.
        #expect(resolve(twin: config(shows: false)).vertical == .automatic)
    }

    @Test func chromeConfigPairsAndEquality() {
        var pair = AxisPair<V>()
        pair.set(.hidden, axes: .vertical)
        #expect(pair.vertical == .hidden && pair.horizontal == nil)
        pair.set(.visible, axes: [.horizontal, .vertical])
        #expect(pair.horizontal == .visible && pair.vertical == .visible)
        pair.set(nil, axes: .horizontal)
        #expect(pair.horizontal == nil && pair.vertical == .visible)
        #expect(ChromeConfig() == ChromeConfig())
        #expect(config(.hidden, nil) != config(nil, .hidden))
    }

    @Test func anyEquatableComparesTypeAndValue() {
        #expect(AnyEquatable(3) == AnyEquatable(3))
        #expect(AnyEquatable(3) != AnyEquatable(4))
        #expect(AnyEquatable(3) != AnyEquatable("3"), "a different type is a different trigger")
        #expect(AnyEquatable([1, 2]) == AnyEquatable([1, 2]))
        var a = ChromeConfig(), b = ChromeConfig()
        a.flashTrigger = AnyEquatable(1); b.flashTrigger = AnyEquatable(1)
        #expect(a == b)
        b.flashTrigger = AnyEquatable(2)
        #expect(a != b)
    }

    // MARK: SwiftUI mirror (16+, gated at runtime)

    @Test func theMirrorRoundTripsThroughSwiftUIs() {
        guard #available(iOS 16.4, *) else { return }
        for v in [V.automatic, .visible, .hidden, .never] {
            #expect(ZTronScrollIndicatorVisibility(v.native) == v, "\(v)")
        }
        #expect(ZTronScrollIndicatorVisibility(ScrollIndicatorVisibility.hidden) == .hidden)
        #expect(ZTronScrollIndicatorVisibility(ScrollIndicatorVisibility.never) == .never)
        #expect(V.hidden.native == ScrollIndicatorVisibility.hidden && V.never.native == ScrollIndicatorVisibility.never)
        #expect(V.hidden.native != V.never.native)
    }

    @Test func theNativeVisibilityTypeExistsFrom16() {
        guard #available(iOS 16, *) else { return }
        // `.native` needs only the 16.0 statics; the reverse needs `Equatable` (16.4). Below 16.4 the native environment
        // is not read (the resolution gets `nil`).
        _ = ZTronScrollIndicatorVisibility.visible.native
    }

    // MARK: hosted resolution (both OS paths): what the real container draws

    typealias Render = (layout: IndicatorLayout, horizontalOpacity: Double, verticalOpacity: Double)
    struct Hosted { var state: ZTronScrollState; var window: UIWindow; var render: Render? }

    /// A content scrollable on both axes inside the 200 pt window (600 × 1000).
    func hosted<Root: View>(_ path: OSPath, _ view: (ZTronScrollState) -> Root) -> Hosted {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never
        let w = withOSPath(path) { host(view(s)) }
        pump(0.15)
        return Hosted(state: s, window: w, render: s.indicatorController?.lastRender)
    }

    func big() -> some View { Color.red.frame(width: 600, height: 1000) }

    @Test(arguments: OSPath.allCases) func defaultDrawsBothThumbsAtZeroOpacityAtRest(path: OSPath) {
        let h = hosted(path) { s in ZTronScrollView([.horizontal, .vertical], state: s) { big() } }
        #expect(h.render?.layout.horizontal != nil && h.render?.layout.vertical != nil)
        #expect(h.render?.horizontalOpacity == 0 && h.render?.verticalOpacity == 0, "automatic thumbs rest invisible")
        unhost(h.window)
    }

    @Test(arguments: OSPath.allCases) func showsIndicatorsFalseHidesAutomaticThumbs(path: OSPath) {
        let capture = StateCapture()
        let w = withOSPath(path) {
            host(ZTronScrollView([.horizontal, .vertical], showsIndicators: false) { CapturingContent(capture: capture) })
        }
        pump(0.15)
        #expect(capture.state?.indicatorController?.lastRender?.layout == IndicatorLayout(horizontal: nil, vertical: nil))
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func memberVisibleBeatsTheInitFlagPerAxis(path: OSPath) {
        let capture = StateCapture()
        let w = withOSPath(path) {
            host(ZTronScrollView([.horizontal, .vertical], showsIndicators: false) { CapturingContent(capture: capture) }
                .scrollIndicators(.visible, axes: .vertical))
        }
        pump(0.15)
        guard let render = capture.state?.indicatorController?.lastRender else { Issue.record("no indicator render"); return }
        #expect(render.layout.vertical != nil && render.verticalOpacity == 1, "member `.visible` beats `showsIndicators: false`")
        #expect(render.layout.horizontal == nil, "the other axis keeps the init flag's `.hidden`")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func memberBeatsTheTwinPerAxisThroughTheContainer(path: OSPath) {
        var twin = ChromeConfig()
        twin.indicators.set(.hidden, axes: [.horizontal, .vertical])
        let h = hosted(path) { s in
            ZTronScrollView([.horizontal, .vertical], state: s) { big() }
                .scrollIndicators(.visible, axes: .vertical)
                .environment(\.ztronChromeConfig, twin)
        }
        #expect(h.render?.layout.vertical != nil && h.render?.verticalOpacity == 1)
        #expect(h.render?.layout.horizontal == nil, "the twin's `.hidden` still holds where the member is silent")
        unhost(h.window)
    }

    @Test(arguments: OSPath.allCases) func theTwinReachesTheContainer(path: OSPath) {
        let h = hosted(path) { s in
            ZTronScrollView([.horizontal, .vertical], state: s) { big() }.ztronScrollIndicators(.never, axes: .horizontal)
        }
        #expect(h.render?.layout.horizontal == nil && h.render?.layout.vertical != nil)
        unhost(h.window)
    }

    @Test(arguments: OSPath.allCases) func hiddenAndNeverDrawNothingAndWakeNoLeaf(path: OSPath) {
        for v in [V.hidden, .never] {
            let h = hosted(path) { s in
                ZTronScrollView([.horizontal, .vertical], state: s) { big() }.scrollIndicators(v)
            }
            #expect(h.render?.layout == IndicatorLayout(horizontal: nil, vertical: nil), "\(v)")
            ZTronRenderCounters.reset()
            for y in stride(from: 10.0, through: 100.0, by: 10) { h.state.track(offset: CGPoint(x: 0, y: y), zoom: 1); pump(0.02) }
            #expect(ZTronRenderCounters.value("chromeLeaf.body") == 0, "a leaf with nothing to draw subscribes to no channel (\(v))")
            unhost(h.window)
        }
    }

    @Test(arguments: OSPath.allCases) func theNativeEnvironmentAboveIsReadFrom164(path: OSPath) {
        guard #available(iOS 16.4, *) else { return }
        let hidden = hosted(path) { s in
            ZTronScrollView([.horizontal, .vertical], state: s) { big() }.scrollIndicators(ScrollIndicatorVisibility.hidden)
        }
        #expect(hidden.render?.layout == IndicatorLayout(horizontal: nil, vertical: nil), "SwiftUI's own modifier above")
        unhost(hidden.window)
        let visible = hosted(path) { s in
            VStack { ZTronScrollView([.horizontal, .vertical], state: s) { big() } }
                .scrollIndicators(ScrollIndicatorVisibility.visible, axes: .vertical)
        }
        #expect(visible.render?.verticalOpacity == 1 && visible.render?.layout.vertical != nil)
        #expect(visible.render?.horizontalOpacity == 0, "still automatic on the axis the native modifier did not name")
        unhost(visible.window)
    }

    @Test(arguments: OSPath.allCases) func aContentThatFitsDrawsNoThumbEvenWhenVisible(path: OSPath) {
        let h = hosted(path) { s in
            ZTronScrollView([.horizontal, .vertical], state: s) { Color.red.frame(width: 60, height: 60) }
                .scrollIndicators(.visible)
        }
        #expect(h.render?.layout == IndicatorLayout(horizontal: nil, vertical: nil))
        unhost(h.window)
    }
}

/// Reaches the state a `ZTronScrollView` created for itself (`init(_:showsIndicators:content:)`): the container writes
/// it into the environment below itself.
@MainActor
final class StateCapture { var state: ZTronScrollState? }

struct CapturingContent: View {
    let capture: StateCapture
    @Environment(\.ztronScrollState) private var state
    var body: some View {
        capture.state = state
        return Color.red.frame(width: 600, height: 1000)
    }
}
