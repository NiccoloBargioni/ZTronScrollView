import Foundation
import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

struct SnapTo: ZTronScrollTargetBehavior {
    var value: CGFloat = 0
    @MainActor func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext) { target.rect.origin.y = value }
}

@MainActor
final class BehaviorModel: ObservableObject {
    @Published var usePaging = true
}

/// M6 session 1, tests 10 and 11: the member / twin pair for `scrollTargetBehavior`, and the 17+ conversions.
@MainActor
@Suite(.serialized)
struct ScrollConfigTwinTests {
    struct Tall: View { var body: some View { Color.red.frame(height: 800) } }

    private func scroller(_ state: ZTronScrollState) -> ZTronScrollView<Tall> {
        ZTronScrollView(.vertical, state: state) { Tall() }
    }

    // MARK: twin and member

    @Test(arguments: OSPath.allCases) func aValueAboveTheViewReachesTheState(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) { host(scroller(s).ztronScrollTargetBehavior(.paging)) }
        #expect(s.targetBehavior?.base is ZTronPagingScrollTargetBehavior)
        #expect(s.effectiveTargetBehavior?.base is ZTronPagingScrollTargetBehavior)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theValueAppliesToEveryScrollViewBelow(path: OSPath) {
        let a = makeState(path), b = makeState(path)
        let w = withOSPath(path) {
            host(VStack(spacing: 0) { scroller(a).frame(height: 100); scroller(b).frame(height: 100) }
                .ztronScrollTargetBehavior(SnapTo(value: 40)))
        }
        #expect((a.targetBehavior?.base as? SnapTo)?.value == 40 && (b.targetBehavior?.base as? SnapTo)?.value == 40)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theMemberWinsOverTheTwin(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(scroller(s).scrollTargetBehavior(SnapTo(value: 7)).ztronScrollTargetBehavior(.paging))
        }
        #expect((s.targetBehavior?.base as? SnapTo)?.value == 7)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theNearestTwinWins(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(scroller(s).ztronScrollTargetBehavior(SnapTo(value: 3)).ztronScrollTargetBehavior(.paging))
        }
        #expect((s.targetBehavior?.base as? SnapTo)?.value == 3)         // the one applied first, closest to the view
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func withoutAnyValueTheKnobIsTheOnlyPaging(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) { host(scroller(s)) }
        #expect(s.targetBehavior == nil && s.effectiveTargetBehavior == nil)
        s.isPagingEnabled = true
        #expect(s.effectiveTargetBehavior?.base is ZTronPagingScrollTargetBehavior)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func changingTheValueUpdatesTheState(path: OSPath) {
        struct Host: View {
            let state: ZTronScrollState
            @ObservedObject var model: BehaviorModel
            var body: some View {
                if model.usePaging {
                    ZTronScrollView(.vertical, state: state) { Color.red.frame(height: 800) }.ztronScrollTargetBehavior(.paging)
                } else {
                    ZTronScrollView(.vertical, state: state) { Color.red.frame(height: 800) }.ztronScrollTargetBehavior(SnapTo(value: 9))
                }
            }
        }
        let s = makeState(path), model = BehaviorModel()
        let w = withOSPath(path) { host(Host(state: s, model: model)) }
        #expect(s.targetBehavior?.base is ZTronPagingScrollTargetBehavior)
        model.usePaging = false
        pump(0.2)
        #expect((s.targetBehavior?.base as? SnapTo)?.value == 9)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theTwinReachesTheReleasePipeline(path: OSPath) {
        let s = makeState(path)
        s.contentInsetAdjustmentBehavior = .never                                  // the hosting window has a safe area
        let w = withOSPath(path) { host(scroller(s).ztronScrollTargetBehavior(SnapTo(value: 123))) }
        pump(0.2)
        var env = PanEnvironment()
        env.viewport = CGSize(width: 200, height: 200)
        env.boundsX = AxisBounds(min: 0, max: 0)
        env.boundsY = AxisBounds(min: 0, max: 600)
        let request = ReleaseRequest(origin: .zero, dragStart: .zero, liftTime: 100, fallbackVelocity: nil)
        let (_, my) = s.endDrag(request, tracker: PointVelocityTracker(), env: env, settings: ReleaseSettings())
        #expect(my.endPosition == 123)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theContainersEnvironmentIsWhatBehaviorsRead(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(scroller(s).environment(\.horizontalSizeClass, .compact).environment(\.layoutDirection, .rightToLeft))
        }
        pump(0.2)
        let context = ZTronScrollTargetBehaviorContext(
            originalTarget: ZTronScrollTarget(rect: .zero), velocity: .zero, contentSize: .zero, containerSize: .zero,
            axes: .vertical, environment: CapturedTargetEnvironment(values: s.targetEnvironment))
        #expect(context.horizontalSizeClass == .compact)
        #expect(context.layoutDirection == .rightToLeft)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theCapturedEnvironmentDoesNotKeepTheStateAlive(path: OSPath) {
        // The environment the container sees carries the state itself and the reader's scope (which lists the state): the
        // leaf owns the captured copy and the state only points at it, so releasing the view releases the state.
        weak var weakState: ZTronScrollState?
        weak var weakBox: TargetEnvironmentBox?
        do {
            let s = makeState(path), scope = ProxyScope(), box = TargetEnvironmentBox()
            weakState = s; weakBox = box
            scope.attach(s)
            box.values.ztronScrollState = s
            box.values.ztronProxyScope = scope
            box.values.horizontalSizeClass = .compact
            s.adoptEnvironment(box)
            #expect(s.targetEnvironment.horizontalSizeClass == .compact)
            scope.detach(s)
        }
        #expect(weakState == nil && weakBox == nil)
        // Without a leaf there is nothing captured: the defaults.
        #expect(makeState(path).targetEnvironment.horizontalSizeClass == EnvironmentValues().horizontalSizeClass)
    }

    @Test(arguments: OSPath.allCases) func hostedContainersCaptureTheirEnvironment(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollViewReader { _ in scroller(s).environment(\.horizontalSizeClass, .regular) })
        }
        pump(0.3)
        #expect(s.targetEnvironment.horizontalSizeClass == .regular)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theCaptureLeafDoesNotReRunContentBodies(path: OSPath) {
        let s = makeState(path)
        let counts = BodyCount()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }.ztronScrollTargetBehavior(.paging))
        }
        pump(0.2)
        let base = counts.bodies
        for y in stride(from: 10.0, through: 200.0, by: 20) { s.track(offset: CGPoint(x: 0, y: y), zoom: 1 + y / 400); pump(0.03) }
        pump(0.1)
        #expect(counts.bodies == base)
        unhost(w)
    }

    // MARK: compile tests: the spellings coexist with SwiftUI's

    @Test func unprefixedMembersStayOnTheZTronScrollView() {
        let paged: ZTronScrollView<Color> = ZTronScrollView { Color.red }.scrollTargetBehavior(.paging)
        let custom: ZTronScrollView<Color> = ZTronScrollView(.horizontal) { Color.red }.scrollTargetBehavior(SnapTo())
            .zoomRange(min: .fit, max: .absolute(4))
        _ = (paged, custom)
        _ = Color.red.ztronScrollTargetBehavior(.paging)
        _ = Color.red.ztronScrollTargetBehavior(SnapTo())
    }

    @Test func theTwinCompilesAroundNativeScrollViews() {
        guard #available(iOS 17, *) else { return }
        _ = ScrollView { Color.red }.ztronScrollTargetBehavior(.paging).scrollTargetBehavior(.paging)
        _ = ScrollView { Color.red }.scrollTargetBehavior(.paging).ztronScrollTargetBehavior(SnapTo())
        _ = ScrollView(.horizontal) { Color.red }.ztronScrollTargetBehavior(ZTronPagingScrollTargetBehavior())
        _ = ZTronScrollView { Color.red }.scrollTargetBehavior(.paging)
    }

    @Test(arguments: OSPath.allCases) func aNativeScrollViewHostsTheTwin(path: OSPath) {
        guard #available(iOS 17, *) else { return }
        let w = withOSPath(path) {
            host(VStack(spacing: 0) {
                ScrollView(.horizontal) { HStack(spacing: 0) { Color.red.frame(width: 200, height: 100); Color.blue.frame(width: 200, height: 100) } }
                    .ztronScrollTargetBehavior(.paging)
                ScrollView(.horizontal) { HStack(spacing: 0) { Color.red.frame(width: 200, height: 100); Color.blue.frame(width: 200, height: 100) } }
                    .ztronScrollTargetBehavior(SnapTo(value: 12))
            })
        }
        pump(0.3)
        unhost(w)
    }

    // MARK: 11 · conversions (17+)

    @Test func nativeTargetAndContextConvertersExist() {
        guard #available(iOS 17, *) else { return }
        // SwiftUI constructs neither `ScrollTarget` nor `ScrollTargetBehaviorContext`, so a value round trip can only be
        // checked while SwiftUI calls a behavior (see `anObservedNativeBehaviorSeesTheBridgedValues` when it does); here the
        // converters are fixed at compile time.
        let read: (ScrollTarget) -> ZTronScrollTarget = { ZTronScrollTarget($0) }
        let write: (ZTronScrollTarget, inout ScrollTarget) -> Void = { ours, native in ours.write(to: &native) }
        let context: (ScrollTargetBehaviorContext) -> ZTronScrollTargetBehaviorContext = { ZTronScrollTargetBehaviorContext($0) }
        let bridge: (SnapTo) -> ZTronBridgedScrollTargetBehavior = { ZTronBridgedScrollTargetBehavior($0) }
        _ = (read, write, context, bridge)
    }

    @Test func theMirrorTargetKeepsItsValue() {
        let a = ZTronScrollTarget(rect: CGRect(x: 1, y: 2, width: 3, height: 4), anchor: .center)
        #expect(a == ZTronScrollTarget(rect: CGRect(x: 1, y: 2, width: 3, height: 4), anchor: .center))
        #expect(a != ZTronScrollTarget(rect: a.rect))
        #expect(ZTronScrollTarget(rect: .zero).anchor == nil)
    }
}
