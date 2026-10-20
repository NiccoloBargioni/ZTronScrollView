import SwiftUI
import ZTronScrollView

/// N-b: nested arbitration (docs/design/NESTED-arbitration.md). An outer paging `ZTronScrollView` (3 pages) whose page 0
/// is a 16:9 zoomer (`ZTronScrollView([.horizontal, .vertical])`, zoom 1…4, double tap), page 1 a plain vertical list,
/// page 2 static text. The inner's policy comes from `-ZTronNestedPolicy automatic|innerWhenZoomed|independent|inner|outer`
/// (default `.automatic`). The readout (Snapshot) lives outside both scrollers and reads their states.
struct NestedPagerScreen: View {
    static let page = CGSize(width: 300, height: 220)
    private static let keys = ["content.body", "pan.catch"]
    @State private var outer: ZTronScrollState
    @State private var zoomer = ZTronScrollState()
    @State private var list = ZTronScrollState()
    @State private var snapshot: [String: Int] = [:]
    @State private var stateInfo = ""

    init() {
        let s = ZTronScrollState()
        s.isPagingEnabled = true
        _outer = State(initialValue: s)
    }

    private static var policyName: String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-ZTronNestedPolicy"), i + 1 < a.count { return a[i + 1] }
        return "automatic"
    }

    private static var policy: ZTronNestedScrollPolicy {
        switch policyName {
        case "innerWhenZoomed": return .innerWhenZoomed
        case "independent": return .independent
        case "inner": return .inner
        case "outer": return .outer
        default: return .automatic
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Snapshot") { takeSnapshot() }.accessibilityIdentifier("Snapshot")
            }
            ZTronScrollView(.horizontal, state: outer) { row }
                .frame(width: Self.page.width, height: Self.page.height)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("nested.outer")
            VStack(spacing: 0) {
                ForEach(Self.keys, id: \.self) { CounterRow(key: $0, value: snapshot[$0] ?? 0) }
            }
            Text(stateInfo).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(stateInfo)
        }
        .padding(8)
    }

    private var row: some View {
        HStack(spacing: 0) {
            ZTronScrollView([.horizontal, .vertical], state: zoomer) { NestedZoomerContent() }
                .zoomRange(min: .absolute(1), max: .absolute(4))
                .doubleTapToZoom()
                .nestedScrollPolicy(Self.policy)
                .frame(width: Self.page.width, height: Self.page.height)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("nested.zoomer")
            ZTronScrollView(.vertical, state: list) { NestedListContent() }
                .frame(width: Self.page.width, height: Self.page.height)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("nested.list")
            NestedTextContent()
                .frame(width: Self.page.width, height: Self.page.height)
        }
    }

    private func reset() {
        for s in [outer, zoomer, list] {
            s.stopScrollingAndZooming()
            s.setZoomScale(1, animated: false)
            s.setContentOffset(.zero, animated: false)
        }
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
        let o = outer.contentOffset, z = zoomer.contentOffset, l = list.contentOffset
        let og = outer.geometry
        stateInfo = String(format: "policy=%@ page=%d ox=%.2f z=%.4f ix=%.2f iy=%.2f ly=%.2f ophase=%d iphase=%d lphase=%d ocw=%.0f ovw=%.0f icw=%.0f",
                           Self.policyName, Int((o.x / Self.page.width).rounded()), o.x, zoomer.zoomScale, z.x, z.y, l.y,
                           outer.phase.rawValue, zoomer.phase.rawValue, list.phase.rawValue,
                           og.contentSize.width, og.containerSize.width, zoomer.geometry.contentSize.width)
    }
}

/// 16:9 content at the page width; the body counts itself and has no inputs.
struct NestedZoomerContent: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return ZStack {
            LinearGradient(colors: [.blue, .green, .yellow, .orange], startPoint: .leading, endPoint: .trailing)
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { c in
                            Text("\(r),\(c)").font(.system(size: 9)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(width: NestedPagerScreen.page.width)
    }
}

struct NestedListContent: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return VStack(spacing: 0) {
            ForEach(0..<40, id: \.self) { i in
                Text("Row \(i)").frame(width: NestedPagerScreen.page.width, height: 44)
                    .background(i % 2 == 0 ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
            }
        }
    }
}

struct NestedTextContent: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return Text("Page 3").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.orange.opacity(0.3))
    }
}
