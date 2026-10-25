import SwiftUI
import ZTronScrollView

// M8b-3: the scaling-header screens (docs/design/M8b-refresh-header.md §3, SPEC S14 "Refresh and header").
// `-ZTronScreen profile`: `.fixed(min: 64, max: 240)`, `.preserve`, `-ZTronHeaderSnap immediately|after|disabled` (default
// immediately), a `.system` refresher in the gap, the avatar scale and the title fade through the reader.
// `-ZTronScreen banner`: `-ZTronHeaderSize aspect|fixed|fit` (default aspect = `.aspectRatio(16/9)`), `.stretch`, a fade,
// the title font from the live height, an overlay refresher over the stretched band, a horizontal-axis toggle.
// Both show `content.body`, `header.builder`, `header.frame`, `refresh.actions`, `header.measure` and a `stateInfo` line
// (`y`, `p` progress, `h` height, `R` resting, `smax` largest stretch, `taps` header button taps) after `Info`.

enum HeaderDemo {
    static func argument(_ name: String, _ fallback: String) -> String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
        return fallback
    }

    static let keys = ["content.body", "header.builder", "header.frame", "refresh.actions", "header.measure"]

    /// The largest stretch and height the header's readers saw since the last reset (written by leaves, read by `Info`).
    @MainActor static var maxStretch: CGFloat = 0
    @MainActor static var maxHeight: CGFloat = 0
    @MainActor static var taps = 0

    static func load() async { try? await Task.sleep(nanoseconds: 600_000_000) }
}

/// A content row that counts its own body: no collapse, stretch, snap or refresh may run it.
struct HeaderRow: View {
    let index: Int
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return Text("Row \(index)")
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
            .background(index % 2 == 0 ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
            .accessibilityIdentifier("header.row.\(index)")
    }
}

/// The controls and the readout shared by both screens.
struct HeaderDemoChrome: View {
    let state: ZTronScrollState
    @Binding var info: String
    @Binding var snapshot: [String: Int]
    var extra: AnyView = AnyView(EmptyView())

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Info") { readout() }.accessibilityIdentifier("Info")
                Button("Half") { state.snapHeader(to: .progress(0.5)) }.accessibilityIdentifier("header.half")
                Button("Collapse") { state.snapHeader(to: .collapsed) }.accessibilityIdentifier("header.collapse")
                Button("Expand") { state.snapHeader(to: .expanded) }.accessibilityIdentifier("header.expand")
                extra
            }
            HStack(spacing: 6) {
                ForEach(HeaderDemo.keys, id: \.self) { CounterRow(key: $0, value: snapshot[$0] ?? 0) }
            }
            Text(info).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(info)
        }
        .font(.caption)
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.endRefreshing()
        state.snapHeader(to: .expanded, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            #if DEBUG
            ZTronRenderCounters.reset()
            #endif
            HeaderDemo.maxStretch = 0
            HeaderDemo.maxHeight = 0
            HeaderDemo.taps = 0
        }
    }

    private func readout() {
        #if DEBUG
        snapshot = ZTronRenderCounters.snapshot
        #endif
        let g = state.headerGeometry
        info = String(format: "y=%.1f p=%.4f h=%.1f R=%.3f smax=%.1f hmax=%.1f taps=%d phase=%d", state.contentOffset.y,
                      g?.progress ?? -1, g?.height ?? -1, g?.restingHeight ?? -1, HeaderDemo.maxStretch, HeaderDemo.maxHeight,
                      HeaderDemo.taps, state.phase.rawValue)
    }
}

/// A button inside the header: hit-testable at every live height above 0.5.
struct HeaderTapButton: View {
    var body: some View {
        Button("Follow") { HeaderDemo.taps += 1 }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.85)))
            .accessibilityIdentifier("header.button")
    }
}

/// A childless accessibility element exactly as large as the header's live frame (a `.contain` container would report the
/// union of its children, overflow included): what the UI tests measure.
struct HeaderBox: View {
    var body: some View {
        Color.clear
            .accessibilityElement()
            .accessibilityLabel("header box")
            .accessibilityIdentifier("header.box")
    }
}

/// Records the largest stretch / height it saw (a per-frame reader: it is a leaf, nothing else runs).
struct HeaderProbe: View {
    let header: ZTronHeaderProxy
    var body: some View {
        ZTronHeaderGeometryReader(header) { g in
            let _ = HeaderDemo.maxStretch = max(HeaderDemo.maxStretch, g.stretch)
            let _ = HeaderDemo.maxHeight = max(HeaderDemo.maxHeight, g.height)
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

// MARK: Profile

struct ProfileScreen: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]

    private var snap: ZTronHeaderSnap {
        switch HeaderDemo.argument("-ZTronHeaderSnap", "immediately") {
        case "after": return .afterFinishAccelerating()
        case "disabled": return .disabled
        default: return .immediately()
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HeaderDemoChrome(state: state, info: $info, snapshot: $snapshot)
            ZTronScrollView(.vertical, state: state) {
                VStack(spacing: 0) { ForEach(0..<40, id: \.self) { HeaderRow(index: $0) } }
            }
            .withScalingHeader(size: .fixed(min: 64, max: 240), scalingBehavior: .preserve, snap: snap) { header in
                ProfileHeader(header: header)
            }
            .refresher(style: .system) { await HeaderDemo.load() }
            .border(Color.gray)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("header.scroller")
        }
        .padding(.horizontal, 6)
    }
}

struct ProfileHeader: View {
    let header: ZTronHeaderProxy
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 12) {
                // The avatar shrinks with the collapse; the title fades. Each is its own reader: the header around them
                // never re-runs.
                ZTronHeaderGeometryReader(header, of: { 1 - 0.5 * $0.progress }) { scale in
                    Circle().fill(Color.orange).frame(width: 72, height: 72).scaleEffect(scale, anchor: .bottomLeading)
                }
                ZTronHeaderGeometryReader(header, of: { (20 * (1 - $0.progress)).rounded() / 20 }) { opacity in
                    Text("Profile").font(.title2.bold()).foregroundColor(.white).opacity(opacity)
                }
                Spacer()
                HeaderTapButton()
            }
            .padding(10)
            HeaderProbe(header: header)
        }
        // Takes the live frame even when the avatar row is taller (the overflow is clipped, the row stays glued to the
        // bottom edge): the root's frame IS the header's live height for the UI tests.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
        .background(HeaderBox())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("header.root")
    }
}

// MARK: Banner

struct BannerScreen: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]
    @State private var horizontal = HeaderDemo.argument("-ZTronBannerAxis", "vertical") == "horizontal"

    private var size: ZTronHeaderSize {
        switch HeaderDemo.argument("-ZTronHeaderSize", "aspect") {
        case "fixed": return .fixed(min: 0, max: 200)
        case "fit": return .fit()
        default: return .aspectRatio(16.0 / 9.0)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HeaderDemoChrome(state: state, info: $info, snapshot: $snapshot, extra: AnyView(
                Button(horizontal ? "Vertical" : "Horizontal") { horizontal.toggle() }.accessibilityIdentifier("banner.axis")))
            scroller
                .id(horizontal)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("header.scroller")
        }
        .padding(.horizontal, 6)
    }

    private var scroller: some View {
        ZTronScrollView(horizontal ? .horizontal : .vertical, state: state) {
            if horizontal {
                HStack(spacing: 0) { ForEach(0..<20, id: \.self) { HeaderRow(index: $0).frame(width: 120) } }
            } else {
                VStack(spacing: 0) { ForEach(0..<40, id: \.self) { HeaderRow(index: $0) } }
            }
        }
        .withScalingHeader(size: size, scalingBehavior: .stretch, fade: .linear(to: .black, from: 0.4)) { header in
            BannerHeader(header: header)
        }
        .refresher(overlay: true) { await HeaderDemo.load() }
    }
}

struct BannerHeader: View {
    let header: ZTronHeaderProxy
    var body: some View {
        // `.fit` measures this: a 16:9 picture has an ideal height at the scroll view's width.
        Image("app.global.about.us.snapshot")
            .resizable()
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .bottomLeading) { BannerTitle(header: header).padding(10) }
            .overlay(alignment: .topTrailing) { HeaderTapButton().padding(10) }
            .overlay(HeaderProbe(header: header))
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(HeaderBox())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("header.root")
    }
}

/// The "sticky overlay": follows the live bottom edge by layout, resizes its font through the reader.
struct BannerTitle: View {
    let header: ZTronHeaderProxy
    var body: some View {
        ZTronHeaderGeometryReader(header, of: { $0.height.rounded() }) { h in
            Text("Banner").font(.system(size: 17 + 0.08 * h, weight: .bold)).foregroundColor(.white)
                .accessibilityIdentifier("banner.title")
        }
    }
}
