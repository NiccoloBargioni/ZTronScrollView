import SwiftUI
import ZTronScrollView

/// BTN-s1: a fast drag that starts on a Button against the same drag from the background (docs/progress/BTN-s1.md). The
/// Q3-s2 spike page without the pager: a two-axis scroller, 900 x 1600 content (a gradient), a Button near the content's
/// top-left. `-ZTronBDNative` swaps in SwiftUI's own `ScrollView` (baseline lane); `-ZTronBDStyle
/// bordered|borderless|plain|default` picks the Button style (default `bordered`); `-ZTronBDLeading <pt>` moves the Button.
/// "Snapshot" writes the readout `bd.info`: offset, its maximum, Button taps, delegate drag callbacks, (DEBUG) the pan
/// counters and the time-stamped offset samples `xs` (the native lane's only timeline).
enum BDArgs {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    private static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var native: Bool { args.contains("-ZTronBDNative") }
    static var style: String { value("-ZTronBDStyle") ?? "bordered" }
    /// `-ZTronBDLeading <pt>`: the Button's distance from the content's leading edge (default 40, the spike page's).
    static var leading: CGFloat { value("-ZTronBDLeading").flatMap(Double.init).map { CGFloat($0) } ?? 40 }
}

@MainActor
final class BDProbe: ZTronScrollViewDelegate {
    static let shared = BDProbe()
    var x: CGFloat = 0, y: CGFloat = 0, maxX: CGFloat = 0, maxY: CGFloat = 0
    var taps = 0
    var order: [String] = []

    /// Time-stamped x samples (`<s>:<x>`, the first 120 changes): when the content stopped following and started to fling.
    var samples: [String] = []

    func record(_ p: CGPoint) {
        if p.x != x, samples.count < 120 {
            samples.append(String(format: "%.3f:%d", Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100),
                                  Int(p.x.rounded())))
        }
        x = p.x; y = p.y
        maxX = max(maxX, x); maxY = max(maxY, y)
    }
    func scrollViewDidScroll(_ state: ZTronScrollState) { record(state.contentOffset) }
    func scrollViewWillBeginDragging(_ state: ZTronScrollState) { order.append("willBeginDragging") }
    func scrollViewDidEndDragging(_ state: ZTronScrollState, willDecelerate decelerate: Bool) {
        order.append("didEndDragging(\(decelerate ? 1 : 0))")
    }
    func scrollViewDidEndDecelerating(_ state: ZTronScrollState) { order.append("didEndDecelerating") }

    func summary() -> String {
        func f(_ v: CGFloat) -> String { String(Int(v.rounded())) }
        var s = "x=\(f(x)) y=\(f(y)) maxX=\(f(maxX)) maxY=\(f(maxY)) taps=\(taps) order=\(order.joined(separator: ","))"
        #if DEBUG
        let c = ZTronRenderCounters.snapshot
        for k in ["pan.ev.down", "pan.ev.drag", "pan.ev.dragEnd", "pan.ev.cancel", "pan.ev.up", "pan.catch"] {
            s += " c.\(k)=\(c[k] ?? 0)"
        }
        #endif
        s += " xs=" + samples.joined(separator: ",")
        return s
    }
}

private struct BDContent: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [.blue, .green, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.4)
            VStack(alignment: .leading, spacing: 12) {
                Text("Button drag").font(.headline)
                BDStyled(button: Button("Tap") { BDProbe.shared.taps += 1 })
                    .accessibilityIdentifier("bd.button")
            }
            .padding(.top, 60)
            .padding(.leading, BDArgs.leading)
        }
        .frame(width: 900, height: 1600)
    }
}

private struct BDStyled<B: View>: View {
    let button: B
    var body: some View {
        switch BDArgs.style {
        case "borderless": button.buttonStyle(.borderless)
        case "plain": button.buttonStyle(.plain)
        case "default": button
        default: button.buttonStyle(.bordered)
        }
    }
}

struct ButtonDragScreen: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""

    var body: some View {
        VStack(spacing: 6) {
            Button("Snapshot") { info = BDProbe.shared.summary() }.accessibilityIdentifier("Snapshot")
            scroller
                .frame(height: 500)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scroller")
            Text(info).font(.caption2).lineLimit(4).accessibilityIdentifier("bd.info").accessibilityValue(info)
        }
        .padding(8)
        .onAppear { state.delegate = BDProbe.shared }
    }

    @ViewBuilder private var scroller: some View {
        if BDArgs.native {
            ScrollView([.horizontal, .vertical]) {
                BDContent().background(GeometryReader { g in
                    let f = g.frame(in: .named("bd.native"))
                    let _ = BDProbe.shared.record(CGPoint(x: -f.minX, y: -f.minY))
                    Color.clear
                })
            }
            .coordinateSpace(name: "bd.native")
        } else {
            ZTronScrollView([.horizontal, .vertical], state: state) { BDContent() }
        }
    }
}
