import SwiftUI
import ZTronScrollView

/// M8b-2: the refresher gallery (docs/design/M8b-refresh-header.md §3). The section comes from
/// `-ZTronRefreshSection system|default|overlay|custom|completion|loadMore|horizontal|refreshable` (default `system`);
/// every section shows `refresh.actions` and `content.body` and has `Info` / `Reset` buttons that write the readout.
struct RefreshScreen: View {
    static var section: String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-ZTronRefreshSection"), i + 1 < a.count { return a[i + 1] }
        return "system"
    }

    var body: some View {
        RefreshSectionView(section: Self.section)
    }
}

/// A row that counts its own body: nothing in a pull, hold or reset may run it.
struct RefreshRow: View {
    let index: Int
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return Text("Row \(index)")
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .background(index % 2 == 0 ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
    }
}

/// The custom indicator of the `custom` section: the whole state as text, so a test can read it.
struct RefreshLoader: View {
    @Binding var state: ZTronRefreshState
    init(_ state: Binding<ZTronRefreshState>) { _state = state }

    var body: some View {
        let mode: String
        switch state.mode {
        case .notRefreshing: mode = "idle"
        case .pulling: mode = "pulling"
        case .refreshing: mode = "refreshing"
        }
        return HStack(spacing: 6) {
            Circle().fill(Color.orange).frame(width: 12 + 16 * state.dragPosition, height: 12 + 16 * state.dragPosition)
            Text(mode).font(.caption2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("refresh.custom.mode")
        .accessibilityValue(mode)
    }
}

struct RefreshSectionView: View {
    let section: String
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var trace = ""
    @State private var snapshot: [String: Int] = [:]
    @State private var rows = 20
    private static let keys = ["refresh.actions", "content.body", "refresh.host.body", "chromeLeaf.body"]

    /// The simulated load: half a second plus the minimum visible time of the configuration.
    private func load() async {
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Info") { readout() }.accessibilityIdentifier("Info")
                Button("Begin") { state.beginRefreshing() }.accessibilityIdentifier("refresh.begin")
                Button("End") { state.endRefreshing() }.accessibilityIdentifier("refresh.end")
            }
            VStack(spacing: 0) {
                ForEach(Self.keys, id: \.self) { CounterRow(key: $0, value: snapshot[$0] ?? 0) }
                Text(info).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(info)
                // The refresher's own DEBUG trace (what it drew and when its state machine moved), read after a gesture.
                Text(trace.isEmpty ? "-" : String(trace.suffix(40))).font(.system(size: 6)).lineLimit(1)
                    .accessibilityIdentifier("refresh.trace").accessibilityValue(trace)
            }
            scroller
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("refresh.list")
        }
        .font(.caption)
        .padding(6)
        .onAppear {
            #if DEBUG
            ZTronRenderCounters.eventCapacity = 600
            #endif
        }
    }

    @ViewBuilder private var scroller: some View {
        switch section {
        case "default":
            // The mandatory shape: trailing closure, default loader.
            ZTronScrollView(.vertical, state: state) { column(40) }
                .refresher { await load() }
                .frame(height: 360)
        case "overlay":
            ZTronScrollView(.vertical, state: state) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.indigo, .pink], startPoint: .top, endPoint: .bottom).frame(height: 180)
                    column(40)
                }
            }
            .refresher(overlay: true) { await load() }
            .frame(height: 360)
        case "custom":
            ZTronScrollView(.vertical, state: state) { column(40) }
                .refresher(refreshView: { RefreshLoader($0) }) { await load() }
                .frame(height: 360)
        case "completion":
            ZTronScrollView(.vertical, state: state) { column(40) }
                .refresher { done in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) { done() }
                }
                .frame(height: 360)
        case "loadMore":
            ZTronScrollView(.vertical, state: state) { column(rows) }
                .refresher { await load(); rows = 20 }
                .refresher(configuration: .loadMore) { await load(); rows += 10 }
                .frame(height: 360)
        case "horizontal":
            ZTronScrollView(.horizontal, state: state) {
                HStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { i in
                        RefreshRow(index: i).frame(width: 90, height: 120)
                    }
                }
            }
            .refresher { await load() }
            .frame(height: 140)
        case "refreshable":
            // `.refreshable` maps to a `.system` refresher on the top edge.
            ZTronScrollView(.vertical, state: state) { column(40) }
                .refreshable { await load() }
                .frame(height: 360)
        default:
            ZTronScrollView(.vertical, state: state) { column(40) }
                .refresher(style: .system) { await load() }
                .frame(height: 360)
        }
    }

    private func column(_ n: Int) -> some View {
        VStack(spacing: 0) { ForEach(0..<n, id: \.self) { RefreshRow(index: $0) } }
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.endRefreshing()
        state.setContentOffset(.zero, animated: false)
        rows = 20
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            #if DEBUG
            ZTronRenderCounters.reset()
            #endif
        }
    }

    private func readout() {
        #if DEBUG
        snapshot = ZTronRenderCounters.snapshot
        #endif
        info = String(format: "y=%.1f x=%.1f phase=%d rows=%d", state.contentOffset.y, state.contentOffset.x,
                      state.phase.rawValue, rows)
        #if DEBUG
        trace = ZTronRenderCounters.events.filter { $0.contains(" rf ") }.joined(separator: "\n")
        #endif
    }
}
