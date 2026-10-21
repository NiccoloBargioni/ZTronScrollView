import SwiftUI
import Testing
import UIKit
import ZTronScrollPhysics
@testable import ZTronScrollView

// M6b L1: content-integral overlays (SPEC S11 amendment 2026-10-21 (user), design docs/design/M6b-content-overlay.md).

// MARK: Probe (M6b step 0)

/// Counts the closure runs of a `GeometryReader` laid out under the transform. SwiftUI calls the closure on the main
/// thread; the counters are plain statics so the closure needs no isolation.
enum GRProbe {
    nonisolated(unsafe) static var runs = 0
    nonisolated(unsafe) static var size = CGSize.zero
}

/// Input-free: its own body runs only when SwiftUI builds it. The reader reads only its size, like the iOS 15 host.
private struct GRProbeContent: View {
    var body: some View {
        Color.red.frame(width: 200, height: 1000)
            .overlay(GeometryReader { g -> Color in GRProbe.runs += 1; GRProbe.size = g.size; return Color.clear })
    }
}

// MARK: Fixtures: input-free views with static body counters

@MainActor
enum Bodies {
    static var content = 0, marker = 0, fill = 0, banner = 0, pin = 0, relative = 0, scaled = 0, equatable = 0, equatableTwin = 0
    static var twin = 0, inner = 0
    static func reset() {
        content = 0; marker = 0; fill = 0; banner = 0; pin = 0; relative = 0; scaled = 0; equatable = 0; equatableTwin = 0
        twin = 0; inner = 0
    }
    static var overlays: [Int] { [marker, fill, banner, pin, relative, scaled, equatable, equatableTwin, twin, inner] }
}

private struct OverlaidContent: View {
    var body: some View { Bodies.content += 1; return Color.red.frame(width: 200, height: 1000) }
}
private struct Marker: View {
    var body: some View { Bodies.marker += 1; return Color.red.frame(width: 10, height: 10).ztronScrollID("m") }
}
private struct Fill: View {
    var body: some View { Bodies.fill += 1; return Color.clear.ztronScrollID("fill") }
}
private struct Banner: View {
    var body: some View { Bodies.banner += 1; return Color.blue.ztronScrollID("banner") }
}
private struct Pin: View {
    var body: some View { Bodies.pin += 1; return Color.green.frame(width: 10, height: 10).ztronScrollID("pin") }
}
private struct RelativeBox: View {
    var body: some View { Bodies.relative += 1; return Color.orange.ztronScrollID("rel") }
}
private struct ScaledMarker: View {
    var body: some View { Bodies.scaled += 1; return Color.purple.frame(width: 6, height: 6) }
}

/// Input-free and not `Equatable`: a twin overlay on the plain (non-cache) path.
private struct TwinMarker: View {
    var body: some View { Bodies.twin += 1; return Color.green.frame(width: 4, height: 4) }
}

/// The content of a scroll view drawn inside a twin overlay.
private struct InnerChips: View {
    var body: some View { Bodies.inner += 1; return Color.blue.frame(width: 600, height: 40) }
}

private extension Notification.Name {
    static let contentOverlayGrow = Notification.Name("ContentOverlayTests.grow")
}

/// Content `200 × 1000` that grows to `200 × 1500` through its own `@State` (a rotation reflow's shape): no parent
/// re-evaluation, no container evaluation, only this body.
private struct GrowingContent: View {
    @State private var tall = false
    var body: some View {
        Bodies.content += 1
        return VStack(spacing: 0) {
            Color.red.frame(width: 200, height: 1000)
            Color.blue.frame(width: 200, height: tall ? 500 : 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .contentOverlayGrow)) { _ in tall = true }
    }
}

/// Outer content `200 × 1100` holding an inner horizontal scroll view (content `600 × 100`).
private struct NestedContent: View {
    let inner: ZTronScrollState
    var body: some View {
        VStack(spacing: 0) {
            Color.red.frame(width: 200, height: 1000)
            ZTronScrollView(.horizontal, state: inner) { Color.orange.frame(width: 600, height: 100) }
                .frame(width: 200, height: 100)
        }
    }
}

/// The public helper inside the content.
private struct HelperContent: View {
    var body: some View {
        Bodies.content += 1
        return Color.red.frame(width: 200, height: 1000)
            .overlay(Color.purple.frame(width: 8, height: 8).ztronScrollCounterScaled(anchor: .bottom))
    }
}

final class OverlayRef {}

/// Holds a new reference on every parent evaluation, yet `==` says equal: only the `Equatable` overload skips its body.
private struct EqOverlay: View, Equatable {
    let ref: OverlayRef
    nonisolated static func == (l: EqOverlay, r: EqOverlay) -> Bool { true }
    var body: some View { Bodies.equatable += 1; return Color.yellow.frame(width: 4, height: 4) }
}

private struct EqTwinOverlay: View, Equatable {
    let ref: OverlayRef
    nonisolated static func == (l: EqTwinOverlay, r: EqTwinOverlay) -> Bool { true }
    var body: some View { Bodies.equatableTwin += 1; return Color.yellow.frame(width: 4, height: 4) }
}

/// The overlay set of the hosted tests (content `W × H`): see `expectFrames`.
@MainActor
private func overlaid<C: View>(_ v: ZTronScrollView<C>) -> ZTronScrollView<C> {
    v.scrollContentIntegralOverlay(anchor: .relative(UnitPoint(x: 0.3, y: 0.65)), overlayAnchor: .center, size: .ideal) { Marker() }
        .scrollContentIntegralOverlay { Fill() }
        .scrollContentIntegralOverlay(anchor: .bottom, overlayAnchor: .bottom, size: .fillMaxWidth(16 / 9)) { Banner() }
        .scrollContentIntegralOverlay(anchor: .absolute(CGPoint(x: 20, y: 30)), size: .ideal) { Pin() }
        .scrollContentIntegralOverlay(anchor: .topLeading, size: .relative(CGSize(width: 0.5, height: 0.2))) { RelativeBox() }
        .scrollContentIntegralOverlay(anchor: .center, overlayAnchor: .center, size: .ideal, scaling: .counterScaled) {
            ScaledMarker()
        }
}

/// Content `200 × 1000`, or `200 × 1500` when the sibling grows (a parent re-evaluation; the content itself is input-free).
private struct SizedParent: View {
    @ObservedObject var model: TallModel
    let state: ZTronScrollState
    var body: some View {
        overlaid(ZTronScrollView(.vertical, state: state) {
            VStack(spacing: 0) {
                OverlaidContent()
                Color.blue.frame(width: 200, height: model.tall ? 500 : 0)
            }
        })
    }
}

/// A parent re-evaluation that changes nothing about the overlays.
private struct RelabelParent: View {
    @ObservedObject var model: LabelModel
    let state: ZTronScrollState
    var body: some View {
        ZTronScrollView(.vertical, state: state) { OverlaidContent() }
            .scrollContentIntegralOverlay(anchor: .center, size: .ideal) { Marker() }
            .scrollContentIntegralOverlay(anchor: .topLeading, size: .ideal) { EqOverlay(ref: OverlayRef()) }
            .ztronScrollContentIntegralOverlay(anchor: .bottomLeading, size: .ideal) { EqTwinOverlay(ref: OverlayRef()) }
            .ztronScrollContentIntegralOverlay(anchor: .bottomTrailing, size: .ideal) { TwinMarker() }
            .accessibilityLabel(model.label)
    }
}

@MainActor
final class OverlayAnchorModel: ObservableObject { @Published var trailing = false }

private struct IdentityOverlay: View {
    let counts: BodyCount
    @State private var id = UUID()
    var body: some View {
        counts.ids.insert(id)
        return Color.red.frame(width: 10, height: 10).ztronScrollID("ident")
    }
}

private struct IdentityParent: View {
    @ObservedObject var model: OverlayAnchorModel
    let state: ZTronScrollState
    let counts: BodyCount
    var body: some View {
        ZTronScrollView(.vertical, state: state) { OverlaidContent() }
            .scrollContentIntegralOverlay(anchor: model.trailing ? .topTrailing : .topLeading,
                                          overlayAnchor: model.trailing ? .topTrailing : .topLeading, size: .ideal) {
                IdentityOverlay(counts: counts)
            }
    }
}

// MARK: Helpers

private func close(_ a: CGRect?, _ b: CGRect, tolerance: CGFloat = 0.5) -> Bool {
    guard let a else { return false }
    return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
        && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
}

/// Exact up to floating-point noise (the math tests).
private func same(_ a: CGRect, _ b: CGRect) -> Bool { close(a, b, tolerance: 1e-9) }

@MainActor
@Suite(.serialized)
struct ContentOverlayTests {
    // MARK: (a) math

    private let content = CGSize(width: 300, height: 600)
    /// The view's own size: 50 × 30 whatever the open axes (the height at width W for `.fillMaxWidth(nil)`).
    private func measure(_ p: OverlayProposal) -> CGSize { CGSize(width: 50, height: 30) }

    private func resolve(_ anchor: ZTronContentOverlayAnchor, _ q: UnitPoint, _ size: ZTronContentOverlaySize,
                         content: CGSize? = nil) -> CGRect {
        ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: anchor, overlayAnchor: q, size: size),
                                   content: content ?? self.content, measure: measure)
    }

    @Test func mathTableNamedAnchorsTimesOverlayAnchorsTimesSizes() {
        let named: [(ZTronContentOverlayAnchor, CGPoint)] = [
            (.topLeading, CGPoint(x: 0, y: 0)), (.top, CGPoint(x: 150, y: 0)), (.topTrailing, CGPoint(x: 300, y: 0)),
            (.leading, CGPoint(x: 0, y: 300)), (.center, CGPoint(x: 150, y: 300)), (.trailing, CGPoint(x: 300, y: 300)),
            (.bottomLeading, CGPoint(x: 0, y: 600)), (.bottom, CGPoint(x: 150, y: 600)), (.bottomTrailing, CGPoint(x: 300, y: 600)),
        ]
        let qs: [UnitPoint] = [.topLeading, .center, .bottom, UnitPoint(x: 0.25, y: 0.75)]
        let sizes: [(ZTronContentOverlaySize, CGSize)] = [
            (.fillMaxWidth(16 / 9), CGSize(width: 300, height: 168.75)),
            (.fillMaxWidth(nil), CGSize(width: 300, height: 30)),
            (.fillMaxWidth(), CGSize(width: 300, height: 30)),
            (.fillMaxHeight(4 / 3), CGSize(width: 800, height: 600)),
            (.relative(CGSize(width: 0.5, height: 0.2)), CGSize(width: 150, height: 120)),
            (.absolute(CGSize(width: 120, height: 40)), CGSize(width: 120, height: 40)),
            (.ideal, CGSize(width: 50, height: 30)),
        ]
        for (anchor, p) in named {
            #expect(ContentOverlayMath.anchorPoint(anchor, content: content) == p, "\(anchor)")
            for q in qs {
                for (size, f) in sizes {
                    let expected = CGRect(x: p.x - q.x * f.width, y: p.y - q.y * f.height, width: f.width, height: f.height)
                    let r = resolve(anchor, q, size)
                    #expect(same(r, expected), "\(anchor) \(q) \(size): \(r) != \(expected)")
                }
            }
        }
    }

    @Test func mathRelativeAbsoluteAndFillMaxSize() {
        // .relative(0.3, 0.65): P = (90, 390); an ideal 50 × 30 view centred on it.
        #expect(same(resolve(.relative(UnitPoint(x: 0.3, y: 0.65)), .center, .ideal), CGRect(x: 65, y: 375, width: 50, height: 30)))
        // .absolute(A) pins the overlayAnchor point at A, whatever the content size.
        for c in [content, CGSize(width: 10, height: 10), .zero] {
            #expect(same(resolve(.absolute(CGPoint(x: 20, y: 30)), .bottom, .absolute(CGSize(width: 120, height: 40)), content: c),
                          CGRect(x: -40, y: -10, width: 120, height: 40)))
            #expect(same(resolve(.absolute(CGPoint(x: 20, y: 30)), .topLeading, .ideal, content: c),
                          CGRect(x: 20, y: 30, width: 50, height: 30)))
        }
        // .fillMaxSize: the content rect whatever the anchors.
        for anchor in [ZTronContentOverlayAnchor.center, .bottomTrailing, .relative(UnitPoint(x: 2, y: -1)), .absolute(CGPoint(x: 9, y: 9))] {
            for q in [UnitPoint.topLeading, .center, .bottomTrailing] {
                #expect(same(resolve(anchor, q, .fillMaxSize), CGRect(x: 0, y: 0, width: 300, height: 600)))
            }
        }
        // `measure` runs only when an axis is unspecified.
        var calls = 0
        _ = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: .center, overlayAnchor: .center, size: .fillMaxWidth(2)),
                                       content: content) { _ in calls += 1; return .zero }
        #expect(calls == 0)
        _ = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: .center, overlayAnchor: .center, size: .fillMaxWidth(nil)),
                                       content: content) { p in calls += 1; #expect(p == OverlayProposal(width: 300, height: nil)); return .zero }
        #expect(calls == 1)
    }

    @Test func mathDegenerateInputs() {
        // W = 0 / H = 0: fill and relative sizes collapse on that axis; an ideal view sits at P at its size.
        let noWidth = CGSize(width: 0, height: 600), noHeight = CGSize(width: 300, height: 0)
        #expect(same(resolve(.center, .center, .fillMaxWidth(16 / 9), content: noWidth), CGRect(x: 0, y: 300, width: 0, height: 0)))
        #expect(same(resolve(.center, .topLeading, .relative(CGSize(width: 0.5, height: 0.5)), content: noWidth),
                      CGRect(x: 0, y: 300, width: 0, height: 300)))
        #expect(same(resolve(.center, .center, .ideal, content: noHeight), CGRect(x: 125, y: -15, width: 50, height: 30)))
        #expect(same(resolve(.center, .topLeading, .fillMaxHeight(2), content: noHeight), CGRect(x: 150, y: 0, width: 0, height: 0)))
        #expect(same(resolve(.top, .topLeading, .fillMaxSize, content: .zero), .zero))
        // Aspect 0, −1, ∞, NaN: as nil (the view's own size on the open axis), with the DEBUG note.
        for r in [CGFloat(0), -1, .infinity, .nan] {
            ZTronRenderCounters.notes["contentOverlay.badAspect"] = nil
            #expect(ContentOverlayMath.aspect(r) == nil)
            #expect(ZTronRenderCounters.notes["contentOverlay.badAspect"] != nil, "note for \(r)")
            #expect(same(resolve(.topLeading, .topLeading, .fillMaxWidth(r)), CGRect(x: 0, y: 0, width: 300, height: 30)), "w \(r)")
            #expect(same(resolve(.topLeading, .topLeading, .fillMaxHeight(r)), CGRect(x: 0, y: 0, width: 50, height: 600)), "h \(r)")
        }
        #expect(ContentOverlayMath.aspect(nil) == nil && ContentOverlayMath.aspect(1.5) == 1.5)
        // Negative or non-finite k / s → 0.
        #expect(same(resolve(.topLeading, .topLeading, .relative(CGSize(width: -0.5, height: 0.2))), CGRect(x: 0, y: 0, width: 0, height: 120)))
        #expect(same(resolve(.topLeading, .topLeading, .relative(CGSize(width: CGFloat.nan, height: .infinity))), .zero))
        #expect(same(resolve(.topLeading, .topLeading, .absolute(CGSize(width: -10, height: 40))), CGRect(x: 0, y: 0, width: 0, height: 40)))
        #expect(same(resolve(.topLeading, .topLeading, .absolute(CGSize(width: CGFloat.infinity, height: .nan))), .zero))
        // Non-finite A → 0.
        #expect(same(resolve(.absolute(CGPoint(x: CGFloat.nan, y: .infinity)), .topLeading, .ideal), CGRect(x: 0, y: 0, width: 50, height: 30)))
        // Larger than the content: the negative origin is kept.
        #expect(same(resolve(.center, .center, .absolute(CGSize(width: 500, height: 900))), CGRect(x: -100, y: -150, width: 500, height: 900)))
        #expect(same(resolve(.topLeading, .bottomTrailing, .ideal), CGRect(x: -50, y: -30, width: 50, height: 30)))
    }

    // MARK: (b) frames through the registry, before and after a content-size change; (c) the change re-places only

    private func expectFrames(_ s: ZTronScrollState, w W: CGFloat, h H: CGFloat, _ label: String) {
        let r = s.targets
        let expected: [(String, CGRect)] = [
            ("m", CGRect(x: 0.3 * W - 5, y: 0.65 * H - 5, width: 10, height: 10)),
            ("fill", CGRect(x: 0, y: 0, width: W, height: H)),
            ("banner", CGRect(x: 0, y: H - W * 9 / 16, width: W, height: W * 9 / 16)),
            ("pin", CGRect(x: 20, y: 30, width: 10, height: 10)),
            ("rel", CGRect(x: 0, y: 0, width: 0.5 * W, height: 0.2 * H)),
        ]
        for (id, frame) in expected {
            #expect(close(r.frame(of: id), frame), "\(label) \(id): \(String(describing: r.frame(of: id))) != \(frame)")
        }
    }

    @Test(arguments: OSPath.allCases) func framesFollowTheFormulaAndTheContentSize(path: OSPath) {
        let s = makeState(path)
        let model = TallModel()
        let w = withOSPath(path) { host(SizedParent(model: model, state: s)) }
        pump(0.2)
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1000))
        expectFrames(s, w: 200, h: 1000, "initial")
        Bodies.reset()
        ZTronRenderCounters.reset()
        withOSPath(path) { model.tall = true; pump(0.3) }
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1500))
        expectFrames(s, w: 200, h: 1500, "grown")
        // Re-placed by layout, never by user bodies. This change re-evaluates the parent, so the container (and the
        // host) runs too; `contentOwnedReflowRePlacesWithoutAnyBody` is the change that does not.
        #expect(Bodies.overlays.allSatisfy { $0 == 0 }, "overlay bodies \(Bodies.overlays)")
        #expect(Bodies.content == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") >= 1)
        if s.usesLayoutProtocol {
            #expect(ZTronRenderCounters.value("contentOverlay.place") >= 1)
        } else {
            #expect(ZTronRenderCounters.value("contentOverlay.reader") >= 1)
        }
        unhost(w)
    }

    /// The rotation shape: the content changes its own size (its `@State`), nothing above it re-evaluates. Layout alone
    /// re-places the overlays: no host body, no overlay body, the content's body once (its own change).
    @Test(arguments: OSPath.allCases) func contentOwnedReflowRePlacesWithoutAnyBody(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) { host(overlaid(ZTronScrollView(.vertical, state: s) { GrowingContent() })) }
        pump(0.2)
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1000))
        expectFrames(s, w: 200, h: 1000, "initial")
        Bodies.reset()
        ZTronRenderCounters.reset()
        withOSPath(path) { NotificationCenter.default.post(name: .contentOverlayGrow, object: nil); pump(0.3) }
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1500))
        expectFrames(s, w: 200, h: 1500, "grown")
        #expect(Bodies.content == 1, "the content's own change only")
        #expect(Bodies.overlays.allSatisfy { $0 == 0 }, "overlay bodies \(Bodies.overlays)")
        #expect(ZTronRenderCounters.value("contentOverlay.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") == 0, "no container evaluation")
        if s.usesLayoutProtocol {
            #expect(ZTronRenderCounters.value("contentOverlay.place") >= 1)
            #expect(ZTronRenderCounters.value("contentOverlay.reader") == 0)
        } else {
            #expect(ZTronRenderCounters.value("contentOverlay.reader") >= 1)
            #expect(ZTronRenderCounters.value("contentOverlay.place") == 0)
        }
        unhost(w)
    }

    // MARK: (c) stability

    @Test(arguments: OSPath.allCases) func motionRunsNoContentNoOverlayNoHostNoPlacement(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(overlaid(ZTronScrollView(.vertical, state: s) { OverlaidContent() })
                .zoomRange(min: .absolute(1), max: .absolute(4)))
        }
        pump(0.3)
        let writes = s.targets.writes
        Bodies.reset()
        ZTronRenderCounters.reset()
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 30 * CGFloat(i)), zoom: 1); pump(0.03) }       // offset only
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 150), zoom: 1 + 0.25 * CGFloat(i)); pump(0.03) }  // zoom
        s.setContentOffset(CGPoint(x: 0, y: 400), animated: true); pump(1.0)
        s.setZoomScale(2, animated: true); pump(1.0)
        #expect(s.zoomScale == 2)
        // The gesture scripts of `PinchPanTests` / `PositionTests`, on the hosted state and the real clock. A second
        // coordinator drives them (the container's own is private); it reads the hosted state's bounds.
        let c = withOSPath(path) { PanCoordinator(state: s, axes: .vertical) }
        c.pinch.centroidSource = .spatial
        // A fling: released at 1500 pt/s, about 3 s of deceleration (and a bounce if it reaches the edge).
        let from = s.peek.presentationOffset
        s.beginTracking(); s.beginDragging()
        s.writeDragOffset(CGPoint(x: from.x, y: from.y + 10)); pump(0.03)
        s.endDrag(ReleaseRequest(origin: CGPoint(x: from.x, y: from.y + 10), dragStart: from, liftTime: s.now(),
                                 fallbackVelocity: CGVector(dx: 0, dy: -1500)),
                  tracker: PointVelocityTracker(), env: c.peekEnvironment(), settings: ReleaseSettings())
        #expect(s.isDecelerating, "the fling runs")
        pump(3.0)
        s.stopScrollingAndZooming()
        // A rubber band: dragged 80 pt past the top edge (the rest offset is −adjustedContentInset.top), released
        // without velocity, springs back.
        let x = s.peek.presentationOffset.x
        let top = c.peekEnvironment().boundsY.min
        s.beginTracking(); s.beginDragging()
        s.writeDragOffset(CGPoint(x: x, y: top - 80)); pump(0.03)
        s.endDrag(ReleaseRequest(origin: CGPoint(x: x, y: top - 80), dragStart: CGPoint(x: x, y: top), liftTime: s.now(),
                                 fallbackVelocity: .zero),
                  tracker: PointVelocityTracker(), env: c.peekEnvironment(), settings: ReleaseSettings())
        #expect(s.isDecelerating, "the spring back runs")
        pump(1.2)
        #expect(abs(s.peek.presentationOffset.y - top) < 0.5, "back at the edge \(top): \(s.peek.presentationOffset)")
        // A pinch past the maximum (4) and its bounce back.
        let centre = CGPoint(x: 100, y: 100)
        c.handle(.touchDown(location: centre, time: s.now(), touchCount: 2))
        c.handlePinch(.fingerCountChanged(count: 2, remaining: centre, time: s.now()))
        c.handlePinch(.began(centroid: centre, time: s.now()))
        for m in [1.2, 1.6, 2.0, 2.6] as [CGFloat] {
            c.handlePinch(.changed(magnification: m, centroid: centre, time: s.now())); pump(0.03)
        }
        #expect(s.zoomScale > 4, "past the maximum: \(s.zoomScale)")
        c.handlePinch(.fingerCountChanged(count: 0, remaining: nil, time: s.now()))
        c.handle(.touchesEnded(time: s.now()))
        #expect(s.isZoomBouncing, "the zoom bounce runs")
        pump(1.2)
        #expect(abs(s.zoomScale - 4) < 1e-6, "bounced to the maximum: \(s.zoomScale)")
        // zoom(to:animated:): 100 × 50 fits the visible area (the viewport less its safe-area insets) by its width.
        s.zoom(to: CGRect(x: 50, y: 300, width: 100, height: 50), animated: true); pump(1.2)
        #expect(abs(s.zoomScale - 2) < 1e-6, "\(s.zoomScale)")
        #expect(ZTronRenderCounters.value("transform.effect") > 0)   // the motion was drawn
        #expect(Bodies.content == 0)
        #expect(Bodies.overlays.allSatisfy { $0 == 0 }, "overlay bodies \(Bodies.overlays)")
        #expect(ZTronRenderCounters.value("contentOverlay.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.reader") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.place") == 0)
        #expect(s.targets.writes == writes, "the overlays' content-space frames never moved")
        unhost(w)
    }

    /// SPEC S14 / the S4 row: a refresh (the hold opens and closes the inset) runs no body and no placement.
    @Test(arguments: OSPath.allCases) func refreshRunsNoContentNoOverlayNoHostNoPlacement(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(overlaid(ZTronScrollView(.vertical, state: s) { OverlaidContent() }).refresher(style: .default) { })
        }
        pump(0.3)
        let writes = s.targets.writes
        Bodies.reset()
        ZTronRenderCounters.reset()
        s.beginRefreshing()
        pump(0.3)
        #expect(s.refresh?.states[.top]?.mode == .refreshing && s.refreshHoldInset.top > 0, "the hold is open")
        s.endRefreshing()
        pump(0.8)
        #expect(s.refresh?.states[.top]?.mode == .notRefreshing && s.refreshHoldInset.top == 0, "the hold closed")
        #expect(Bodies.content == 0)
        #expect(Bodies.overlays.allSatisfy { $0 == 0 }, "overlay bodies \(Bodies.overlays)")
        #expect(ZTronRenderCounters.value("contentOverlay.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.reader") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.place") == 0)
        #expect(s.targets.writes == writes)
        unhost(w)
    }

    @Test(arguments: OSPath.allCases) func parentReevaluationDoesNotRunInputFreeOverlayBodies(path: OSPath) {
        let s = makeState(path)
        let model = LabelModel()
        Bodies.reset()
        let w = withOSPath(path) { host(RelabelParent(model: model, state: s)) }
        pump(0.2)
        // Every overlay drew: the member, the `Equatable` member and twin (the cache path) and the plain twin.
        #expect(Bodies.marker >= 1 && Bodies.equatable >= 1 && Bodies.equatableTwin >= 1 && Bodies.twin >= 1,
                "overlay bodies \(Bodies.overlays)")
        #expect(close(s.targets.frame(of: "m"), CGRect(x: 100, y: 500, width: 10, height: 10)))
        Bodies.reset()
        ZTronRenderCounters.reset()
        withOSPath(path) { model.label = "b"; pump(0.2) }
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") >= 1)   // the container did re-evaluate
        #expect(Bodies.marker == 0)
        #expect(Bodies.equatable == 0)                                         // `==`, not field identity
        #expect(Bodies.equatableTwin == 0)
        #expect(Bodies.twin == 0)                                              // a twin rebuilt in a new AnyView
        #expect(Bodies.content == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.body") == 0)
        unhost(w)
    }

    // MARK: (d) identity

    @Test(arguments: OSPath.allCases) func reappliedMemberKeepsTheOverlaysIdentity(path: OSPath) {
        let s = makeState(path)
        let model = OverlayAnchorModel()
        let counts = BodyCount()
        let w = withOSPath(path) { host(IdentityParent(model: model, state: s, counts: counts)) }
        pump(0.2)
        #expect(close(s.targets.frame(of: "ident"), CGRect(x: 0, y: 0, width: 10, height: 10)))
        withOSPath(path) { model.trailing = true; pump(0.3) }
        #expect(close(s.targets.frame(of: "ident"), CGRect(x: 190, y: 0, width: 10, height: 10)),
                "\(String(describing: s.targets.frame(of: "ident")))")
        #expect(counts.ids.count == 1)
        unhost(w)
    }

    // MARK: (e) member + twin

    @Test(arguments: OSPath.allCases) func memberAndTwinCoexistTwinsFirst(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { OverlaidContent() }
                .scrollContentIntegralOverlay(anchor: .topLeading, size: .ideal) {
                    Color.red.frame(width: 10, height: 10).ztronScrollID("member")
                }
                .ztronScrollContentIntegralOverlay(anchor: .bottomTrailing, overlayAnchor: .bottomTrailing, size: .ideal) {
                    Color.blue.frame(width: 10, height: 10).ztronScrollID("twin")
                })
        }
        pump(0.2)
        #expect(close(s.targets.frame(of: "member"), CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(close(s.targets.frame(of: "twin"), CGRect(x: 190, y: 990, width: 10, height: 10)))
        let order = (ZTronRenderCounters.notes["contentOverlay.order"] ?? "").split(separator: ",").map(String.init)
        #expect(order.count == 2 && order.last == "member.0" && order.first?.contains("ObserverKey") == true, "\(order)")
        unhost(w)
    }

    /// Design §4: the twin reaches a scroll view nested in the content, which draws its own copy in its own content space.
    @Test(arguments: OSPath.allCases) func theTwinReachesANestedScrollViewWithItsOwnCopy(path: OSPath) {
        let s = makeState(path), inner = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { NestedContent(inner: inner) }
                .ztronScrollContentIntegralOverlay(anchor: .bottomTrailing, overlayAnchor: .bottomTrailing, size: .ideal) {
                    Color.blue.frame(width: 10, height: 10).ztronScrollID("twin")
                })
        }
        pump(0.3)
        #expect(close(s.targets.frame(of: "twin"), CGRect(x: 190, y: 1090, width: 10, height: 10)),
                "outer \(String(describing: s.targets.frame(of: "twin")))")
        #expect(close(inner.targets.frame(of: "twin"), CGRect(x: 590, y: 90, width: 10, height: 10)),
                "inner \(String(describing: inner.targets.frame(of: "twin")))")
        unhost(w)
    }

    /// A twin whose view holds a `ZTronScrollView`: that scroll view must not draw the twin again (it used to nest
    /// without end, the overlay inheriting the twin list). One copy, a bounded number of host evaluations.
    @Test(arguments: OSPath.allCases) func aTwinHoldingAScrollViewDoesNotDrawItselfInside(path: OSPath) {
        let s = makeState(path)
        Bodies.reset()
        ZTronRenderCounters.reset()
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { OverlaidContent() }
                .ztronScrollContentIntegralOverlay(anchor: .bottom, overlayAnchor: .bottom,
                                                   size: .absolute(CGSize(width: 200, height: 40))) {
                    ZTronScrollView(.horizontal) { InnerChips() }
                })
        }
        pump(0.3)
        #expect(Bodies.inner >= 1, "the inner scroll view drew")
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") < 10,
                "\(ZTronRenderCounters.value("contentOverlay.host.body")) host evaluations")
        #expect(Bodies.inner <= 2, "one copy: \(Bodies.inner) inner bodies")
        unhost(w)
    }

    // MARK: (e2) centring: both hosts put a view that takes less than its frame in the frame's centre

    @Test(arguments: OSPath.allCases) func bothHostsCentreAViewInItsFrame(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { OverlaidContent() }
                // P = (100, 100), frame (40, 60, 120, 40): the 10 × 10 view at its centre.
                .scrollContentIntegralOverlay(anchor: .relative(UnitPoint(x: 0.5, y: 0.1)), overlayAnchor: .bottom,
                                              size: .absolute(CGSize(width: 120, height: 40))) {
                    Color.red.frame(width: 10, height: 10).ztronScrollID("small")
                }
                // Width = W, the view's own height at that width.
                .scrollContentIntegralOverlay(anchor: .top, overlayAnchor: .top, size: .fillMaxWidth()) {
                    Color.blue.frame(height: 25).ztronScrollID("wide")
                }
                // `.fillMaxSize`: a smaller view centred in the content rect, as SwiftUI's `.overlay`.
                .scrollContentIntegralOverlay { Color.green.frame(width: 20, height: 20).ztronScrollID("centred") })
        }
        pump(0.2)
        #expect(close(s.targets.frame(of: "small"), CGRect(x: 95, y: 75, width: 10, height: 10)),
                "\(String(describing: s.targets.frame(of: "small")))")
        #expect(close(s.targets.frame(of: "wide"), CGRect(x: 0, y: 0, width: 200, height: 25)),
                "\(String(describing: s.targets.frame(of: "wide")))")
        #expect(close(s.targets.frame(of: "centred"), CGRect(x: 90, y: 490, width: 20, height: 20)),
                "\(String(describing: s.targets.frame(of: "centred")))")
        unhost(w)
    }

    // MARK: (f) counter-scale

    @Test func counterScaleEffectMath() {
        let t = CounterScaleEffect.transform(zoom: 2, anchor: .bottom, size: CGSize(width: 10, height: 20))
        #expect(t.a == 0.5 && t.d == 0.5 && t.b == 0 && t.c == 0)
        #expect(CGPoint(x: 5, y: 20).applying(t) == CGPoint(x: 5, y: 20))      // the anchor point stays
        #expect(CGPoint(x: 0, y: 0).applying(t) == CGPoint(x: 2.5, y: 10))
        let e = CounterScaleEffect(zoom: 2, anchor: .center).effectValue(size: CGSize(width: 6, height: 6))
        #expect(e.m11 == 0.5 && e.m22 == 0.5 && e.m31 == 1.5 && e.m32 == 1.5)
        for z in [CGFloat(0), -1, .nan, .infinity] {
            #expect(CounterScaleEffect.transform(zoom: z, anchor: .center, size: CGSize(width: 6, height: 6)) == .identity, "\(z)")
        }
        var animated = CounterScaleEffect(zoom: 1, anchor: .center)
        animated.animatableData = 3
        #expect(animated.zoom == 3)
    }

    @Test(arguments: OSPath.allCases) func counterScaleLeafWakesOnZoomOnly(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { OverlaidContent() }
                .scrollContentIntegralOverlay(anchor: .center, overlayAnchor: .center, size: .ideal, scaling: .counterScaled) {
                    ScaledMarker()
                })
        }
        pump(0.2)
        Bodies.reset()
        ZTronRenderCounters.reset()
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 30 * CGFloat(i)), zoom: 1); pump(0.03) }
        #expect(ZTronRenderCounters.value("contentOverlay.counterScale.body") == 0)
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 150), zoom: 1 + 0.25 * CGFloat(i)); pump(0.03) }
        #expect(ZTronRenderCounters.value("contentOverlay.counterScale.body") >= 1)
        #expect(Bodies.scaled == 0 && Bodies.content == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") == 0)
        // Presentation-only zoom writes (the transaction probe, a rotation's resize tick) do not change the target: the
        // leaf stays asleep on both paths (on 15–16 the `.zoom` channel used to wake it on every such frame).
        let woken = ZTronRenderCounters.value("contentOverlay.counterScale.body")
        for i in 1...5 { s.storage.presentationZoom = 2.25 + 0.1 * CGFloat(i); pump(0.03) }
        #expect(ZTronRenderCounters.value("contentOverlay.counterScale.body") == woken,
                "\(ZTronRenderCounters.value("contentOverlay.counterScale.body") - woken) wakes on presentation writes")
        unhost(w)
    }

    /// Design §4 `.counterScaled`, read through the effect's value: at zoom 2 the overlay draws at its ideal size on
    /// screen and its `overlayAnchor` point stays on `P`.
    @Test(arguments: OSPath.allCases) func aCounterScaledOverlayKeepsItsSizeAndItsAnchorPoint(path: OSPath) throws {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { OverlaidContent() }
                .scrollContentIntegralOverlay(anchor: .relative(UnitPoint(x: 0.3, y: 0.65)), overlayAnchor: .bottom, size: .ideal,
                                              scaling: .counterScaled) { ScaledMarker() }
                .zoomRange(min: .absolute(1), max: .absolute(4)))
        }
        pump(0.2)
        CounterScaleProbe.last = nil
        withOSPath(path) { s.setZoomScale(2, animated: false); pump(0.2) }
        let v = try #require(CounterScaleProbe.last)
        #expect(v.zoom == 2 && v.anchor == .bottom && v.size == CGSize(width: 6, height: 6), "\(v)")
        // The overlay's frame (formula): P = (60, 650), q = .bottom, f = 6 × 6. The effect maps it in place.
        let frame = CGRect(x: 57, y: 644, width: 6, height: 6)
        let drawn = CGRect(origin: .zero, size: v.size)
            .applying(CounterScaleEffect.transform(zoom: v.zoom, anchor: v.anchor, size: v.size))
            .offsetBy(dx: frame.minX, dy: frame.minY)
        #expect(close(drawn, CGRect(x: 58.5, y: 647, width: 3, height: 3), tolerance: 1e-9), "\(drawn)")
        #expect(drawn.width * s.zoomScale == 6 && drawn.height * s.zoomScale == 6, "6 × 6 on screen")
        #expect(drawn.midX == 60 && drawn.maxY == 650, "the tip stays on P")
        unhost(w)
    }

    /// `.fillMaxSize` ignores both anchors: a counter-scaled fill scales about the content's centre, not about the
    /// default `overlayAnchor` (`.topLeading`).
    @Test(arguments: OSPath.allCases) func aCounterScaledFillScalesAboutTheContentCentre(path: OSPath) throws {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { OverlaidContent() }
                .scrollContentIntegralOverlay(scaling: .counterScaled) { Color.blue.opacity(0.2) }
                .zoomRange(min: .absolute(1), max: .absolute(4)))
        }
        pump(0.2)
        CounterScaleProbe.last = nil
        withOSPath(path) { s.setZoomScale(2, animated: false); pump(0.2) }
        let v = try #require(CounterScaleProbe.last)
        #expect(v.zoom == 2 && v.anchor == .center && v.size == CGSize(width: 200, height: 1000), "\(v)")
        unhost(w)
    }

    /// SPEC S6 / M8-chrome §6: the public helper inside the content follows the nearest scroll view's zoom, never on
    /// panning, and never re-runs the content's body.
    @Test(arguments: OSPath.allCases) func theCounterScaledHelperFollowsTheZoomWithoutAContentBody(path: OSPath) throws {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { HelperContent() }.zoomRange(min: .absolute(1), max: .absolute(4)))
        }
        pump(0.2)
        Bodies.reset()
        ZTronRenderCounters.reset()
        CounterScaleProbe.last = nil
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 30 * CGFloat(i)), zoom: 1); pump(0.03) }
        #expect(ZTronRenderCounters.value("contentOverlay.counterScale.body") == 0, "panning never wakes it")
        withOSPath(path) { s.setZoomScale(3, animated: false); pump(0.2) }
        let v = try #require(CounterScaleProbe.last)
        #expect(v.zoom == 3 && v.anchor == .bottom && v.size == CGSize(width: 8, height: 8), "\(v)")
        #expect(ZTronRenderCounters.value("contentOverlay.counterScale.body") >= 1)
        #expect(Bodies.content == 0)
        unhost(w)
    }

    @Test func theCounterScaledHelperOutsideAScrollViewDrawsUnchanged() throws {
        CounterScaleProbe.last = nil
        let w = host(Color.purple.frame(width: 8, height: 8).ztronScrollCounterScaled())
        let v = try #require(CounterScaleProbe.last)
        #expect(v.zoom == 1 && CounterScaleEffect.transform(zoom: v.zoom, anchor: v.anchor, size: v.size) == .identity)
        unhost(w)
    }

    // MARK: (g) probe

    /// Step 0 of M6b L1: a `GeometryReader` below `ContentTransform` that reads only its size does not re-run its
    /// closure when only the effect's value changes (track steps, an animated offset, an animated zoom). Measured flat on
    /// the iOS 17.5 and 27.0 runtimes, both paths: this is what lets the iOS 15 host (`ContentOverlayReaderHost`) be a
    /// reader. The iOS 15 runtime itself (the only one that ships that host) is not measured here (no simulator).
    @Test(arguments: OSPath.allCases) func geometryReaderUnderTransformClosureRuns(path: OSPath) {
        let s = makeState(path)
        GRProbe.runs = 0
        let w = withOSPath(path) {
            host(ZTronScrollView(.vertical, state: s) { GRProbeContent() }
                .zoomRange(min: .absolute(1), max: .absolute(4)))
        }
        pump(0.3)
        #expect(GRProbe.runs >= 1 && GRProbe.size == CGSize(width: 200, height: 1000))   // the probe counts
        GRProbe.runs = 0
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 20 * CGFloat(i)), zoom: 1); pump(0.03) }
        let offsetOnly = GRProbe.runs
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 100), zoom: 1 + 0.2 * CGFloat(i)); pump(0.03) }
        let zoomSteps = GRProbe.runs - offsetOnly
        s.setContentOffset(CGPoint(x: 0, y: 300), animated: true); pump(1.0)
        let animatedOffset = GRProbe.runs - offsetOnly - zoomSteps
        s.setZoomScale(3, animated: true); pump(1.0)
        let animatedZoom = GRProbe.runs - offsetOnly - zoomSteps - animatedOffset
        print("[GRProbe] path=\(path) layout=\(s.usesLayoutProtocol) offsetTracks=\(offsetOnly) zoomTracks=\(zoomSteps) "
              + "animatedOffset=\(animatedOffset) animatedZoom=\(animatedZoom) zoom=\(s.zoomScale)")
        #expect(s.zoomScale == 3)
        #expect(GRProbe.runs == 0, "offset \(offsetOnly) zoom \(zoomSteps) animOffset \(animatedOffset) animZoom \(animatedZoom)")
        unhost(w)
    }

    // MARK: (h) the overlay does not change the measured content size

    @Test(arguments: OSPath.allCases) func overlaysDoNotChangeTheMeasuredContentSize(path: OSPath) {
        let plain = makeState(path), withOverlays = makeState(path)
        ZTronRenderCounters.reset()
        let w1 = withOSPath(path) { host(ZTronScrollView(.vertical, state: plain) { OverlaidContent() }) }
        pump(0.2)
        #expect(ZTronRenderCounters.value("contentOverlay.place") == 0)   // no overlay, no layout pass
        let w2 = withOSPath(path) {
            host(overlaid(ZTronScrollView(.vertical, state: withOverlays) { OverlaidContent() })
                .scrollContentIntegralOverlay(anchor: .center, overlayAnchor: .center, size: .absolute(CGSize(width: 900, height: 3000))) {
                    Color.gray
                })
        }
        pump(0.2)
        #expect(plain.peek.metrics.contentSize == CGSize(width: 200, height: 1000))
        #expect(withOverlays.peek.metrics.contentSize == plain.peek.metrics.contentSize)
        unhost(w1)
        unhost(w2)
    }
}
