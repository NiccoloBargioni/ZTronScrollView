import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

@MainActor
final class ConfigBox { var config = ChromeConfig() }

struct EnvironmentProbe: View {
    let box: ConfigBox
    @Environment(\.ztronChromeConfig) private var config
    var body: some View {
        box.config = config
        return Color.clear
    }
}

/// M8-1 (design M8 §1, §2): the member + twin shape of the indicator modifiers — what each spelling stores, how the
/// twin reaches the environment and native scroll views, and the state's indicator API.
@MainActor
@Suite(.serialized)
struct IndicatorModifierTests {
    // MARK: members

    @Test func membersReturnTheViewAndStoreTheirSettings() {
        let v: ZTronScrollView<Color> = ZTronScrollView(.vertical, showsIndicators: false) { Color.red }
            .scrollIndicators(.hidden, axes: .horizontal)
            .scrollIndicators(.visible, axes: .vertical)
            .scrollIndicatorsFlash(onAppear: true)
            .scrollIndicatorsFlash(trigger: 7)
        #expect(v.chrome.indicators == AxisPair(horizontal: .hidden, vertical: .visible))
        #expect(v.chrome.showsIndicators == false && v.chrome.flashOnAppear == true && v.chrome.flashTrigger == AnyEquatable(7))
    }

    @Test func theDefaultAxesAreBothAndALaterCallWinsPerAxis() {
        let both: ZTronScrollView<Color> = ZTronScrollView { Color.red }.scrollIndicators(.never)
        #expect(both.chrome.indicators == AxisPair(horizontal: .never, vertical: .never))
        let later = both.scrollIndicators(.automatic, axes: .vertical)
        #expect(later.chrome.indicators == AxisPair(horizontal: .never, vertical: .automatic))
    }

    @Test func theInitFlagTrueSaysNothingAndMembersChainWithTheOthers() {
        let v: ZTronScrollView<Color> = ZTronScrollView([.horizontal, .vertical]) { Color.red }
            .zoomRange(min: .absolute(1), max: .absolute(4))
            .scrollIndicators(.hidden)
            .doubleTapToZoom()
        #expect(v.chrome.showsIndicators == nil)
        #expect(ZTronScrollView(state: ZTronScrollState()) { Color.red }.chrome.showsIndicators == nil)
    }

    // MARK: twins

    @Test func twinsWriteTheEnvironmentAndTheInnerOneWinsPerAxis() {
        let box = ConfigBox()
        let w = host(EnvironmentProbe(box: box)
            .ztronScrollIndicators(.visible, axes: .vertical)
            .ztronScrollIndicators(.hidden)
            .ztronScrollIndicatorsFlash(onAppear: true)
            .ztronScrollIndicatorsFlash(trigger: 3))
        #expect(box.config.indicators == AxisPair(horizontal: .hidden, vertical: .visible))
        #expect(box.config.flashOnAppear == true && box.config.flashTrigger == AnyEquatable(3))
        unhost(w)
    }

    @Test func aViewWithoutTwinsSeesTheEmptyConfiguration() {
        let box = ConfigBox()
        let w = host(EnvironmentProbe(box: box))
        #expect(box.config == ChromeConfig())
        unhost(w)
    }

    func nativeIndicator<V: View>(_ view: V) -> (vertical: Bool, horizontal: Bool)? {
        let w = host(view)
        pump(0.3)
        defer { unhost(w) }
        guard let root = w.rootViewController?.view, let sv = firstScrollView(in: root) else { return nil }
        return (sv.showsVerticalScrollIndicator, sv.showsHorizontalScrollIndicator)
    }

    @Test func theTwinAlsoConfiguresNativeScrollViewsFrom16() {
        guard #available(iOS 16, *) else { return }
        let hidden = nativeIndicator(ScrollView { Color.red.frame(height: 1000) }.ztronScrollIndicators(.hidden))
        #expect(hidden?.vertical == false, "SwiftUI's own modifier was applied")
        let visible = nativeIndicator(ScrollView(showsIndicators: false) { Color.red.frame(height: 1000) }.ztronScrollIndicators(.visible))
        #expect(visible?.vertical == true)
        let perAxis = nativeIndicator(ScrollView([.vertical, .horizontal]) { Color.red.frame(width: 1000, height: 1000) }
            .ztronScrollIndicators(.never, axes: .vertical))
        #expect(perAxis?.vertical == false && perAxis?.horizontal == true)
    }

    @Test func theFlashTwinsComposeWithNativeScrollViews() {
        // SwiftUI's flash modifiers (17+) are applied under #available; nothing observable from UIKit, but they must not
        // disturb the scroll view.
        let v = nativeIndicator(ScrollView { Color.red.frame(height: 1000) }
            .ztronScrollIndicatorsFlash(onAppear: true).ztronScrollIndicatorsFlash(trigger: 1))
        #expect(v?.vertical == true)
    }

    // MARK: state API

    @Test(arguments: OSPath.allCases) func indicatorInsetsRoundTripThroughTheMetrics(path: OSPath) {
        let s = makeState(path)
        #expect(s.scrollIndicatorInsets == EdgeInsets())
        let insets = EdgeInsets(top: 5, leading: 1, bottom: 7, trailing: 2)
        s.setContentSize(CGSize(width: 390, height: 3000))
        let before = s.peek.metrics
        s.scrollIndicatorInsets = insets
        #expect(s.scrollIndicatorInsets == insets && s.peek.metrics.indicatorInsets == insets)
        var expected = before
        expected.indicatorInsets = insets
        #expect(s.peek.metrics == expected, "nothing else in the metrics moved (no resize, no offset write)")
        s.scrollIndicatorInsets = EdgeInsets()
        #expect(s.peek.metrics == before)
    }

    @Test(arguments: OSPath.allCases) func flashingWithoutAViewIsHarmless(path: OSPath) {
        let s = makeState(path)
        s.flashScrollIndicators()
        #expect(s.indicatorController == nil)
    }
}
