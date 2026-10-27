import SwiftUI
import Testing
@testable import ZTronScrollView

/// Design M8b §3 tests 10 and 13: the live header height counts onto the unobscured top for the scroll indicators, the
/// `scrollTo` anchors (at the target) and the refresh indicator (under `.preserve` in the gap below the still header with
/// `.openGap`, D65, or above the moved header with `.followContent`, D61; over the stretched band under `.stretch`), with a
/// refresh hold.
@MainActor
@Suite(.serialized)
struct HeaderInsetConsumerTests {
    func make(_ path: OSPath, behavior: ZTronHeaderScalingBehavior = .preserve,
              pull: ZTronHeaderPullBehavior = .openGap) -> ZTronScrollState {
        let s = makeState(path)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 402, height: 874), contentSize: CGSize(width: 402, height: 3000),
                                   safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), displayScale: 3))
        s.track(offset: CGPoint(x: 0, y: -s.adjustedContentInset.top), zoom: 1)
        s.headerSpec = HeaderSizing(size: .fixed(min: 64, max: 240), behavior: behavior, snap: .disabled, pull: pull)
        s.headerSpecChanged()
        return s
    }

    func scroll(_ s: ZTronScrollState, oPrime x: CGFloat) {
        s.track(offset: CGPoint(x: 0, y: x - HeaderMath.base(s.peek.metrics)), zoom: 1)
    }

    func oPrime(_ s: ZTronScrollState) -> CGFloat {
        let p = s.peek
        return HeaderMath.headerOffset(offset: p.presentationOffset, zoom: p.presentationZoom, metrics: p.metrics)
    }

    @Test(arguments: OSPath.allCases) func theIndicatorTrackStartsBelowTheLiveHeader(path: OSPath) {
        let s = make(path)
        func trackTop() -> CGFloat {
            let p = s.peek
            return IndicatorMath.trackInsets(p.metrics, extra: EdgeInsets(), header: HeaderMath.obscuredDelta(
                offset: p.presentationOffset, zoom: p.presentationZoom, metrics: p.metrics)).top
        }
        #expect(trackTop() == 302)
        scroll(s, oPrime: 100)
        #expect(trackTop() == 202)
        scroll(s, oPrime: 900)
        #expect(trackTop() == 126)
    }

    @Test(arguments: OSPath.allCases) func scrollToEvaluatesTheHeaderAtTheTarget(path: OSPath) {
        let s = make(path)
        s.targets.register("first", frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        s.targets.register("deep", frame: CGRect(x: 0, y: 1200, width: 402, height: 44))
        s.targets.register("near", frame: CGRect(x: 0, y: 300, width: 402, height: 44))
        scroll(s, oPrime: 600)
        s.scrollTo(id: AnyHashable("first"), anchor: .top, animation: nil, ambient: false)
        #expect(oPrime(s) == 0, "the first item at the top: back to rest, the header expanded")
        s.scrollTo(id: AnyHashable("deep"), anchor: .top, animation: nil, ambient: false)
        #expect(oPrime(s) == 1376, "below the collapsed header (min 64), not below the resting one")
        let itemTop = 1200 - s.contentOffset.y
        #expect(itemTop == 126, "the item's top meets the header's live bottom")
        s.scrollTo(id: AnyHashable("near"), anchor: .center, animation: nil, ambient: false)
        let p = s.peek
        let h = HeaderMath.height(o: oPrime(s), m: p.metrics.header!)
        let unobscuredTop = 62 + h, unobscuredBottom: CGFloat = 874 - 34
        let itemCentre = 300 + 22 - p.presentationOffset.y
        #expect(abs(itemCentre - (unobscuredTop + unobscuredBottom) / 2) < 0.01, "centred in the area below the header at the target")
    }

    @Test(arguments: OSPath.allCases) func aStretchedHeaderGrowsByTheHoldAndTheIndicatorFloatsOverTheBand(path: OSPath) {
        let s = make(path, behavior: .stretch)
        s.setRefreshHold(EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0), followsOffset: true)
        let m = s.peek.metrics
        #expect(oPrime(s) == -60 && s.headerGeometry?.height == 300, "h == R + H while refreshing at rest")
        let (base, overlay) = RefreshIndicatorMath.base(edge: .top, metrics: m, overlay: false)
        #expect(overlay && base.top == 302, "overlay placement over the band, whatever overlay: says")
        let placement = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: overlay, refreshing: true, dragPosition: 1,
                                                       pull: 60, length: 60, viewport: m.viewportSize, base: base)!
        #expect(placement.frame.minY == 302 && placement.frame.maxY == 362, "centred over the stretched band")
        #expect(placement.visibleLength(vertical: true) == 60)
    }

    /// D61 (`.followContent`): the `.preserve` header moves down with the hold (height R), the gap opens ABOVE it and the
    /// indicator sits there, `[top0, top0 + H]`; the header's bottom edge stays on the content's top.
    @Test(arguments: OSPath.allCases) func aFollowingHeaderMovesDownWithTheHoldAndTheIndicatorSitsAboveIt(path: OSPath) {
        let s = make(path, pull: .followContent)
        s.setRefreshHold(EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0), followsOffset: true)
        let m = s.peek.metrics
        #expect(oPrime(s) == -60 && s.headerGeometry?.height == 240)
        #expect(HeaderMath.gapAbove(o: -60, m: m.header!) == 60 && HeaderMath.translation(o: -60, m: m.header!) == 60)
        let (base, overlay) = RefreshIndicatorMath.base(edge: .top, metrics: m, overlay: false)
        #expect(!overlay && base.top == 62, "the base is the header slot's top (top0)")
        let placement = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: true, dragPosition: 1,
                                                       pull: 60, length: 60, viewport: m.viewportSize, base: base)!
        #expect(placement.frame.minY == 62 && placement.clip.minY == 62 && placement.clip.maxY == 122,
                "in the gap above the header")
        let headerTop: CGFloat = 62 + 60, headerBottom = headerTop + 240
        let content = 0 - s.contentOffset.y
        #expect(content == 362 && content == headerBottom, "the header's bottom edge is the content's top")
        #expect(placement.clip.maxY == headerTop, "the gap ends at the header's top edge")
        #expect(HeaderMath.refreshTop(m)?.overlay == false, "the base stays (top0) in a resize: baseFollowsInset false")
    }

    /// D65 (`.openGap`, the default; pre-D61): the `.preserve` header stays still at its resting place and height under the
    /// hold, the gap opens BELOW it and the indicator sits there at the plain refresh base (`aci.top − hold`, the resting
    /// header's bottom edge), `[top0 + R, top0 + R + H]`; the content's top is the header's bottom + H; the base follows
    /// the adjusted inset in a resize (no header case); the scroll indicators' track starts at the header's bottom edge.
    @Test(arguments: OSPath.allCases) func anOpenGapHeaderStaysStillAndTheIndicatorSitsBelowIt(path: OSPath) {
        let s = make(path)
        s.setRefreshHold(EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0), followsOffset: true)
        let m = s.peek.metrics
        #expect(m.header?.pull == .openGap)
        #expect(oPrime(s) == -60 && s.headerGeometry?.height == 240 && s.headerGeometry?.stretch == 0)
        #expect(HeaderMath.gapAbove(o: -60, m: m.header!) == 0 && HeaderMath.translation(o: -60, m: m.header!) == 0)
        #expect(HeaderMath.gapBelow(o: -60, m: m.header!) == 60)
        #expect(HeaderMath.refreshTop(m) == nil, "the plain base")
        let (base, overlay) = RefreshIndicatorMath.base(edge: .top, metrics: m, overlay: false)
        #expect(!overlay && base.top == 302, "aci.top − hold: the resting header's bottom edge (top0 + R)")
        let placement = RefreshIndicatorMath.placement(edge: .top, style: .system, overlay: false, refreshing: true, dragPosition: 1,
                                                       pull: 60, length: 60, viewport: m.viewportSize, base: base)!
        let headerTop: CGFloat = 62, headerBottom = headerTop + 240
        let content = 0 - s.contentOffset.y
        #expect(content == 362 && content == headerBottom + 60, "the gap H between the header's bottom and the content's top")
        #expect(placement.frame.minY == headerBottom && placement.clip.minY == headerBottom && placement.clip.maxY == content,
                "in the gap below the header: \(placement)")
        let track = IndicatorMath.trackInsets(m, extra: EdgeInsets(), header: HeaderMath.obscuredDelta(
            offset: s.peek.presentationOffset, zoom: 1, metrics: m)).top
        #expect(track == headerBottom, "the scroll indicators' track starts at the still header's bottom (\(track))")
        // A pull on top of the hold (rubber band past it): the header still does not move, the gap grows.
        scroll(s, oPrime: -100)
        #expect(HeaderMath.translation(o: oPrime(s), m: s.peek.metrics.header!) == 0 && s.headerGeometry?.height == 240)
        #expect(RefreshIndicatorMath.base(edge: .top, metrics: s.peek.metrics, overlay: false).0.top == 302)
    }

    /// The same container in both modes away from a pull: collapse and scrolling are identical (`gapAbove` / `gapBelow`
    /// are 0 for `o′ ≥ 0`), the track starts below the live header.
    @Test(arguments: OSPath.allCases, [ZTronHeaderPullBehavior.openGap, .followContent])
    func bothModesCollapseAlike(path: OSPath, pull: ZTronHeaderPullBehavior) {
        let s = make(path, pull: pull)
        for (o, top) in [(0, 302), (100, 202), (900, 126)] as [(CGFloat, CGFloat)] {
            scroll(s, oPrime: o)
            let p = s.peek
            let track = IndicatorMath.trackInsets(p.metrics, extra: EdgeInsets(), header: HeaderMath.obscuredDelta(
                offset: p.presentationOffset, zoom: p.presentationZoom, metrics: p.metrics)).top
            #expect(track == top, "\(path) \(pull) o′ \(o): track \(track)")
            #expect(HeaderMath.gapAbove(o: o, m: p.metrics.header!) == 0 && HeaderMath.gapBelow(o: o, m: p.metrics.header!) == 0)
        }
    }

    @Test(arguments: OSPath.allCases) func theOtherEdgesIgnoreTheHeader(path: OSPath) {
        let s = make(path, behavior: .stretch)
        let m = s.peek.metrics
        #expect(RefreshIndicatorMath.base(edge: .bottom, metrics: m, overlay: false).1 == false)
        #expect(RefreshIndicatorMath.base(edge: .bottom, metrics: m, overlay: false).0.bottom == 34)
    }
}
