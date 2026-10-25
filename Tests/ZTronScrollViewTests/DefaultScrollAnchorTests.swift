import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

/// `defaultScrollAnchor` roles, the twins and the SwiftUI conversions (M6 session 3, tests 9, 10 and 11).
@MainActor
@Suite(.serialized)
struct DefaultScrollAnchorTests {
    static let metrics = ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900), displayScale: 2)

    // MARK: 9 · roles on the state

    @Test(arguments: OSPath.allCases) func initialOffsetBottomStartsAtTheMaximumOnceAtTheFirstLayout(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.initialOffsetAnchor = .bottom
        s.setViewport(ViewportMetrics(size: CGSize(width: 100, height: 200), safeArea: EdgeInsets()))
        #expect(s.peek.presentationOffset == .zero)                                  // no content yet
        s.setContentSize(CGSize(width: 300, height: 900))
        #expect(s.peek.presentationOffset == CGPoint(x: 0, y: 700))                  // the vertical axis only
        s.track(offset: CGPoint(x: 0, y: 100), zoom: 1)
        s.setContentSize(CGSize(width: 300, height: 1500))
        #expect(s.peek.presentationOffset.y != 1300 || false)                         // not applied again
        #expect(abs(s.peek.presentationOffset.y - 100) < 1e-6 || s.peek.presentationOffset.y == 100)
    }

    @Test(arguments: OSPath.allCases) func initialOffsetUsesEveryScrollableAxisAndTheInsets(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.scrollAxes = [.horizontal, .vertical]
        s.initialOffsetAnchor = .center
        var m = Self.metrics
        m.contentInset = EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0)
        s.setMetrics(m)
        // bounds x 0...200, y -20...700: the center of each.
        #expect(s.peek.presentationOffset == CGPoint(x: 100, y: 340))
    }

    @Test(arguments: OSPath.allCases) func noInitialAnchorLeavesTheOffsetAlone(path: OSPath) {
        let s = makeState(path)
        s.setMetrics(Self.metrics)
        #expect(s.peek.presentationOffset == .zero)
    }

    @Test(arguments: OSPath.allCases) func alignmentCentersSmallContentAndFeedsTheGeometry(path: OSPath) {
        let s = makeState(path)
        #expect(s.contentAlignment == .topLeading)
        s.alignmentAnchor = .center
        #expect(s.contentAlignment == .center)
        s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 50, height: 50), displayScale: 2))
        let g = s.makeZoomGeometry()
        #expect(g.x.alignment == 0.5 && g.y.alignment == 0.5)
        #expect(g.x.alignmentPadding(at: 1) == 25 && g.y.alignmentPadding(at: 1) == 75)
        s.alignmentAnchor = .bottomTrailing
        #expect(s.makeZoomGeometry().y.alignmentPadding(at: 1) == 150)
    }

    @Test(arguments: OSPath.allCases) func alignmentIsTheViewAlignedAnchor(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.setMetrics(Self.metrics)
        for i in 0..<9 { s.targets.register(i, frame: CGRect(x: 0, y: CGFloat(i) * 100, width: 300, height: 100)) }
        s.alignmentAnchor = .center
        s.targetBehavior = AnyZTronScrollTargetBehavior(ZTronViewAlignedScrollTargetBehavior(limitBehavior: .never))
        s.track(offset: CGPoint(x: 0, y: 300), zoom: 1)
        s.beginTracking(); s.beginDragging()
        var t = PointVelocityTracker()
        for i in 0...8 {
            let time = 100 - 0.12 + Double(i) * 0.015
            t.add(CGPoint(x: 0, y: -600 * CGFloat(time - (100 - 0.12))), at: time)
        }
        s.endDrag(ReleaseRequest(origin: CGPoint(x: 0, y: 300), dragStart: CGPoint(x: 0, y: 300), liftTime: 100, fallbackVelocity: nil),
                  tracker: t, env: PanSessionTests.env(), settings: ReleaseSettings())
        var now = 100.0
        while s.isClockRunning && now < 130 { now += 1.0 / 60; s.step(to: Date(timeIntervalSinceReferenceDate: now)) }
        // The item's center meets the container's: offsets 50, 150, … (cell k at 100k + 50 - 100).
        let y = s.peek.presentationOffset.y
        #expect(abs((y + 50).truncatingRemainder(dividingBy: 100)) < 0.5 || y == 700 || y == 0, "landed at \(y)")
    }

    // MARK: PARITY-s1 · content-size changes follow SwiftUI's rule (measured next to a native ScrollView)

    func contentSize(_ s: ZTronScrollState, _ height: CGFloat) { s.setContentSize(CGSize(width: 300, height: height)) }

    @Test(arguments: OSPath.allCases) func theInitialAnchorHoldsUntilTheViewIsFirstMoved(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.initialOffsetAnchor = .bottom
        s.setMetrics(Self.metrics)
        #expect(s.peek.presentationOffset.y == 700)
        contentSize(s, 1032)                                                          // native: 4250 → 4382 after three rows
        #expect(s.peek.presentationOffset.y == 832)
        contentSize(s, 900)
        #expect(s.peek.presentationOffset.y == 700)
        s.setContentOffset(CGPoint(x: 0, y: 700), animated: false)                  // any command, even to where it is
        contentSize(s, 1032)
        #expect(s.peek.presentationOffset.y == 700)                                  // kept from now on
    }

    @Test(arguments: OSPath.allCases) func aSizeChangesAnchorHoldsAnAxisThatSitsAtItsAnchoredPosition(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.sizeChangesAnchor = .bottom
        s.setMetrics(Self.metrics)
        contentSize(s, 1032)
        #expect(s.peek.presentationOffset.y == 0)                                    // at the top, not at the bottom: kept
        s.setContentOffset(CGPoint(x: 0, y: 832), animated: false)
        contentSize(s, 1164)
        #expect(s.peek.presentationOffset.y == 964)                                  // at the bottom: stays at the bottom
        s.setContentOffset(CGPoint(x: 0, y: 400), animated: false)
        contentSize(s, 1296)
        #expect(s.peek.presentationOffset.y == 400)                                  // in between: kept (content above shifts nothing)
        s.sizeChangesAnchor = .center
        s.setContentOffset(CGPoint(x: 0, y: 548), animated: false)                   // (1296 − 200) / 2
        contentSize(s, 1428)
        #expect(s.peek.presentationOffset.y == 614)                                  // native: 2125 → 2191
    }

    @Test(arguments: OSPath.allCases) func contentThatFittedGrowsFromItsAlignmentAnchor(path: OSPath) {
        for (anchor, expected) in [(UnitPoint?.some(.bottom), CGFloat(300)), (.center, 150), (nil, 0)] {
            let s = makeState(path)
            s.now = { 100 }
            s.alignmentAnchor = anchor
            s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 100, height: 88),
                                       displayScale: 2))
            s.setContentOffset(.zero, animated: false)
            contentSize(s, 500)                                                       // native rows 2 → 5: bottom 70, center 35
            #expect(s.peek.presentationOffset.y == expected, "\(String(describing: anchor))")
        }
    }

    @Test(arguments: OSPath.allCases) func withoutAnchorsAContentChangeKeepsTheOffset(path: OSPath) {
        let s = makeState(path)
        s.now = { 100 }
        s.setMetrics(Self.metrics)
        s.setContentOffset(CGPoint(x: 0, y: 700), animated: false)
        contentSize(s, 1032)
        #expect(s.peek.presentationOffset.y == 700)                                  // native: no pin without an anchor
        contentSize(s, 600)
        #expect(s.peek.presentationOffset.y == 400)                                  // clamped
    }

    // MARK: 10 · member, twin, precedence (hosted)

    struct Probe: View {
        let state: ZTronScrollState
        var memberBottomForAlignment = false
        var body: some View {
            if memberBottomForAlignment {
                ZTronScrollView(.vertical, state: state) { Color.red.frame(height: 400) }
                    .defaultScrollAnchor(.bottom, for: .alignment)
            } else {
                ZTronScrollView(.vertical, state: state) { Color.red.frame(height: 400) }
            }
        }
    }

    @Test(arguments: OSPath.allCases) func theTwinAboveReachesTheStateAndTheMemberWins(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(Probe(state: s, memberBottomForAlignment: true)
                .ztronDefaultScrollAnchor(.leading, for: .sizeChanges)
                .ztronDefaultScrollAnchor(.top))
        }
        pump(0.2)
        #expect(s.initialOffsetAnchor == .top)                                       // the twin's
        #expect(s.alignmentAnchor == .bottom)                                        // the member beats the twin
        #expect(s.sizeChangesAnchor == .leading)                                     // the inner twin, for its role only
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theMemberSetsAllRolesAndTheRoleOverloadOne(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { Color.red.frame(height: 400) }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.center, for: .sizeChanges))
        }
        pump(0.2)
        #expect(s.initialOffsetAnchor == .bottom && s.alignmentAnchor == .bottom && s.sizeChangesAnchor == .center)
        unhost(w)
    }

    // MARK: 11 · conversions

    @Test func anchorRolesRoundTrip() {
        guard #available(iOS 18, *) else { return }
        for role in ZTronScrollAnchorRole.allCases {
            #expect(ZTronScrollAnchorRole(role.native) == role)
        }
        #expect(ZTronScrollAnchorRole.allCases.count == 3)
    }

    @Test func positionsConvertBothWays() {
        guard #available(iOS 18, *) else { return }
        let id = ZTronScrollPosition(ScrollPosition(id: 3, anchor: .center))
        #expect(id.viewID(type: Int.self) == 3 && id.point == nil && id.edge == nil && !id.isPositionedByUser)
        #expect(ZTronScrollPosition(id: 3).native.viewID.map { AnyHashable($0) } == AnyHashable(3))     // erased like SwiftUI erases ids
        #expect(ZTronScrollPosition(ScrollPosition(point: CGPoint(x: 1, y: 2))).point == CGPoint(x: 1, y: 2))
        #expect(ZTronScrollPosition(point: CGPoint(x: 1, y: 2)).native.point == CGPoint(x: 1, y: 2))
        #expect(ZTronScrollPosition(ScrollPosition(edge: .bottom)).edge == .bottom)
        #expect(ZTronScrollPosition(edge: .trailing).native.edge == .trailing)
        #expect(ZTronScrollPosition(ScrollPosition()).viewID == nil && ZTronScrollPosition(ScrollPosition()) .point == nil)
        // One axis keeps the axis: SwiftUI's position has no `x` / `y` accessors, only the point it resolves to.
        _ = ZTronScrollPosition(x: 4).native
        _ = ZTronScrollPosition(y: 5).native
        _ = ZTronScrollPosition(x: 4, y: 5).native
        // `isPositionedByUser` is get-only on SwiftUI's side: ours carries it in, never out.
        var user = ZTronScrollPosition(id: 1)
        user = user.positioned(by: .id(AnyHashable(2), nil), serial: user.serial)
        #expect(user.isPositionedByUser && !user.native.isPositionedByUser)
        #expect(ZTronScrollPosition(id: 7) != ZTronScrollPosition(id: 7))            // a new request is a new value
        // PARITY-s1: a Sendable id reaches SwiftUI with its own type (SwiftUI matches views by it), equal to SwiftUI's own value.
        #expect(ZTronScrollPosition(id: 3, anchor: .center).native == ScrollPosition(id: 3, anchor: .center))
        if #available(iOS 26, *) {
            #expect(ZTronScrollPosition(ScrollPosition(y: 5)).y == 5)                 // 26 reads one-axis requests back
            #expect(ZTronScrollPosition(ScrollPosition(x: 4)).x == 4)
        }
    }

    final class NativeModel: ObservableObject {
        @Published var position = ZTronScrollPosition() { didSet { writes += 1 } }
        @Published var id: Int?
        var writes = 0
    }

    @Test(arguments: OSPath.allCases) func theTwinDrivesANativeScrollView(path: OSPath) {
        guard #available(iOS 18, *) else { return }
        let model = NativeModel()
        struct Native: View {
            @ObservedObject var model: NativeModel
            var body: some View {
                ScrollView {
                    VStack(spacing: 0) { ForEach(0..<20, id: \.self) { i in Color.red.frame(height: 100).id(i) } }.scrollTargetLayout()
                }
                .ztronScrollPosition($model.position)
            }
        }
        let w = withOSPath(path) { host(Native(model: model)) }
        pump(0.3)
        guard let root = w.rootViewController?.view, let sv = firstScrollView(in: root) else { Issue.record("no UIScrollView"); return }
        let top = sv.contentOffset.y
        model.position = ZTronScrollPosition(edge: .bottom)
        pump(0.5)
        #expect(sv.contentOffset.y > top + 1000, "offset \(sv.contentOffset.y)")
        // PARITY-s1: an id request reaches the native view (it never did through an `AnyHashable` wrapper), a point is in
        // content space (it lands at the top of the unobscured area), and SwiftUI's echo of a request is not written back.
        let writes = model.writes
        model.position = ZTronScrollPosition(id: 7, anchor: .top)
        pump(0.5)
        #expect(abs(sv.contentOffset.y + sv.adjustedContentInset.top - 700) < 0.5, "id 7: \(sv.contentOffset.y)")
        model.position = ZTronScrollPosition(point: CGPoint(x: 0, y: 300))
        pump(0.5)
        #expect(abs(sv.contentOffset.y + sv.adjustedContentInset.top - 300) < 0.5, "point: \(sv.contentOffset.y)")
        #expect(model.writes == writes + 2, "writes \(model.writes - writes)")
        unhost(w)
    }
}
