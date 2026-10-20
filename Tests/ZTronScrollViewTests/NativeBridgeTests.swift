import Foundation
import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// M6 session 1, test 11 at runtime: SwiftUI constructs neither `ScrollTarget` nor `ScrollTargetBehaviorContext`, so the
/// conversions are exercised by letting a hosted native `ScrollView` call its behavior: the test drives the
/// `UIScrollView` delegate's `scrollViewWillEndDragging` (public UIKit API) exactly as a lifted finger would.

/// SwiftUI calls the behavior from its own (main-thread) callback; the sink only collects.
final class NativeSink: @unchecked Sendable {
    var targets: [ZTronScrollTarget] = []
    var contexts: [ZTronScrollTargetBehaviorContext] = []
}

@available(iOS 17, *)
struct NativeRecorder: ScrollTargetBehavior, @unchecked Sendable {
    let sink: NativeSink
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        sink.targets.append(ZTronScrollTarget(target))
        sink.contexts.append(ZTronScrollTargetBehaviorContext(context))
    }
}

@MainActor
func firstScrollView(in view: UIView) -> UIScrollView? {
    if let scrollView = view as? UIScrollView { return scrollView }
    for sub in view.subviews {
        if let found = firstScrollView(in: sub) { return found }
    }
    return nil
}

/// Releases a drag on the hosting `UIScrollView`: the proposed target offset goes in, SwiftUI's answer comes out.
@MainActor
func releaseDrag(_ window: UIWindow, velocity: CGPoint, proposed: CGPoint) -> CGPoint? {
    guard let root = window.rootViewController?.view, let scrollView = firstScrollView(in: root),
          let delegate = scrollView.delegate else { return nil }
    delegate.scrollViewWillBeginDragging?(scrollView)
    let target = UnsafeMutablePointer<CGPoint>.allocate(capacity: 1)
    defer { target.deallocate() }
    target.pointee = proposed
    delegate.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: target)
    return target.pointee
}

@MainActor
@Suite(.serialized)
struct NativeBridgeTests {
    /// The adjusted inset SwiftUI put on the hosted `UIScrollView` (the window has a safe area): SwiftUI's target rect and
    /// the delegate's offset differ by it.
    func nativeScrollView(_ window: UIWindow) -> UIScrollView? {
        window.rootViewController.flatMap { firstScrollView(in: $0.view) }
    }

    @Test(arguments: OSPath.allCases) func aNativeScrollViewHandsItsTargetAndContextToABehavior(path: OSPath) {
        guard #available(iOS 17, *) else { return }
        let sink = NativeSink()
        let w = withOSPath(path) {
            host(ScrollView { Color.red.frame(height: 1000) }.scrollTargetBehavior(NativeRecorder(sink: sink)))
        }
        pump(0.3)
        guard let native = nativeScrollView(w) else { Issue.record("no UIScrollView behind the hosted ScrollView"); return }
        guard releaseDrag(w, velocity: CGPoint(x: 0, y: 2), proposed: CGPoint(x: 0, y: 300)) != nil else {
            Issue.record("no UIScrollView delegate behind the hosted ScrollView"); return
        }
        guard let target = sink.targets.first, let context = sink.contexts.first else {
            Issue.record("the native scroll view did not call the behavior from its delegate"); return
        }
        // The values are SwiftUI's own, read through the converters: the target is the visible rect (container-sized), the
        // axes and sizes are those of the scroll view, and the container is the UNOBSCURED size.
        let inset = native.adjustedContentInset
        #expect(target.rect.size == context.containerSize)
        #expect(context.axes == .vertical)
        #expect(abs(context.containerSize.height - (native.bounds.height - inset.top - inset.bottom)) < 1)
        #expect(context.containerSize.width == 200 && context.contentSize.height >= 1000)
        // `context.velocity` is 0 for a delegate-injected release (SwiftUI reads the gesture's own velocity); its unit
        // (points per millisecond, ours too, D32) is measured by the demo's TargetsUITests during a real pan.
        // SwiftUI's target space (R4, measured on 17.5 and 27.0): the rect is in content coordinates, UIKit's offset plus
        // the top inset, so a view at rest reports origin 0. Which offset it starts from differs by OS: the proposed
        // target (17.5) or the current one (27.0). The library's own pipeline presents offsets (docs/progress/M6-s1.md).
        let origin = target.rect.origin.y - inset.top
        #expect(abs(origin - native.contentOffset.y) < 1 || abs(origin - 300) < 1,
                "native target origin \(target.rect.origin.y), offset \(native.contentOffset.y), top inset \(inset.top)")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func aBridgedBehaviorWritesItsTargetBackIntoTheNativeOne(path: OSPath) {
        guard #available(iOS 17, *) else { return }
        let w = withOSPath(path) {
            host(ScrollView { Color.red.frame(height: 1000) }.ztronScrollTargetBehavior(SnapTo(value: 420)))
        }
        pump(0.3)
        guard let native = nativeScrollView(w) else { Issue.record("no UIScrollView behind the hosted ScrollView"); return }
        let answer = releaseDrag(w, velocity: CGPoint(x: 0, y: 1), proposed: CGPoint(x: 0, y: 130))
        // SnapTo puts the rect origin at 420 in SwiftUI's target space; the delegate's offset is that minus the top inset.
        #expect(abs((answer?.y ?? -1) - (420 - native.adjustedContentInset.top)) < 1, "the answer SwiftUI took from the bridged behavior: \(String(describing: answer))")
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func theTwinsPagingIsSwiftUIsOwn(path: OSPath) {
        guard #available(iOS 17, *) else { return }
        let w = withOSPath(path) {
            host(ScrollView { Color.red.frame(height: 1000) }.ztronScrollTargetBehavior(.paging))
        }
        pump(0.3)
        guard let native = nativeScrollView(w) else { Issue.record("no UIScrollView behind the hosted ScrollView"); return }
        // The same release on a plain `.scrollTargetBehavior(.paging)` ScrollView must give the same answer.
        let plain = withOSPath(path) {
            host(ScrollView { Color.red.frame(height: 1000) }.scrollTargetBehavior(.paging))
        }
        pump(0.3)
        let viaTwin = releaseDrag(w, velocity: .zero, proposed: CGPoint(x: 0, y: 130))
        let viaNative = releaseDrag(plain, velocity: .zero, proposed: CGPoint(x: 0, y: 130))
        #expect(viaTwin != nil && viaTwin == viaNative, "twin \(String(describing: viaTwin)) vs native \(String(describing: viaNative)) (inset \(native.adjustedContentInset.top))")
        unhost(w); unhost(plain)
    }
}
