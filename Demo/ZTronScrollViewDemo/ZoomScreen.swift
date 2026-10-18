import SwiftUI
import ZTronScrollView

/// Counts zoom callbacks (outside any view body).
@MainActor
final class ZoomProbe: ZTronScrollViewDelegate {
    var order: [String] = []
    private var wasBouncing = false
    func scrollViewDidZoom(_ state: ZTronScrollState) {
        #if DEBUG
        ZTronRenderCounters.increment("zoom.didZoom")
        if state.isZoomBouncing, !wasBouncing { ZTronRenderCounters.increment("zoom.bounce") }
        #endif
        wasBouncing = state.isZoomBouncing
    }
    func scrollViewDidScroll(_ state: ZTronScrollState) {
        #if DEBUG
        ZTronRenderCounters.increment("zoom.didScroll")
        #endif
    }
    func scrollViewWillBeginZooming(_ state: ZTronScrollState) { order.append("willBeginZooming") }
    func scrollViewDidEndZooming(_ state: ZTronScrollState, atScale scale: CGFloat) {
        order.append(String(format: "didEndZooming(%.3f)", scale))
        wasBouncing = false
    }
    func scrollViewWillBeginDragging(_ state: ZTronScrollState) { order.append("willBeginDragging") }
    func reset() { order = []; wasBouncing = false }
}

/// 12 x 12 grid of 50 pt cells; the body counts itself and has no inputs.
struct ZoomGrid: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return VStack(spacing: 0) {
            ForEach(0..<12, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { c in
                        if r == 0 && c == 0 {
                            Button("0,0") {
                                #if DEBUG
                                ZTronRenderCounters.increment("button.fired")
                                #endif
                            }
                            .accessibilityIdentifier("cell.button")
                            .frame(width: 50, height: 50).background(Color.orange.opacity(0.4))
                        } else {
                            Text("\(r),\(c)").font(.system(size: 10))
                                .frame(width: 50, height: 50)
                                .background((r + c) % 2 == 0 ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 600)
    }
}

struct ZoomScreen: View {
    static let viewport = CGSize(width: 300, height: 360)
    private static let keys = ["content.body", "zoom.didZoom", "zoom.didScroll", "zoom.bounce", "reader.zoomOnly",
                               "button.fired", "clock.tick"]
    @State private var state = ZTronScrollState()
    @State private var probe = ZoomProbe()
    @State private var snapshot: [String: Int] = [:]
    @State private var stateInfo = ""

    private static var maxZoom: CGFloat {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-ZTronZoomMax"), i + 1 < a.count, let v = Double(a[i + 1]) { return CGFloat(v) }
        return 8
    }
    private static var doubleTap: Bool { ProcessInfo.processInfo.arguments.contains("-ZTronDoubleTap") }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Snapshot") { takeSnapshot() }.accessibilityIdentifier("Snapshot")
            }
            ZTronScrollView([.horizontal, .vertical], state: state) { ZoomGrid() }
                .zoomRange(min: .absolute(1), max: .absolute(Self.maxZoom))
                .doubleTapToZoom(Self.doubleTap)
                .frame(width: Self.viewport.width, height: Self.viewport.height)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scroller")
            ZTronScrollReader(state, of: { (g: ZTronScrollGeometry) -> CGFloat in g.zoomScale }) { (z: CGFloat) in
                CountedLabel(key: "reader.zoomOnly", text: String(format: "zoom %.2f", z))
            }
            VStack(spacing: 0) {
                ForEach(Self.keys, id: \.self) { CounterRow(key: $0, value: snapshot[$0] ?? 0) }
            }
            Text(stateInfo).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(stateInfo)
        }
        .padding(8)
        .onAppear { state.delegate = probe }
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.setZoomScale(1, animated: false)
        state.setContentOffset(.zero, animated: false)
        probe.reset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            #if DEBUG
            ZTronRenderCounters.reset()
            #endif
        }
    }

    private func takeSnapshot() {
        #if DEBUG
        snapshot = ZTronRenderCounters.snapshot
        #endif
        let z = state.zoomScale, o = state.contentOffset
        // Unscaled content point under the viewport center (content is larger than the viewport: no centering pad).
        let ux = (o.x + Self.viewport.width / 2) / z, uy = (o.y + Self.viewport.height / 2) / z
        stateInfo = String(format: "phase=%d z=%.4f ox=%.2f oy=%.2f ux=%.2f uy=%.2f zooming=%d bouncing=%d order=%@",
                           state.phase.rawValue, z, o.x, o.y, ux, uy, state.isZooming ? 1 : 0,
                           state.isZoomBouncing ? 1 : 0, probe.order.joined(separator: ","))
    }
}
