import SwiftUI
import ZTronScrollView

/// Records offset extremes and callbacks for the pan UI tests (outside any view body).
@MainActor
final class PanProbe: ZTronScrollViewDelegate {
    var minY: CGFloat = 0
    var maxY: CGFloat = 0
    var order: [String] = []
    func scrollViewDidScroll(_ state: ZTronScrollState) {
        #if DEBUG
        ZTronRenderCounters.increment("didScroll")
        #endif
        minY = min(minY, state.contentOffset.y)
        maxY = max(maxY, state.contentOffset.y)
    }
    func scrollViewWillBeginDragging(_ state: ZTronScrollState) { order.append("willBeginDragging") }
    func scrollViewDidEndDragging(_ state: ZTronScrollState, willDecelerate decelerate: Bool) {
        order.append("didEndDragging(\(decelerate))")
    }
    func scrollViewDidEndDecelerating(_ state: ZTronScrollState) { order.append("didEndDecelerating") }
    func reset() { minY = 0; maxY = 0; order = [] }
}

/// Every row is a Button (counts `button.fired`); the content has no inputs so its body must never run.
struct PanContent: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return VStack(spacing: 4) {
            ForEach(0..<80, id: \.self) { i in
                Button {
                    #if DEBUG
                    ZTronRenderCounters.increment("button.fired")
                    #endif
                } label: {
                    Text("Row \(i)").frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.green.opacity(0.2))
                }
                .accessibilityIdentifier("row.\(i)")
            }
        }
    }
}

struct PanScreen: View {
    private static let keys = ["content.body", "didScroll", "button.fired", "clock.tick"]
    @State private var state = ZTronScrollState()
    @State private var probe = PanProbe()
    @State private var snapshot: [String: Int] = [:]
    @State private var stateInfo = ""

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Snapshot") { takeSnapshot() }.accessibilityIdentifier("Snapshot")
            }
            ZTronScrollView(.vertical, state: state) { PanContent() }
                .frame(height: 360)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scroller")
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
        stateInfo = "phase=\(state.phase.rawValue) y=\(Int(state.contentOffset.y)) minY=\(Int(probe.minY)) maxY=\(Int(probe.maxY)) order=\(probe.order.joined(separator: ","))"
    }
}
