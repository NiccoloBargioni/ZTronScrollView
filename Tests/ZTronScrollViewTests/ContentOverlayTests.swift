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
    v.scrollContentIntegralOverlay(anchor: .relative(ZTronUnitPoint(x: 0.3, y: 0.65)), overlayAnchor: .center, size: .ideal) { Marker() }
        .scrollContentIntegralOverlay { Fill() }
        .scrollContentIntegralOverlay(anchor: .bottom, overlayAnchor: .bottom, size: .fillMaxWidth(16 / 9)) { Banner() }
        .scrollContentIntegralOverlay(anchor: .absolute(CGPoint(x: 20, y: 30)), size: .ideal) { Pin() }
        .scrollContentIntegralOverlay(anchor: .topLeading, size: .relative(ZTronUnitSize(width: 0.5, height: 0.2))) { RelativeBox() }
        .scrollContentIntegralOverlay(anchor: .center, overlayAnchor: .center, size: .ideal, scaling: .counterScaled) {
            ScaledMarker()
        }
}

/// The generalized sizes (M6b units) and a clamped relative anchor, content `200 × H`: see `expectGeneralizedFrames`.
@MainActor
private func generalized<C: View>(_ v: ZTronScrollView<C>) -> ZTronScrollView<C> {
    v.scrollContentIntegralOverlay(anchor: .top, overlayAnchor: .top, size: .fillMaxWidth(height: .absolute(40))) {
        Color.red.ztronScrollID("g.wabs")
    }
    .scrollContentIntegralOverlay(anchor: .center, overlayAnchor: .center, size: .fillMaxWidth(height: .relative(0.1))) {
        Color.orange.ztronScrollID("g.wrel")
    }
    .scrollContentIntegralOverlay(anchor: .bottom, overlayAnchor: .bottom, size: .fillMaxWidth(height: .aspectRatio(4))) {
        Color.yellow.ztronScrollID("g.war")
    }
    .scrollContentIntegralOverlay(anchor: .leading, overlayAnchor: .leading, size: .fillMaxHeight(width: .relative(0.25))) {
        Color.green.ztronScrollID("g.hrel")
    }
    .scrollContentIntegralOverlay(anchor: .leading, overlayAnchor: .leading, size: .fillMaxHeight(width: .aspectRatio(0.5))) {
        Color.blue.ztronScrollID("g.har")
    }
    .scrollContentIntegralOverlay(anchor: .trailing, overlayAnchor: .trailing, size: .fillMaxHeight(width: .absolute(12))) {
        Color.purple.ztronScrollID("g.habs")
    }
    .scrollContentIntegralOverlay(anchor: .bottomTrailing, overlayAnchor: .bottomTrailing,
                                  size: .relative(width: 0.5, height: 0.2)) {
        Color.gray.ztronScrollID("g.rel")
    }
    // (2, −1) clamps to (1, 0): the content's top-trailing corner, not (400, −1000).
    .scrollContentIntegralOverlay(anchor: .relative(ZTronUnitPoint(x: 2, y: -1)), overlayAnchor: .topTrailing, size: .ideal) {
        Color.black.frame(width: 10, height: 10).ztronScrollID("g.corner")
    }
    // The `.ideal` free axes: SwiftUI measures the view with that axis open and the filled one at the content's length.
    // Wrapped text, whose height depends on the width it is offered.
    .scrollContentIntegralOverlay(anchor: .center, overlayAnchor: .center, size: .fillMaxWidth(height: .ideal)) {
        wrappedCaption().ztronScrollID("g.wideal")
    }
    // A view whose width depends on the height it is offered: 0.1 × that height.
    .scrollContentIntegralOverlay(anchor: .trailing, overlayAnchor: .trailing, size: .fillMaxHeight(width: .ideal)) {
        Color.cyan.aspectRatio(0.1, contentMode: .fit).ztronScrollID("g.hideal")
    }
}

/// Several lines of text at the content's width (200): the `.fillMaxWidth(height: .ideal)` overlay of `generalized`.
@MainActor
private func wrappedCaption() -> some View {
    Text("A caption long enough to wrap over several lines at the content's width of two hundred points.")
        .font(.system(size: 17))
        .frame(maxWidth: .infinity)
}

/// `wrappedCaption()`'s own size at `width`, measured outside any scroll view (the reference both hosts must match).
@MainActor
private func wrappedCaptionSize(width: CGFloat) -> CGSize {
    UIHostingController(rootView: wrappedCaption())
        .sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
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
            (.relative(ZTronUnitSize(width: 0.5, height: 0.2)), CGSize(width: 150, height: 120)),
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
        #expect(same(resolve(.relative(ZTronUnitPoint(x: 0.3, y: 0.65)), .center, .ideal), CGRect(x: 65, y: 375, width: 50, height: 30)))
        // .absolute(A) pins the overlayAnchor point at A, whatever the content size.
        for c in [content, CGSize(width: 10, height: 10), .zero] {
            #expect(same(resolve(.absolute(CGPoint(x: 20, y: 30)), .bottom, .absolute(CGSize(width: 120, height: 40)), content: c),
                          CGRect(x: -40, y: -10, width: 120, height: 40)))
            #expect(same(resolve(.absolute(CGPoint(x: 20, y: 30)), .topLeading, .ideal, content: c),
                          CGRect(x: 20, y: 30, width: 50, height: 30)))
        }
        // .fillMaxSize: the content rect whatever the anchors.
        for anchor in [ZTronContentOverlayAnchor.center, .bottomTrailing, .relative(ZTronUnitPoint(x: 2, y: -1)), .absolute(CGPoint(x: 9, y: 9))] {
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
        #expect(same(resolve(.center, .topLeading, .relative(ZTronUnitSize(width: 0.5, height: 0.5)), content: noWidth),
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
        // k clamps to 0...1 (NaN → 0, +∞ → 1: the unit types, M6b units); negative or non-finite s → 0.
        #expect(same(resolve(.topLeading, .topLeading, .relative(ZTronUnitSize(width: -0.5, height: 0.2))), CGRect(x: 0, y: 0, width: 0, height: 120)))
        #expect(same(resolve(.topLeading, .topLeading, .relative(ZTronUnitSize(width: CGFloat.nan, height: .infinity))),
                     CGRect(x: 0, y: 0, width: 0, height: 600)))
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
                .scrollContentIntegralOverlay(anchor: .relative(ZTronUnitPoint(x: 0.5, y: 0.1)), overlayAnchor: .bottom,
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
                .scrollContentIntegralOverlay(anchor: .relative(ZTronUnitPoint(x: 0.3, y: 0.65)), overlayAnchor: .bottom, size: .ideal,
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

    // MARK: (i) unit types, normalization and the generalized sizes (M6b units, user request 2026-10-21)

    private func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    @Test func unitTypesClampToZeroOneAndNaNIsZero() {
        let table: [(CGFloat, CGFloat)] = [(-1, 0), (0, 0), (-0.0, 0), (0.5, 0.5), (1, 1), (2, 1), (.nan, 0),
                                           (.infinity, 1), (-.infinity, 0)]
        for (v, want) in table {
            #expect(ZTronUnitLength(v).value == want, "length \(v)")
            let s = ZTronUnitSize(width: v, height: 0.25), t = ZTronUnitSize(width: 0.25, height: v)
            #expect(s.width == want && s.height == 0.25 && t.width == 0.25 && t.height == want, "size \(v)")
            #expect(ZTronUnitSize(CGSize(width: v, height: v)) == ZTronUnitSize(width: want, height: want), "size \(v)")
            let p = ZTronUnitPoint(x: v, y: 0.75), q = ZTronUnitPoint(x: 0.75, y: v)
            #expect(p.x == want && p.y == 0.75 && q.x == 0.75 && q.y == want, "point \(v)")
            #expect(ZTronUnitPoint(UnitPoint(x: v, y: v)) == ZTronUnitPoint(x: want, y: want), "point \(v)")
        }
        // Literals go through the clamping initializer.
        let a: ZTronUnitLength = 0.25, b: ZTronUnitLength = 2, c: ZTronUnitLength = -1, d: ZTronUnitLength = 1
        let e: ZTronUnitLength = 2.5, f: ZTronUnitLength = -0.5, g: ZTronUnitLength = 0
        #expect(a.value == 0.25 && b == .full && c == .zero && d == .full && e == .full && f == .zero && g == .zero)
        #expect(ZTronUnitLength.zero.value == 0 && ZTronUnitLength.full.value == 1)
        #expect(ZTronUnitSize.zero.width == 0 && ZTronUnitSize.zero.height == 0)
        #expect(ZTronUnitSize.full.width == 1 && ZTronUnitSize.full.height == 1)
        // Equal values hash alike (−0 and every clamped negative included).
        #expect(Set([ZTronUnitLength(0), ZTronUnitLength(-0.0), ZTronUnitLength(-3), .zero, 0]).count == 1)
        #expect(Set([ZTronUnitPoint(x: 1, y: 0), ZTronUnitPoint(x: 9, y: -9), .topTrailing]).count == 1)
        // The nine named points are UnitPoint's, both ways.
        let named: [(ZTronUnitPoint, UnitPoint)] = [
            (.topLeading, .topLeading), (.top, .top), (.topTrailing, .topTrailing), (.leading, .leading), (.center, .center),
            (.trailing, .trailing), (.bottomLeading, .bottomLeading), (.bottom, .bottom), (.bottomTrailing, .bottomTrailing),
        ]
        for (z, u) in named {
            #expect(z.unitPoint == u, "\(z)")
            #expect(ZTronUnitPoint(u) == z, "\(u)")
        }
        #expect(ZTronUnitPoint(UnitPoint(x: 2, y: -1)) == .topTrailing)
    }

    @Test func sizesNormalizeWhenBuiltSoEqualRenderingValuesCompareEqual() {
        typealias S = ZTronContentOverlaySize
        // An unusable aspect ratio is `.ideal` on that axis.
        let idealW = S.fillMaxWidth(height: .ideal), idealH = S.fillMaxHeight(width: .ideal)
        #expect(S.fillMaxWidth() == idealW && S.fillMaxWidth(nil) == idealW)
        #expect(S.fillMaxHeight() == idealH && S.fillMaxHeight(nil) == idealH)
        for r in [CGFloat(0), -1, .infinity, -.infinity, .nan] {
            #expect(S.fillMaxWidth(r) == idealW && S.fillMaxWidth(height: .aspectRatio(r)) == idealW, "w \(r)")
            #expect(S.fillMaxHeight(r) == idealH && S.fillMaxHeight(width: .aspectRatio(r)) == idealH, "h \(r)")
        }
        // The sugar is the general form.
        #expect(S.fillMaxWidth(16 / 9) == S.fillMaxWidth(height: .aspectRatio(16 / 9)))
        #expect(S.fillMaxWidth(16.0 / 9.0) == S.fillMaxWidth(16 / 9))
        #expect(S.fillMaxHeight(0.5) == S.fillMaxHeight(width: .aspectRatio(0.5)))
        // Absolute lengths and sizes: negative or non-finite → 0.
        for v in [CGFloat(-5), .nan, .infinity, -.infinity] {
            #expect(S.fillMaxWidth(height: .absolute(v)) == S.fillMaxWidth(height: .absolute(0)), "w \(v)")
            #expect(S.fillMaxHeight(width: .absolute(v)) == S.fillMaxHeight(width: .absolute(0)), "h \(v)")
            #expect(S.absolute(CGSize(width: v, height: 7)) == S.absolute(CGSize(width: 0, height: 7)), "s.w \(v)")
            #expect(S.absolute(CGSize(width: 7, height: v)) == S.absolute(CGSize(width: 7, height: 0)), "s.h \(v)")
        }
        // Relative fractions clamp (unit types).
        #expect(S.fillMaxWidth(height: .relative(2)) == S.fillMaxWidth(height: .relative(.full)))
        #expect(S.fillMaxHeight(width: .relative(-1)) == S.fillMaxHeight(width: .relative(.zero)))
        #expect(S.fillMaxWidth(height: .relative(ZTronUnitLength(.nan))) == S.fillMaxWidth(height: .relative(0)))
        #expect(S.relative(ZTronUnitSize(width: 2, height: -1)) == S.relative(width: 1, height: 0))
        #expect(S.relative(ZTronUnitSize(CGSize(width: 0.5, height: 0.2))) == S.relative(width: 0.5, height: 0.2))
        #expect(S.relative(.full) == S.relative(width: 1, height: 1) && S.relative(.zero) == S.relative(width: 0, height: 0))
        // Different shapes stay different.
        let distinct: [S] = [.fillMaxSize, .ideal, .fillMaxWidth(), .fillMaxHeight(), .fillMaxWidth(2), .fillMaxWidth(3),
                             .fillMaxHeight(2), .fillMaxWidth(height: .absolute(40)), .fillMaxHeight(width: .absolute(40)),
                             .fillMaxWidth(height: .relative(0.5)), .fillMaxHeight(width: .relative(0.5)), .relative(.full),
                             .relative(width: 0.5, height: 0.2), .absolute(CGSize(width: 40, height: 40))]
        for i in distinct.indices {
            for j in distinct.indices where i != j {
                #expect(distinct[i] != distinct[j], "\(distinct[i]) vs \(distinct[j])")
            }
        }
        // A relative anchor clamps to the content; `.absolute` and `overlayAnchor` do not.
        #expect(ZTronContentOverlayAnchor.relative(ZTronUnitPoint(x: 2, y: -1)) == .relative(.topTrailing))
        #expect(ContentOverlayMath.anchorPoint(.relative(ZTronUnitPoint(x: 2, y: -1)), content: content) == CGPoint(x: 300, y: 0))
        #expect(ContentOverlayMath.anchorPoint(.absolute(CGPoint(x: -40, y: 900)), content: content) == CGPoint(x: -40, y: 900))
        #expect(same(resolve(.topLeading, UnitPoint(x: 2, y: -1), .absolute(CGSize(width: 10, height: 10))), rect(-20, 10, 10, 10)))
    }

    @Test func mathEveryFreeLengthOnBothAxes() {
        // Content 300 × 600, the view's own size 50 × 30 (`measure`).
        let heights: [(ZTronContentOverlayLength, CGFloat)] = [   // .fillMaxWidth(height:): width 300
            (.ideal, 30), (.aspectRatio(4), 75), (.aspectRatio(0.5), 600), (.absolute(40), 40), (.relative(0.1), 60),
            (.relative(1), 600), (.relative(0), 0),
        ]
        let widths: [(ZTronContentOverlayLength, CGFloat)] = [    // .fillMaxHeight(width:): height 600
            (.ideal, 50), (.aspectRatio(0.5), 300), (.aspectRatio(2), 1200), (.absolute(12), 12), (.relative(0.25), 75),
            (.relative(1), 300), (.relative(0), 0),
        ]
        let anchors: [(ZTronContentOverlayAnchor, CGPoint)] = [
            (.center, CGPoint(x: 150, y: 300)), (.bottomTrailing, CGPoint(x: 300, y: 600)),
            (.relative(ZTronUnitPoint(x: 0.3, y: 0.65)), CGPoint(x: 90, y: 390)), (.absolute(CGPoint(x: -20, y: 30)), CGPoint(x: -20, y: 30)),
        ]
        for (anchor, p) in anchors {
            for q in [UnitPoint.topLeading, .center, .bottomTrailing, UnitPoint(x: 0.25, y: 0.75)] {
                for (l, h) in heights {
                    let want = rect(p.x - q.x * 300, p.y - q.y * h, 300, h)
                    #expect(same(resolve(anchor, q, .fillMaxWidth(height: l)), want), "w \(anchor) \(q) \(l)")
                }
                for (l, w) in widths {
                    let want = rect(p.x - q.x * w, p.y - q.y * 600, w, 600)
                    #expect(same(resolve(anchor, q, .fillMaxHeight(width: l)), want), "h \(anchor) \(q) \(l)")
                }
                #expect(same(resolve(anchor, q, .relative(width: 0.5, height: 0.2)), rect(p.x - q.x * 150, p.y - q.y * 120, 150, 120)))
            }
        }
        // The proposal leaves the free axis open for `.ideal` only, and `measure` runs only then.
        #expect(ContentOverlayMath.proposal(.fillMaxWidth(height: .ideal), content: content) == OverlayProposal(width: 300, height: nil))
        #expect(ContentOverlayMath.proposal(.fillMaxHeight(width: .ideal), content: content) == OverlayProposal(width: nil, height: 600))
        var calls = 0
        let closed: [ZTronContentOverlaySize] = [.fillMaxWidth(height: .absolute(40)), .fillMaxWidth(height: .relative(0.1)),
                                                 .fillMaxWidth(height: .aspectRatio(4)), .fillMaxHeight(width: .absolute(12)),
                                                 .fillMaxHeight(width: .relative(0.25)), .fillMaxHeight(width: .aspectRatio(0.5)),
                                                 .relative(width: 0.5, height: 0.2)]
        for size in closed {
            _ = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: .center, overlayAnchor: .center, size: size),
                                           content: content) { _ in calls += 1; return .zero }
        }
        #expect(calls == 0)
        _ = ContentOverlayMath.resolve(ContentOverlayPlacement(anchor: .center, overlayAnchor: .center, size: .fillMaxHeight(width: .ideal)),
                                       content: content) { p in calls += 1; #expect(p == OverlayProposal(width: nil, height: 600)); return .zero }
        #expect(calls == 1)
        // Degenerate content. W = 0: the filled width is 0, an aspect height W / r is 0, an absolute or relative height
        // keeps its value; H = 0 mirrors it.
        let noWidth = CGSize(width: 0, height: 600), noHeight = CGSize(width: 300, height: 0)
        let tl = ZTronContentOverlayAnchor.topLeading, q0 = UnitPoint.topLeading
        #expect(same(resolve(tl, q0, .fillMaxWidth(height: .aspectRatio(4)), content: noWidth), rect(0, 0, 0, 0)))
        #expect(same(resolve(tl, q0, .fillMaxWidth(height: .absolute(40)), content: noWidth), rect(0, 0, 0, 40)))
        #expect(same(resolve(tl, q0, .fillMaxWidth(height: .relative(0.1)), content: noWidth), rect(0, 0, 0, 60)))
        #expect(same(resolve(tl, q0, .fillMaxWidth(height: .ideal), content: noWidth), rect(0, 0, 0, 30)))
        #expect(same(resolve(tl, q0, .fillMaxWidth(height: .relative(0.5)), content: noHeight), rect(0, 0, 300, 0)))
        #expect(same(resolve(tl, q0, .fillMaxWidth(height: .aspectRatio(4)), content: noHeight), rect(0, 0, 300, 75)))
        #expect(same(resolve(tl, q0, .fillMaxHeight(width: .aspectRatio(0.5)), content: noHeight), rect(0, 0, 0, 0)))
        #expect(same(resolve(tl, q0, .fillMaxHeight(width: .absolute(12)), content: noHeight), rect(0, 0, 12, 0)))
        #expect(same(resolve(tl, q0, .fillMaxHeight(width: .relative(0.25)), content: noHeight), rect(0, 0, 75, 0)))
        #expect(same(resolve(tl, q0, .fillMaxHeight(width: .ideal), content: noHeight), rect(0, 0, 50, 0)))
        #expect(same(resolve(tl, q0, .fillMaxHeight(width: .relative(0.25)), content: noWidth), rect(0, 0, 0, 600)))
        #expect(same(resolve(tl, q0, .fillMaxHeight(width: .aspectRatio(0.5)), content: noWidth), rect(0, 0, 300, 600)))
        #expect(same(resolve(tl, q0, .relative(width: 0.5, height: 0.2), content: .zero), .zero))
        #expect(same(resolve(.relative(.bottomTrailing), .bottomTrailing, .relative(width: 1, height: 1), content: .zero), .zero))
        // Negative or non-finite content counts as 0.
        #expect(same(resolve(tl, q0, .fillMaxWidth(height: .relative(0.5)), content: CGSize(width: -10, height: CGFloat.nan)), .zero))
        // Negative or non-finite free lengths, normalized when built: absolute → 0, aspect → `.ideal`, relative clamps.
        for v in [CGFloat(-5), .nan, .infinity] {
            #expect(same(resolve(tl, q0, .fillMaxWidth(height: .absolute(v))), rect(0, 0, 300, 0)), "\(v)")
            #expect(same(resolve(tl, q0, .fillMaxHeight(width: .absolute(v))), rect(0, 0, 0, 600)), "\(v)")
            #expect(same(resolve(tl, q0, .fillMaxWidth(height: .aspectRatio(v))), rect(0, 0, 300, 30)), "\(v)")
            #expect(same(resolve(tl, q0, .fillMaxHeight(width: .aspectRatio(v))), rect(0, 0, 50, 600)), "\(v)")
            let k = ZTronUnitLength(v).value
            #expect(same(resolve(tl, q0, .fillMaxWidth(height: .relative(ZTronUnitLength(v)))), rect(0, 0, 300, 600 * k)), "\(v)")
            #expect(same(resolve(tl, q0, .fillMaxHeight(width: .relative(ZTronUnitLength(v)))), rect(0, 0, 300 * k, 600)), "\(v)")
        }
        // A ratio so extreme that the length overflows counts as 0 (never an infinite frame).
        #expect(same(resolve(tl, q0, .fillMaxWidth(height: .aspectRatio(.leastNonzeroMagnitude))), rect(0, 0, 300, 0)))
        #expect(same(resolve(tl, q0, .fillMaxHeight(width: .aspectRatio(.greatestFiniteMagnitude))), rect(0, 0, 0, 600)))
        // Defensive on values the constructors exclude.
        #expect(ContentOverlayMath.axisLength(.aspectRatio(-1), sameAxis: 600) { 300 / $0 } == nil)
        #expect(ContentOverlayMath.axisLength(.aspectRatio(.nan), sameAxis: 600) { 300 / $0 } == nil)
        #expect(ContentOverlayMath.axisLength(.absolute(-3), sameAxis: 600) { $0 } == 0)
    }

    /// Compile-only: the agreed spellings type-check without ambiguity (a failure here is a build error, not a test
    /// failure).
    @Test func theAgreedSpellingsCompile() {
        let r: CGFloat = 2
        let sizes: [ZTronContentOverlaySize] = [
            .fillMaxWidth(), .fillMaxWidth(16 / 9), .fillMaxWidth(16.0 / 9.0), .fillMaxWidth(r), .fillMaxWidth(nil),
            .fillMaxWidth(height: .relative(0.2)), .fillMaxWidth(height: .absolute(40)), .fillMaxWidth(height: .aspectRatio(16 / 9)),
            .fillMaxWidth(height: .ideal), .fillMaxHeight(), .fillMaxHeight(0.5), .fillMaxHeight(width: .relative(0.25)),
            .fillMaxHeight(width: .absolute(12)), .relative(width: 0.5, height: 0.2), .relative(width: 1, height: 0),
            .relative(.full), .relative(.zero), .relative(ZTronUnitSize(width: 0.5, height: 0.2)),
            .relative(ZTronUnitSize(CGSize(width: 0.5, height: 0.2))), .absolute(CGSize(width: 120, height: 40)), .ideal,
            .fillMaxSize,
        ]
        let anchors: [ZTronContentOverlayAnchor] = [
            .center, .relative(.center), .relative(ZTronUnitPoint(x: 0.3, y: 0.65)),
            .relative(ZTronUnitPoint(UnitPoint(x: 0.3, y: 0.65))), .absolute(CGPoint(x: -20, y: 30)),
        ]
        let lengths: [ZTronContentOverlayLength] = [.ideal, .aspectRatio(16 / 9), .absolute(12), .relative(0.05), .relative(1), .relative(.full)]
        let view = ZTronScrollView(.vertical) { Color.red.frame(width: 10, height: 10) }
            .scrollContentIntegralOverlay(size: .fillMaxWidth(16 / 9)) { Color.blue }
            .scrollContentIntegralOverlay(anchor: .top, overlayAnchor: .top, size: .fillMaxWidth(height: .relative(0.05))) { Color.blue }
            .scrollContentIntegralOverlay(anchor: .trailing, overlayAnchor: .trailing, size: .fillMaxHeight(width: .absolute(12))) {
                Color.blue
            }
            .scrollContentIntegralOverlay(anchor: .relative(.topTrailing), size: .relative(width: 0.5, height: 0.2)) { Color.blue }
            .ztronScrollContentIntegralOverlay(size: .relative(.full)) { Color.blue }
        #expect(sizes.count == 22 && anchors.count == 5 && lengths.count == 6)
        _ = view
    }

    /// The DocC promise of `ZTronContentOverlaySize`, checked both ways: two sizes are `==` exactly when both hosts draw
    /// them alike, i.e. the same proposal for every content size and the same `.fillMaxSize`-ness (which drops the
    /// anchors). The proposal is all either host reads of a size besides that.
    @Test func sizesCompareEqualExactlyWhenTheyDrawAlike() {
        typealias S = ZTronContentOverlaySize
        // One size, several spellings.
        #expect(S.fillMaxWidth(height: .relative(1)) == .relative(.full))
        #expect(S.fillMaxHeight(width: .relative(1)) == .relative(.full))
        #expect(S.fillMaxWidth(height: .relative(0.3)) == .relative(width: 1, height: 0.3))
        #expect(S.fillMaxHeight(width: .relative(0.3)) == .relative(width: 0.3, height: 1))
        #expect(S.relative(.zero) == .absolute(.zero))
        #expect(S.fillMaxWidth(height: .relative(0)) == .fillMaxWidth(height: .absolute(0)))
        #expect(S.relative(width: 1, height: 0) == .fillMaxWidth(height: .absolute(-3)))
        #expect(S.relative(width: 0, height: 1) == .fillMaxHeight(width: .absolute(.nan)))
        #expect(S.relative(width: 0, height: 0.5) == .relative(width: -2, height: 0.5))
        #expect(S.fillMaxSize != .relative(.full), "fillMaxSize ignores the anchors")
        // Both ways, over many sizes (equal spellings included) and contents.
        let sizes: [S] = [
            .fillMaxSize, .ideal, .fillMaxWidth(), .fillMaxWidth(0), .fillMaxWidth(2), .fillMaxWidth(3), .fillMaxHeight(),
            .fillMaxHeight(2), .fillMaxHeight(0.5), .fillMaxWidth(height: .absolute(0)), .fillMaxWidth(height: .absolute(40)),
            .fillMaxWidth(height: .relative(0)), .fillMaxWidth(height: .relative(0.3)), .fillMaxWidth(height: .relative(1)),
            .fillMaxHeight(width: .absolute(0)), .fillMaxHeight(width: .absolute(40)), .fillMaxHeight(width: .relative(0)),
            .fillMaxHeight(width: .relative(0.3)), .fillMaxHeight(width: .relative(1)), .relative(.full), .relative(.zero),
            .relative(width: 1, height: 0.3), .relative(width: 0.3, height: 1), .relative(width: 1, height: 0),
            .relative(width: 0, height: 1), .relative(width: 0.5, height: 0.2), .relative(width: 0, height: 0.5),
            .absolute(.zero), .absolute(CGSize(width: 40, height: 40)), .absolute(CGSize(width: 0, height: 40)),
            .absolute(CGSize(width: 40, height: 0)),
        ]
        let contents = [CGSize.zero, CGSize(width: 300, height: 600), CGSize(width: 1, height: 1), CGSize(width: 7, height: 3),
                        CGSize(width: 0, height: 600), CGSize(width: 300, height: 0), CGSize(width: 123.5, height: 77.25),
                        CGSize(width: 40, height: 40)]
        func drawn(_ size: S) -> (Bool, [OverlayProposal]) {
            if case .fillMaxSize = size.kind { return (true, []) }
            return (false, contents.map { ContentOverlayMath.proposal(size, content: $0) })
        }
        var equalPairs = 0, unequalPairs = 0
        for i in sizes.indices {
            for j in sizes.indices where i != j {
                let alike = drawn(sizes[i]) == drawn(sizes[j])
                #expect((sizes[i] == sizes[j]) == alike, "\(sizes[i]) vs \(sizes[j]): alike \(alike)")
                if alike { equalPairs += 1 } else { unequalPairs += 1 }
            }
        }
        #expect(equalPairs >= 20 && unequalPairs > 500, "both directions exercised: \(equalPairs) / \(unequalPairs)")
    }

    /// A named anchor draws like the relative point of the same name; the values compare as written (the DocC).
    @Test func namedAnchorsDrawLikeTheirRelativePointsAndCompareAsWritten() {
        let pairs: [(ZTronContentOverlayAnchor, ZTronUnitPoint)] = [
            (.topLeading, .topLeading), (.top, .top), (.topTrailing, .topTrailing), (.leading, .leading), (.center, .center),
            (.trailing, .trailing), (.bottomLeading, .bottomLeading), (.bottom, .bottom), (.bottomTrailing, .bottomTrailing),
        ]
        for c in [CGSize.zero, CGSize(width: 300, height: 600), CGSize(width: 123.5, height: 77.25)] {
            for (named, u) in pairs {
                #expect(ContentOverlayMath.anchorPoint(named, content: c) == ContentOverlayMath.anchorPoint(.relative(u), content: c),
                        "\(named) \(c)")
            }
        }
        #expect(ZTronContentOverlayAnchor.center != .relative(.center))
        #expect(ZTronContentOverlayAnchor.relative(.center) == .relative(ZTronUnitPoint(x: 0.5, y: 0.5)))
    }

    /// A positive ratio is kept when the size is built; if its length overflows in layout it draws 0 and writes the note.
    @Test func anOverflowingAspectRatioDrawsZeroAndWritesTheNote() {
        let tl = ZTronContentOverlayAnchor.topLeading, q0 = UnitPoint.topLeading, key = "contentOverlay.badAspect"
        ZTronRenderCounters.notes[key] = nil
        let tiny = ZTronContentOverlaySize.fillMaxWidth(CGFloat.leastNonzeroMagnitude)
        #expect(tiny != .fillMaxWidth() && ZTronRenderCounters.notes[key] == nil, "a positive ratio is kept")
        #expect(same(resolve(tl, q0, tiny), rect(0, 0, 300, 0)))
        #expect(ZTronRenderCounters.notes[key] == "\(CGFloat.leastNonzeroMagnitude) overflows")
        ZTronRenderCounters.notes[key] = nil
        let huge = ZTronContentOverlaySize.fillMaxHeight(width: .aspectRatio(.greatestFiniteMagnitude))
        #expect(same(resolve(tl, q0, huge), rect(0, 0, 0, 600)))
        #expect(ZTronRenderCounters.notes[key] == "\(CGFloat.greatestFiniteMagnitude) overflows")
        // The same ratio on a content short enough not to overflow draws its length, without the note.
        ZTronRenderCounters.notes[key] = nil
        #expect(same(resolve(tl, q0, huge, content: CGSize(width: 300, height: 0.5)),
                     rect(0, 0, CGFloat.greatestFiniteMagnitude / 2, 0.5)))
        #expect(same(resolve(tl, q0, .fillMaxWidth(4)), rect(0, 0, 300, 75)))
        #expect(ZTronRenderCounters.notes[key] == nil)
    }

    private func expectGeneralizedFrames(_ s: ZTronScrollState, h H: CGFloat, _ label: String) {
        let r = s.targets
        // The caption's height at width 200 is several lines (a height-for-width view, not a fixed one).
        let t = wrappedCaptionSize(width: 200)
        let line = UIHostingController(rootView: Text("A").font(.system(size: 17)))
            .sizeThatFits(in: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude))
        #expect(t.width == 200 && t.height > 2 * line.height, "\(label) caption \(t), line \(line)")
        let expected: [(String, CGRect)] = [
            ("g.wabs", rect(0, 0, 200, 40)),                    // .top / .top, W × 40
            ("g.wrel", rect(0, 0.45 * H, 200, 0.1 * H)),        // .center / .center, W × 0.1 H
            ("g.war", rect(0, H - 50, 200, 50)),                // .bottom / .bottom, W × W / 4
            ("g.hrel", rect(0, 0, 50, H)),                      // .leading / .leading, 0.25 W × H
            ("g.har", rect(0, 0, 0.5 * H, H)),                  // .leading / .leading, 0.5 H × H
            ("g.habs", rect(188, 0, 12, H)),                    // .trailing / .trailing, 12 × H
            ("g.rel", rect(100, 0.8 * H, 100, 0.2 * H)),        // .bottomTrailing / .bottomTrailing, 0.5 W × 0.2 H
            ("g.corner", rect(190, 0, 10, 10)),                 // (2, −1) → (1, 0) / .topTrailing, ideal 10 × 10
            ("g.wideal", rect(0, 0.5 * H - t.height / 2, 200, t.height)),   // .center / .center, W × the text's height at W
            ("g.hideal", rect(200 - 0.1 * H, 0, 0.1 * H, H)),   // .trailing / .trailing, the view's width at H × H
        ]
        for (id, frame) in expected {
            #expect(close(r.frame(of: id), frame), "\(label) \(id): \(String(describing: r.frame(of: id))) != \(frame)")
        }
    }

    /// The generalized sizes and a clamped relative anchor on both hosts. A content-owned reflow re-places them by
    /// layout alone (no host, no overlay body); motion afterwards runs nothing at all.
    @Test(arguments: OSPath.allCases) func generalizedSizesLandOnBothHostsFollowAReflowAndStayStill(path: OSPath) {
        let s = makeState(path)
        let w = withOSPath(path) {
            host(generalized(ZTronScrollView(.vertical, state: s) { GrowingContent() })
                .zoomRange(min: .absolute(1), max: .absolute(4)))
        }
        pump(0.2)
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1000))
        expectGeneralizedFrames(s, h: 1000, "initial")
        Bodies.reset()
        ZTronRenderCounters.reset()
        withOSPath(path) { NotificationCenter.default.post(name: .contentOverlayGrow, object: nil); pump(0.3) }
        #expect(s.peek.metrics.contentSize == CGSize(width: 200, height: 1500))
        expectGeneralizedFrames(s, h: 1500, "grown")
        #expect(Bodies.content == 1, "the content's own change only")
        #expect(ZTronRenderCounters.value("contentOverlay.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") == 0, "no container evaluation")
        #expect(ZTronRenderCounters.value(s.usesLayoutProtocol ? "contentOverlay.place" : "contentOverlay.reader") >= 1)
        let writes = s.targets.writes
        Bodies.reset()
        ZTronRenderCounters.reset()
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 30 * CGFloat(i)), zoom: 1); pump(0.03) }
        for i in 1...5 { s.track(offset: CGPoint(x: 0, y: 150), zoom: 1 + 0.25 * CGFloat(i)); pump(0.03) }
        s.setContentOffset(CGPoint(x: 0, y: 400), animated: true); pump(1.0)
        #expect(ZTronRenderCounters.value("transform.effect") > 0)   // the motion was drawn
        #expect(Bodies.content == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.host.body") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.reader") == 0)
        #expect(ZTronRenderCounters.value("contentOverlay.place") == 0)
        #expect(s.targets.writes == writes, "the overlays' content-space frames never moved")
        unhost(w)
    }
}
