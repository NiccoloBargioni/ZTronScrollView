import SwiftUI
import ZTronScrollView

/// Content whose body counts itself. It has no inputs, so scrolling, zooming and parent re-renders must never run it.
struct ProofContent: View {
    @State private var on = false

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return VStack(spacing: 8) {
            Button(on ? "Toggle: on" : "Toggle: off") { on.toggle() }
                .accessibilityIdentifier("content.toggle")
                .accessibilityValue(on ? "on" : "off")
            ForEach(0..<60, id: \.self) { i in
                Text("Row \(i)").frame(maxWidth: .infinity).padding(.vertical, 6).background(Color.blue.opacity(0.15))
            }
        }
        .frame(height: 1600, alignment: .top)
    }
}

/// A reader label that counts how often its body runs (the reader's content closure output).
struct CountedLabel: View {
    let key: String
    let text: String
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment(key)
        #endif
        return Text(text).font(.caption2)
    }
}

struct ProofScreen: View {
    private static let keys = ["content.body", "transformHost.body", "transform.effect", "clock.tick", "clock.dupTick", "didScroll",
                               "reader.zoom", "reader.offset"]
    @State private var state = ZTronScrollState()
    @State private var snapshot: [String: Int] = [:]
    @State private var stateInfo = ""
    /// "settled …" once `Reset` zeroed the counters after a quiet period (the UI tests wait for it).
    @State private var settle = ""

    private var path: String {
        ZTronAvailability.forcedFallbacks.isEmpty ? "preferred" : "forcedFallback"
    }

    var body: some View {
        VStack(spacing: 6) {
            controls
            scroller
            readers
            Text(path).font(.caption2).accessibilityIdentifier("path").accessibilityValue(path)
            counters
            // Fixed frames: the texts written by Reset and Snapshot never change the layout (a VStack that grows moves the
            // scroll view, a layout pass that evaluates the content's transform effect, review d16).
            Text(stateInfo).font(.caption2).frame(width: 360, height: 30)
                .accessibilityIdentifier("stateInfo").accessibilityValue(stateInfo)
            Text(settle).font(.caption2).frame(width: 360, height: 14)
                .accessibilityIdentifier("settle").accessibilityValue(settle)
        }
        .padding(8)
    }

    private var controls: some View {
        VStack {
            HStack {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("AnimatedScroll") { state.setContentOffset(CGPoint(x: 0, y: 400), animated: true) }
                    .accessibilityIdentifier("AnimatedScroll")
                Button("WithAnimationScroll") {
                    withAnimation(.linear(duration: 1)) { state.scroll(to: CGPoint(x: 0, y: 400)) }
                }.accessibilityIdentifier("WithAnimationScroll")
            }
            HStack {
                Button("Zoom") { state.setZoomScale(1.5, animated: false) }.accessibilityIdentifier("Zoom")
                Button("Snapshot") { takeSnapshot() }.accessibilityIdentifier("Snapshot")
            }
        }
    }

    private var scroller: some View {
        ZTronScrollView(.vertical, state: state) { ProofContent() }
                .zoomRange(min: .absolute(1), max: .absolute(4))
            .frame(height: 280)
            .border(Color.gray)
    }

    private var readers: some View {
        HStack {
            ZTronScrollReader(state, of: { (g: ZTronScrollGeometry) -> CGFloat in g.zoomScale }) { (z: CGFloat) in
                CountedLabel(key: "reader.zoom", text: "zoom \(z)")
            }
            ZTronScrollReader(state, of: { (g: ZTronScrollGeometry) -> CGPoint in g.contentOffset }) { (o: CGPoint) in
                CountedLabel(key: "reader.offset", text: "y \(Int(o.y))")
            }
        }
    }

    private var counters: some View {
        VStack(spacing: 0) {
            ForEach(Self.keys, id: \.self) { key in
                CounterRow(key: key, value: snapshot[key] ?? 0)
            }
        }
    }
}

struct CounterRow: View {
    let key: String
    let value: Int
    var body: some View {
        Text("\(key): \(value)").font(.caption2)
            .accessibilityIdentifier("counter.\(key)")
            .accessibilityValue("\(value)")
    }
}

extension ProofScreen {
    private func reset() {
        state.stopScrollingAndZooming()
        state.setContentOffset(.zero, animated: false)
        state.setZoomScale(1, animated: false)
        settle = ""
        // Readers and the transform update on the next render; zero the counters once the screen is quiet: no render
        // counter moved for 0.5 s (at most 3 s, so continuous per-frame work still shows in the next window). A fixed
        // 0.3 s delay counted layout passes that land later under host load (a late launch layout evaluates the
        // transform effect twice: review d16, 5 of 8 runs at load 300-700).
        settleCounters(start: Date(), quietSince: Date(), last: -1)
    }

    private func settleCounters(start: Date, quietSince: Date, last: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            #if DEBUG
            let keys = ["transform.effect", "transformHost.body", "clock.tick", "content.body", "reader.zoom", "reader.offset"]
            let n = keys.reduce(0) { $0 + ZTronRenderCounters.value($1) }
            let now = Date()
            let quiet = n == last ? quietSince : now
            if now.timeIntervalSince(quiet) >= 0.5 || now.timeIntervalSince(start) >= 3 {
                let absorbed = ZTronRenderCounters.value("transform.effect")
                ZTronRenderCounters.reset()
                settle = String(format: "settled after %.1f s, absorbed effect %d", now.timeIntervalSince(start), absorbed)
            } else {
                settleCounters(start: start, quietSince: quiet, last: n)
            }
            #endif
        }
    }

    /// Copies the counters into state. Shown only after the motion, so the display never perturbs it.
    private func takeSnapshot() {
        #if DEBUG
        snapshot = ZTronRenderCounters.snapshot
        stateInfo = "phase=\(state.phase.rawValue) anim=\(state.isScrollAnimating) y=\(Int(state.contentOffset.y)) z=\(state.zoomScale)"
        #endif
    }
}
