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
    }

    final class NativeModel: ObservableObject {
        @Published var position = ZTronScrollPosition()
        @Published var id: Int?
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
        unhost(w)
    }
}
