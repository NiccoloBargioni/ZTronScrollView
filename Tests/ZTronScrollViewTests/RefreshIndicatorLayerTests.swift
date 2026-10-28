import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Open item 18 (D65 review): a refresh hold under an uncapped 16:9 `.preserve` `.openGap` header taller than the viewport
/// (landscape, R 491 pt over 402) puts the gap, and the indicator in it, below the screen. The indicator was placed in the
/// viewport's frame with no layer of its own, so SwiftUI drew no layer for it there: in a system rotation Core Animation had
/// nothing to interpolate, the indicator vanished on the way out and, on the way back, appeared at once at its final place,
/// over the header that was still shrinking (seam lab, 27.0 / 17.5 / forced: 5-6 of 32-34 rotation frames drawn). The
/// indicator box is now its own layer group, laid out at the gap (`RefreshPlacementEffect`), so it keeps its layer below
/// the screen and rotates with the header and the content. `.stretch` the same: its overlay
/// indicator's placement was nil there (the clip from a base below the screen to the viewport's edge was empty). Checked
/// on the hosted layer tree, both OS paths (17+ `geometryGroup()`, 15–16 `compositingGroup()`).
@MainActor
@Suite(.serialized)
struct RefreshIndicatorLayerTests {
    /// A colour no other view of the host draws.
    static let marker = (r: 0.11, g: 0.22, b: 0.33)

    struct Host: View {
        let state: ZTronScrollState
        let behavior: ZTronHeaderScalingBehavior
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Color.green.frame(height: 3000) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), scalingBehavior: behavior) { _ in Color.red }
                .refresher(refreshView: { _ in
                    Color(red: RefreshIndicatorLayerTests.marker.r, green: RefreshIndicatorLayerTests.marker.g,
                          blue: RefreshIndicatorLayerTests.marker.b)
                        .frame(width: 20, height: 20)
                }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
        }
    }

    /// The window frames of the layers filled with the marker colour; `presented`: as drawn now (the presentation tree,
    /// where Core Animation interpolates), else the model values.
    func markerFrames(in window: UIWindow, presented: Bool = false) -> [CGRect] {
        var out: [CGRect] = []
        let root = presented ? (window.layer.presentation() ?? window.layer) : window.layer
        func visit(_ layer: CALayer) {
            if let c = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - Self.marker.r) < 0.02, abs(g - Self.marker.g) < 0.02, abs(b - Self.marker.b) < 0.02 {
                    out.append(layer.convert(layer.bounds, to: root))
                }
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root)
        return out
    }

    /// Hosts the view in a `size` window, begins refreshing and returns the marker's layer frames with the indicator's
    /// place (`[base, base + 60]` in the window: the `.openGap` gap `[aci.top − hold, aci.top]`, the `.stretch` band's
    /// `[top0 + R, … + 60]`) and the resting header height.
    func hold(path: OSPath, size: CGSize, behavior: ZTronHeaderScalingBehavior = .preserve)
        -> (frames: [CGRect], gap: ClosedRange<CGFloat>, resting: CGFloat, height: CGFloat) {
        let s = makeState(path)
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(origin: .zero, size: size))
            w.rootViewController = UIHostingController(rootView: Host(state: s, behavior: behavior))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        s.beginRefreshing()
        pump(0.5)
        let m = s.peek.metrics
        let base = RefreshIndicatorMath.base(edge: .top, metrics: m, overlay: false).0.top
        return (markerFrames(in: w), base...(base + 60), m.header?.resting ?? .nan, size.height)
    }

    func expectLayerInPlace(path: OSPath, behavior: ZTronHeaderScalingBehavior) {
        let label = "\(path) \(behavior)"
        // Portrait: the gap (band) is on the screen.
        let p = hold(path: path, size: CGSize(width: 402, height: 874), behavior: behavior)
        #expect(p.frames.count == 1, "\(label) portrait: marker layers \(p.frames)")
        if let f = p.frames.first {
            #expect(p.gap.contains(f.midY) && p.gap.upperBound < p.height, "\(label) portrait: marker \(f) place \(p.gap)")
            #expect(abs(f.midX - 201) < 0.5, "\(label) portrait: marker \(f)")
        }
        // Landscape: R 491 pt over a 402 pt viewport, the indicator's place below the screen; it keeps its layer there.
        let l = hold(path: path, size: CGSize(width: 874, height: 402), behavior: behavior)
        #expect(l.resting > l.height, "\(label) landscape: R \(l.resting)")
        #expect(l.gap.lowerBound > l.height, "\(label) landscape: place \(l.gap) below the screen")
        #expect(l.frames.count == 1, "\(label) landscape: marker layers \(l.frames)")
        if let f = l.frames.first {
            #expect(l.gap.contains(f.midY), "\(label) landscape: marker \(f) place \(l.gap)")
            #expect(abs(f.midX - 437) < 0.5, "\(label) landscape: marker \(f)")
        }
    }

    /// `.preserve` `.openGap` (the default): the gap below the still header.
    @Test(arguments: OSPath.allCases)
    func theOpenGapHoldIndicatorKeepsItsLayerInItsGap(path: OSPath) {
        expectLayerInPlace(path: path, behavior: .preserve)
    }

    /// `.stretch`: the indicator floats over the band the hold stretches (overlay placement, its base `top0 + R`).
    @Test(arguments: OSPath.allCases)
    func theStretchHoldIndicatorKeepsItsLayerOverItsBand(path: OSPath) {
        expectLayerInPlace(path: path, behavior: .stretch)
    }

    final class Width: ObservableObject { @Published var narrow = false }

    struct ResizeHost: View {
        let state: ZTronScrollState
        @ObservedObject var width: Width
        var body: some View {
            Host(state: state, behavior: .preserve).frame(width: width.narrow ? 241 : 402)
        }
    }

    /// The box stays laid out, so a `withAnimation` width change during the hold (R 226 → 136 pt, the gap moves up 90 pt
    /// with the header) draws the indicator part way at mid animation (as drawn: the presentation tree). Placed by a
    /// render-time translation instead (an intermediate fix, animatable or not), it landed at its new place in the first
    /// frame while the header shrank (seam lab, 17.5: 88 pt above the gap, over the header; here `mid == end`).
    @Test(arguments: OSPath.allCases)
    func anAnimatedResizeMovesTheIndicatorWithTheGap(path: OSPath) {
        let s = makeState(path), width = Width()
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: ResizeHost(state: s, width: width))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        s.beginRefreshing()
        pump(0.5)
        let start = markerFrames(in: w).first?.midY ?? .nan
        withAnimation(.linear(duration: 1.2)) { width.narrow = true }
        pump(0.5)
        let mid = markerFrames(in: w, presented: true).first?.midY ?? .nan
        pump(1.2)
        let end = markerFrames(in: w).first?.midY ?? .nan
        #expect(start - end > 80, "\(path): the gap moves up with R (\(start) -> \(end))")
        #expect(mid < start - 10 && mid > end + 10, "\(path): part way at mid animation: \(start) -> \(mid) -> \(end)")
    }

    // MARK: Final check of D65: the 15–16 indicator group only under a header

    final class HeaderToggle: ObservableObject { @Published var on = false }

    struct BlendHost: View {
        @ObservedObject var header: HeaderToggle
        let state: ZTronScrollState
        var body: some View {
            let view = ZTronScrollView(.vertical, state: state) { Color.green.frame(height: 3000) }
            // The same view type either way (`withScalingHeader` returns `Self`): toggling keeps the identity.
            (header.on ? view.withScalingHeader(size: .fixed(min: 0, max: 100)) { _ in Color.red } : view)
                .refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20).blendMode(.difference) }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
        }
    }

    /// The 15–16 group (`compositingGroup()`) composites a custom indicator alone: its blend modes no longer reach what is
    /// behind it (forced lane, no header: a `.difference` white probe stayed white where 17+ and fb1fe59 blend it,
    /// `RefreshUITests.testACustomIndicatorsBlendModeReachesWhatIsBehindIt`). Open item 18 needs the group only under a
    /// scaling header, so 15–16 group the box only there, latched at the box's first frame: installing or removing the
    /// header during the hold keeps the indicator's identity. (A logic-test host has no render server, so this checks the
    /// latched branch; the header case's layers are checked above.)
    @Test(arguments: OSPath.allCases, [false, true])
    func theFifteenIndicatorGroupIsOnlyUnderAHeader(path: OSPath, headerFirst: Bool) {
        #if DEBUG
        ZTronRenderCounters.reset()
        let s = makeState(path), header = HeaderToggle()
        header.on = headerFirst
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: BlendHost(header: header, state: s))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        pump(0.4)
        #expect(ZTronRenderCounters.notes["refresh.group"] == nil, "\(path): no indicator box before the hold")
        s.beginRefreshing()
        pump(0.5)
        let first = ZTronRenderCounters.notes["refresh.group"]
        header.on.toggle()   // install / remove the header during the hold
        pump(0.5)
        let after = ZTronRenderCounters.notes["refresh.group"]
        #expect(s.refresh?.states[.top]?.mode == .refreshing, "\(path): still held")
        if path == .preferred {
            #expect(first == nil && after == nil, "17+: geometryGroup, no latch (\(String(describing: first)))")
        } else {
            #expect(first == (headerFirst ? "compositing" : "none"), "\(path) header first \(headerFirst): \(String(describing: first))")
            #expect(after == first, "\(path): the latch never re-decides during the hold (\(String(describing: after)))")
        }
        #endif
    }
}
