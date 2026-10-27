import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Open item 18 (D65 review): a refresh hold under an uncapped 16:9 `.preserve` `.openGap` header taller than the viewport
/// (landscape, R 491 pt over 402) puts the gap, and the indicator in it, below the screen. The indicator was placed in the
/// viewport's frame with no layer of its own, so SwiftUI drew no layer for it there: in a system rotation Core Animation had
/// nothing to interpolate, the indicator vanished on the way out and, on the way back, appeared at once at its final place,
/// over the header that was still shrinking (seam lab, 27.0 / 17.5 / forced: 5-6 of 32-34 rotation frames drawn). The
/// indicator box is now its own layer group, moved to the gap by a render-time transform (`RefreshPlacementEffect`), so it
/// keeps its layer below the screen and rotates with the header and the content. Checked on the hosted layer tree, both
/// OS paths (17+ `geometryGroup()`, 15–16 `compositingGroup()`).
@MainActor
@Suite(.serialized)
struct RefreshIndicatorLayerTests {
    /// A colour no other view of the host draws.
    static let marker = (r: 0.11, g: 0.22, b: 0.33)

    struct Host: View {
        let state: ZTronScrollState
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Color.green.frame(height: 3000) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64)) { _ in Color.red }
                .refresher(refreshView: { _ in
                    Color(red: RefreshIndicatorLayerTests.marker.r, green: RefreshIndicatorLayerTests.marker.g,
                          blue: RefreshIndicatorLayerTests.marker.b)
                        .frame(width: 20, height: 20)
                }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
        }
    }

    /// The window frames of the layers filled with the marker colour.
    func markerFrames(in window: UIWindow) -> [CGRect] {
        var out: [CGRect] = []
        func visit(_ layer: CALayer) {
            if let c = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - Self.marker.r) < 0.02, abs(g - Self.marker.g) < 0.02, abs(b - Self.marker.b) < 0.02 {
                    out.append(layer.convert(layer.bounds, to: window.layer))
                }
            }
            layer.sublayers?.forEach(visit)
        }
        visit(window.layer)
        return out
    }

    /// Hosts the view in a `size` window, begins refreshing and returns the marker's layer frames with the gap the hold
    /// keeps open (`[aci.top − hold, aci.top]` in the window, the `.openGap` base) and the resting header height.
    func hold(path: OSPath, size: CGSize) -> (frames: [CGRect], gap: ClosedRange<CGFloat>, resting: CGFloat, height: CGFloat) {
        let s = makeState(path)
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(origin: .zero, size: size))
            w.rootViewController = UIHostingController(rootView: Host(state: s))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        s.beginRefreshing()
        pump(0.5)
        let m = s.peek.metrics
        let top = m.adjustedContentInset.top
        return (markerFrames(in: w), (top - m.refreshHold.top)...top, m.header?.resting ?? .nan, size.height)
    }

    @Test(arguments: OSPath.allCases)
    func theHoldIndicatorKeepsItsLayerInItsGap(path: OSPath) {
        // Portrait: the gap is on the screen.
        let p = hold(path: path, size: CGSize(width: 402, height: 874))
        #expect(p.frames.count == 1, "\(path) portrait: marker layers \(p.frames)")
        if let f = p.frames.first {
            #expect(p.gap.contains(f.midY) && p.gap.upperBound < p.height, "\(path) portrait: marker \(f) gap \(p.gap)")
            #expect(abs(f.midX - 201) < 0.5, "\(path) portrait: marker \(f)")
        }
        // Landscape: R 491 pt over a 402 pt viewport, the gap below the screen; the indicator keeps its layer there.
        let l = hold(path: path, size: CGSize(width: 874, height: 402))
        #expect(l.resting > l.height, "\(path) landscape: R \(l.resting)")
        #expect(l.gap.lowerBound > l.height, "\(path) landscape: gap \(l.gap) below the screen")
        #expect(l.frames.count == 1, "\(path) landscape: marker layers \(l.frames)")
        if let f = l.frames.first {
            #expect(l.gap.contains(f.midY), "\(path) landscape: marker \(f) gap \(l.gap)")
            #expect(abs(f.midX - 437) < 0.5, "\(path) landscape: marker \(f)")
        }
    }
}
