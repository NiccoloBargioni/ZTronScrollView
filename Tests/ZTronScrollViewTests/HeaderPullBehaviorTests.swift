import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// D65 (user, 2026-10-27): the pull behavior of a `.preserve` scaling header, `ZTronHeaderPullBehavior`. The API through
/// the real container, both OS paths: the default `.openGap`, the environment twin `ztronScalingHeaderPullBehavior(_:)` for
/// every scroll view below it, the member `scalingHeaderPullBehavior(_:)`, their precedence (member, else the innermost
/// twin, else `.openGap`), and a runtime change as a cold configuration change (no content body, the header takes the new
/// mode's place in the same update, also during a live pull).
@MainActor
@Suite(.serialized)
struct HeaderPullBehaviorTests {
    final class Box {
        var minY: CGFloat = .nan
        var height: CGFloat = .nan
    }

    /// Fills the live frame and records it.
    struct Probe: View {
        let box: Box
        var body: some View {
            GeometryReader { g in
                let _ = record(g)
                Color.red
            }
        }
        func record(_ g: GeometryProxy) {
            box.minY = g.frame(in: .global).minY
            box.height = g.size.height
        }
    }

    func window<V: View>(_ view: V) -> UIWindow {
        let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        w.rootViewController = UIHostingController(rootView: view)
        w.makeKeyAndVisible()
        pump(0.3)
        return w
    }

    func pull(_ s: ZTronScrollState) -> ZTronHeaderPullBehavior? { s.peek.metrics.header?.pull }

    func track(_ s: ZTronScrollState, oPrime x: CGFloat) {
        s.track(offset: CGPoint(x: 0, y: x - HeaderMath.base(s.peek.metrics)), zoom: 1)
    }

    func scroller(_ s: ZTronScrollState, box: Box = Box(), counts: BodyCount = BodyCount())
        -> ZTronScrollView<StatefulContent> {
        ZTronScrollView(.vertical, state: s) { StatefulContent(counts: counts) }
            .withScalingHeader(size: .fixed(min: 64, max: 240)) { _ in Probe(box: box) }
    }

    @Test(arguments: OSPath.allCases) func theDefaultIsOpenGap(path: OSPath) {
        let s = makeState(path), box = Box()
        let w = withOSPath(path) { window(scroller(s, box: box)) }
        defer { unhost(w) }
        #expect(pull(s) == .openGap)
        track(s, oPrime: -60)
        pump(0.1)
        let top0 = HeaderMath.top0(s.peek.metrics)
        #expect(abs(box.minY - top0) < 0.5 && abs(box.height - 240) < 0.5, "\(path): the header stays still (\(box.minY))")
        #expect(abs(-s.peek.presentationOffset.y - (top0 + 240 + 60)) < 0.5, "\(path): the gap below it is the pull")
    }

    @Test(arguments: OSPath.allCases) func theTwinAppliesToEveryScrollViewBelowIt(path: OSPath) {
        let a = makeState(path), b = makeState(path)
        let w = withOSPath(path) {
            window(VStack(spacing: 0) {
                scroller(a).frame(height: 437)
                scroller(b).frame(height: 437)
            }
            .ztronScalingHeaderPullBehavior(.followContent))
        }
        defer { unhost(w) }
        #expect(pull(a) == .followContent && pull(b) == .followContent, "\(path): \(String(describing: pull(a))) \(String(describing: pull(b)))")
    }

    /// Member, else the innermost twin, else `.openGap`; the member works before or after `withScalingHeader`.
    @Test(arguments: OSPath.allCases) func theMemberWinsThenTheInnermostTwin(path: OSPath) {
        let s1 = makeState(path), s2 = makeState(path), s3 = makeState(path), s4 = makeState(path)
        let w = withOSPath(path) {
            window(VStack(spacing: 0) {
                scroller(s1).scalingHeaderPullBehavior(.openGap).frame(height: 218)
                    .ztronScalingHeaderPullBehavior(.followContent)
                scroller(s2).scalingHeaderPullBehavior(.followContent).frame(height: 218)
                    .ztronScalingHeaderPullBehavior(.openGap)
                scroller(s3).frame(height: 218)
                    .ztronScalingHeaderPullBehavior(.followContent)
                    .ztronScalingHeaderPullBehavior(.openGap)
                ZTronScrollView(.vertical, state: s4) { Color.green.frame(height: 2000) }
                    .scalingHeaderPullBehavior(.followContent)
                    .withScalingHeader(size: .fixed(min: 64, max: 240)) { _ in Color.red }
                    .frame(height: 218)
            })
        }
        defer { unhost(w) }
        #expect(pull(s1) == .openGap, "\(path): the member wins over the twin")
        #expect(pull(s2) == .followContent, "\(path): the member wins over the twin")
        #expect(pull(s3) == .followContent, "\(path): the innermost twin wins")
        #expect(pull(s4) == .followContent, "\(path): the member before withScalingHeader still applies")
    }

    /// A runtime change of the twin (an ancestor's value; the scroll view's own parent does not re-run) and of the member
    /// (a parent rebuild), during a live pull: the header takes the new mode's place in the same update (layout = state),
    /// no content body runs, the header builder runs at most once per change (the container re-evaluates: R7).
    @Test(arguments: OSPath.allCases) func aRuntimeChangeIsColdAndDrawnAtOnce(path: OSPath) {
        @MainActor final class Model: ObservableObject {
            @Published var env = ZTronHeaderPullBehavior.openGap
            @Published var member: ZTronHeaderPullBehavior?
        }
        struct Inner: View {
            let state: ZTronScrollState
            let box: Box
            let counts: BodyCount
            let member: ZTronHeaderPullBehavior?
            var body: some View {
                let base = ZTronScrollView(.vertical, state: state) { StatefulContent(counts: counts) }
                    .withScalingHeader(size: .fixed(min: 64, max: 240)) { _ in Probe(box: box) }
                if let member { return base.scalingHeaderPullBehavior(member) }
                return base
            }
        }
        struct Outer: View {
            @ObservedObject var model: Model
            let state: ZTronScrollState
            let box: Box
            let counts: BodyCount
            var body: some View {
                Inner(state: state, box: box, counts: counts, member: model.member)
                    .ztronScalingHeaderPullBehavior(model.env)
            }
        }
        let s = makeState(path), box = Box(), counts = BodyCount(), model = Model()
        let w = withOSPath(path) { window(Outer(model: model, state: s, box: box, counts: counts)) }
        defer { unhost(w) }
        track(s, oPrime: -60)
        pump(0.1)
        let top0 = HeaderMath.top0(s.peek.metrics)
        func check(_ expected: ZTronHeaderPullBehavior, _ label: String) {
            #expect(pull(s) == expected, "\(path) \(label): \(String(describing: pull(s)))")
            let y = expected == .followContent ? top0 + 60 : top0
            #expect(abs(box.minY - y) < 0.5 && abs(box.height - 240) < 0.5,
                    "\(path) \(label): header at \(box.minY) (expected \(y)), height \(box.height)")
            let base = RefreshIndicatorMath.base(edge: .top, metrics: s.peek.metrics, overlay: false).0.top
            #expect(base == (expected == .followContent ? top0 : top0 + 240), "\(path) \(label): refresh base \(base)")
            #expect(abs(-s.peek.presentationOffset.y - (top0 + 300)) < 0.5, "\(path) \(label): the content did not move")
        }
        check(.openGap, "start")
        let bodies = counts.bodies
        func change(_ label: String, _ expected: ZTronHeaderPullBehavior, _ mutate: () -> Void) {
            ZTronRenderCounters.reset()
            mutate()
            pump(0.15)
            check(expected, label)
            #expect(ZTronRenderCounters.value("header.builder") <= 1, "\(path) \(label): builder runs \(ZTronRenderCounters.value("header.builder"))")
        }
        change("twin -> followContent", .followContent) { model.env = .followContent }
        change("twin -> openGap", .openGap) { model.env = .openGap }
        change("member -> followContent", .followContent) { model.member = .followContent }
        change("twin -> followContent under the member", .followContent) { model.env = .followContent }
        change("member -> openGap", .openGap) { model.member = .openGap }
        #expect(counts.bodies == bodies, "\(path): no content body for a pull behavior change (\(counts.bodies - bodies))")
        // Back to rest: identical in both modes.
        track(s, oPrime: 0)
        pump(0.1)
        #expect(abs(box.minY - top0) < 0.5 && abs(box.height - 240) < 0.5)
    }
}
