import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// M8-1: the native fixture the visibility resolution is held against. A hosted SwiftUI `ScrollView` is configured with
/// `showsIndicators:` and `scrollIndicators(_:)` and the `UIScrollView` behind it is read (public UIKit API), exactly as
/// the M6 target fixtures do. Measured on iOS 17.5 and 27.0 (2026-10-20): `showsIndicators: false` only decides what
/// `.automatic` means; an explicit `.visible` (on the view or on a parent) beats it, `.hidden` / `.never` hide.
@MainActor
@Suite(.serialized)
struct NativeIndicatorFixtureTests {
    @available(iOS 16, *)
    func nativeShowsVertical(initFlag: Bool, _ visibility: ScrollIndicatorVisibility?) -> Bool? {
        let w: UIWindow
        if let visibility {
            w = host(ScrollView(showsIndicators: initFlag) { Color.red.frame(height: 1000) }.scrollIndicators(visibility))
        } else {
            w = host(ScrollView(showsIndicators: initFlag) { Color.red.frame(height: 1000) })
        }
        pump(0.3)
        defer { unhost(w) }
        guard let root = w.rootViewController?.view, let sv = firstScrollView(in: root) else { return nil }
        return sv.showsVerticalScrollIndicator
    }

    typealias V = ZTronScrollIndicatorVisibility

    /// Ours, for the same configuration: does the vertical axis draw?
    func oursDraws(initFlag: Bool, _ visibility: V?) -> Bool {
        var member = ChromeConfig()
        member.indicators.set(visibility, axes: .vertical)
        member.showsIndicators = initFlag ? nil : false
        let r = IndicatorResolution.resolve(member: member, twin: ChromeConfig(), native: nil)
        return r.draws(r.vertical)
    }

    @Test func theLibraryResolvesEveryInitFlagAndVisibilityLikeAHostedScrollView() {
        guard #available(iOS 16, *) else { return }
        let rows: [(V?, ScrollIndicatorVisibility?)] = [
            (nil, nil), (.automatic, .automatic), (.visible, .visible), (.hidden, .hidden), (.never, .never),
        ]
        for flag in [true, false] {
            for (ours, native) in rows {
                let expected = nativeShowsVertical(initFlag: flag, native)
                #expect(expected != nil, "no UIScrollView behind the hosted ScrollView")
                #expect(oursDraws(initFlag: flag, ours) == expected, "showsIndicators: \(flag), scrollIndicators: \(String(describing: ours))")
            }
        }
    }

    @Test func theMeasuredFacts() {
        guard #available(iOS 16, *) else { return }
        #expect(nativeShowsVertical(initFlag: true, nil) == true)
        #expect(nativeShowsVertical(initFlag: false, nil) == false)
        #expect(nativeShowsVertical(initFlag: false, .visible) == true, "an explicit .visible beats showsIndicators: false")
        #expect(nativeShowsVertical(initFlag: false, .automatic) == false, ".automatic defers to the flag")
        #expect(nativeShowsVertical(initFlag: true, .hidden) == false && nativeShowsVertical(initFlag: true, .never) == false)
    }

    @Test func aParentsVisibleAlsoBeatsTheFlagAsATwinDoes() {
        guard #available(iOS 16, *) else { return }
        let w = host(VStack { ScrollView(showsIndicators: false) { Color.red.frame(height: 1000) } }.scrollIndicators(.visible))
        pump(0.3)
        defer { unhost(w) }
        guard let root = w.rootViewController?.view, let sv = firstScrollView(in: root) else { Issue.record("no UIScrollView"); return }
        #expect(sv.showsVerticalScrollIndicator, "native: parent .visible beats the flag")
        var member = ChromeConfig(), twin = ChromeConfig()
        member.showsIndicators = false
        twin.indicators.set(.visible, axes: .vertical)
        #expect(IndicatorResolution.resolve(member: member, twin: twin, native: nil).vertical == .visible, "ours: twin .visible beats the flag")
    }

    @Test func perAxisModifiersLeaveTheOtherAxisToTheFlag() {
        guard #available(iOS 16, *) else { return }
        let w = host(ScrollView([.vertical, .horizontal], showsIndicators: false) { Color.red.frame(width: 1000, height: 1000) }
            .scrollIndicators(.visible, axes: .horizontal))
        pump(0.3)
        defer { unhost(w) }
        guard let root = w.rootViewController?.view, let sv = firstScrollView(in: root) else { Issue.record("no UIScrollView"); return }
        #expect(sv.showsHorizontalScrollIndicator && !sv.showsVerticalScrollIndicator)
        var member = ChromeConfig()
        member.showsIndicators = false
        member.indicators.set(.visible, axes: .horizontal)
        let r = IndicatorResolution.resolve(member: member, twin: ChromeConfig(), native: nil)
        #expect(r.horizontal == .visible && r.vertical == .hidden)
    }
}
