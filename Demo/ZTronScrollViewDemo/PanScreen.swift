import SwiftUI
import ZTronScrollView
#if canImport(UIKit)
import UIKit
#endif

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
    private var stamp: String { String(format: "@%.3f", Date().timeIntervalSince1970) }
    func scrollViewWillBeginDragging(_ state: ZTronScrollState) { order.append("willBeginDragging\(stamp)") }
    func scrollViewDidEndDragging(_ state: ZTronScrollState, willDecelerate decelerate: Bool) {
        order.append("didEndDragging(\(decelerate))\(stamp)")
    }
    func scrollViewDidEndDecelerating(_ state: ZTronScrollState) { order.append("didEndDecelerating\(stamp)") }
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
                .pressScrollHooked()
                .accessibilityIdentifier("row.\(i)")
            }
        }
    }
}

/// Fires `tick` every 30 ms; only exists under `-ZTronCancelProbe` so the other pan tests run without a timer.
private struct CancelProbeTicker: View {
    let tick: () -> Void
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onReceive(Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()) { _ in tick() }
    }
}

struct PanScreen: View {
    private static let keys = ["content.body", "didScroll", "button.fired", "clock.tick", "pan.catch", "pan.movingAtEvent", "pan.ev.down", "pan.ev.up", "pan.ev.dragEnd"]
    /// UIKit touch observer probes (D31, DEBUG counters): events the recognizer saw and the two `canPrevent` answers it gave.
    private static let observerKeys = ["pan.ev.drag", "pan.ev.cancel", "phase.tracking", "uikit.began", "uikit.moved", "uikit.ended",
                                       "uikit.cancelled", "uikit.canPrevent", "uikit.canBePrevented"]
    /// `-ZTronShowToggle`: a Toggle button removes / re-adds the scroll view (window changes: uninstall / reinstall).
    private static let showToggle = ProcessInfo.processInfo.arguments.contains("-ZTronShowToggle")
    /// `-ZTronCancelProbe`: 300 ms after the first touch-down the app tries to make UIKit cancel the touch in flight (see
    /// `cancelTouchesInFlight`); the outcome per mechanism lands in `probe=` of the state readout.
    private static let cancelProbe = ProcessInfo.processInfo.arguments.contains("-ZTronCancelProbe")
    /// `-ZTronPanNative 1` (D11 narrowing harness): the same rows in a native `ScrollView` (the native reference rows).
    private static let native = ProcessInfo.processInfo.arguments.firstIndex(of: "-ZTronPanNative").map {
        $0 + 1 < ProcessInfo.processInfo.arguments.count && ProcessInfo.processInfo.arguments[$0 + 1] == "1" } ?? false
    @State private var state = ZTronScrollState()
    @State private var probe = PanProbe()
    @State private var snapshot: [String: Int] = [:]
    @State private var stateInfo = ""
    @State private var shown = true
    @State private var probeScheduled = false
    @State private var probeLog = ""

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Snapshot") { takeSnapshot() }.accessibilityIdentifier("Snapshot")
                if Self.showToggle { Button("Toggle") { shown.toggle() }.accessibilityIdentifier("Toggle") }
            }
            if shown, Self.native {
                ScrollView(.vertical) { PanContent() }
                    .frame(height: 360)
                    .border(Color.gray)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scroller")
            } else if shown {
                ZTronScrollView(.vertical, state: state) { PanContent() }
                    .frame(height: 360)
                    .border(Color.gray)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scroller")
            } else {
                Color.clear.frame(height: 360).accessibilityIdentifier("placeholder")
            }
            ZTronScrollReader(state, of: { (g: ZTronScrollGeometry) -> ZTronScrollPhase in g.phase }) { (p: ZTronScrollPhase) in
                CountedLabel(key: p == .tracking ? "phase.tracking" : "phase.other", text: "phase \(p.rawValue)")
            }
            VStack(spacing: 0) {
                ForEach(Self.keys + Self.observerKeys, id: \.self) { CounterRow(key: $0, value: snapshot[$0] ?? 0) }
            }
            Text(stateInfo).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(stateInfo)
        }
        .padding(8)
        .onAppear {
            state.delegate = probe
            #if canImport(UIKit)
            PressScrollHook.scroll = Self.native ? PressScrollHook.native() : PressScrollHook.ztron(state)
            #else
            PressScrollHook.scroll = PressScrollHook.ztron(state)
            #endif
        }
        .background { if Self.cancelProbe { CancelProbeTicker { armCancelProbe() } } }
    }

    /// Polls the touch-down counter (no view reads it): the first down starts the probe.
    private func armCancelProbe() {
        #if DEBUG
        guard Self.cancelProbe, !probeScheduled, ZTronRenderCounters.value("pan.ev.down") > 0 else { return }
        probeScheduled = true
        cancelTouchesInFlight()
        #endif
    }

    /// UIKit cancels a touch in flight when its window stops being shown or the app is interrupted. Two mechanisms, 500 ms
    /// apart (the second sends the app to Settings; the UI test brings it back); `probeLog` records how many
    /// `touchesCancelled` the observer had seen after each.
    private func cancelTouchesInFlight() {
        #if canImport(UIKit) && DEBUG
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.keyWindow ?? scene?.windows.first else { return }
        let mechanisms: [(String, (Bool) -> Void)] = [
            ("windowHidden", { window.isHidden = !$0 }),
            ("openSettings", { if !$0, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }),
        ]
        for (i, m) in mechanisms.enumerated() {
            let t = 0.3 + 0.5 * Double(i)
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { m.1(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.1) { m.1(true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.2) {
                probeLog += "\(m.0):\(ZTronRenderCounters.value("uikit.cancelled")),"
            }
        }
        #endif
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.setContentOffset(.zero, animated: false)
        probe.reset()
        PressScrollHook.rearm()
        #if canImport(UIKit)
        if Self.native { PressScrollHook.firstScrollView()?.setContentOffset(.zero, animated: false) }
        #endif
        probeScheduled = false
        probeLog = ""
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
        var y = Int(state.contentOffset.y)
        #if canImport(UIKit)
        if Self.native { y = Int(PressScrollHook.firstScrollView()?.contentOffset.y ?? -9999) }
        #endif
        stateInfo = "phase=\(state.phase.rawValue) tracking=\(state.isTracking ? 1 : 0) y=\(y) hookScrolls=\(PressScrollHook.fired) minY=\(Int(probe.minY)) maxY=\(Int(probe.maxY)) probe=\(probeLog) order=\(probe.order.joined(separator: ",")) \(snapshot.keys.filter { $0.hasPrefix("lag=") }.joined(separator: ","))"
    }
}
