import SwiftUI
import ZTronScrollView
#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
#endif

/// BTN-s1: a fast drag that starts on a Button against the same drag from the background (docs/progress/BTN-s1.md). The
/// Q3-s2 spike page without the pager: a two-axis scroller, 900 x 1600 content (a gradient), a Button near the content's
/// top-left. `-ZTronBDNative` swaps in SwiftUI's own `ScrollView` (baseline lane); `-ZTronBDStyle
/// bordered|borderless|plain|default` picks the Button style (default `bordered`); `-ZTronBDLeading <pt>` moves the Button;
/// `-ZTronBDWidth <pt>` widens the content (BTN-s2's sweep: flings that do not reach the trailing edge).
/// "Snapshot" writes the readout `bd.info`: offset, its maximum, Button taps, delegate drag callbacks, the release
/// velocity ZTron reported (`vel`, pt/s), (DEBUG) the pan counters and the time-stamped offset samples `xs`; on the native
/// lane also `bd.native` (BTN-s2, `BDNativeProbe`: UIKit's touches, pan velocities and offsets). "Reset" puts the offset
/// back to zero and clears both probes, so one launch runs many drags.
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
    /// `-ZTronBDWidth <pt>`: the content's width (default 900, the spike page's).
    static var width: CGFloat { value("-ZTronBDWidth").flatMap(Double.init).map { CGFloat($0) } ?? 900 }
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
    /// pt/s (the delegate's pt/ms × 1000): the release velocity after the tracker's rest rule.
    var releaseVelocity: CGFloat?
    func scrollViewWillEndDragging(_ state: ZTronScrollState, withVelocity velocity: CGPoint,
                                   targetContentOffset: inout CGPoint) {
        releaseVelocity = velocity.x * 1000
    }
    func scrollViewDidEndDragging(_ state: ZTronScrollState, willDecelerate decelerate: Bool) {
        order.append("didEndDragging(\(decelerate ? 1 : 0))")
    }
    func scrollViewDidEndDecelerating(_ state: ZTronScrollState) { order.append("didEndDecelerating") }

    func reset() {
        x = 0; y = 0; maxX = 0; maxY = 0; taps = 0
        order = []; samples = []; releaseVelocity = nil
    }

    func summary() -> String {
        func f(_ v: CGFloat) -> String { String(Int(v.rounded())) }
        var s = "x=\(f(x)) y=\(f(y)) maxX=\(f(maxX)) maxY=\(f(maxY)) taps=\(taps) order=\(order.joined(separator: ","))"
        s += " vel=" + (releaseVelocity.map(f) ?? "-")
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

#if canImport(UIKit)
/// BTN-s2 (docs/progress/BTN-s2.md): how `UIScrollView` picks its release velocity, on the native lane only. Finds the
/// `UIScrollView` behind SwiftUI's `ScrollView` (from a view inside its content) and records, in ms since the touch-down:
/// - `T`: every touch the scroll view gets (`b`egan / `m`oved / `e`nded / `c`ancelled `@<t>:<window x>`, `UITouch.timestamp`;
///   `+n` = n coalesced samples), from an observer recognizer that never recognizes;
/// - `P`: every pan callback (`<state>@<t of the newest touch>:<velocity(in:).x>/<translation.x>`, states
///   `b c e x f` = began, changed, ended, cancelled, failed), and at `.ended` `dec=` (`isDecelerating` right after
///   UIKit's own handler), `off=`;
/// - `O`: contentOffset.x by KVO (`<t>:<x>`, uptime at the change): every change until the lift, then the first 12.
@MainActor
final class BDNativeProbe: NSObject, UIGestureRecognizerDelegate {
    static let shared = BDNativeProbe()
    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var t0: TimeInterval?
    private var newestTouch: TimeInterval = 0
    private var lifted = false
    private var afterLift = 0
    private var touches: [String] = [], pans: [String] = [], offsets: [String] = []

    func attach(_ sv: UIScrollView) {
        guard scrollView !== sv else { return }
        scrollView = sv
        sv.panGestureRecognizer.addTarget(self, action: #selector(pan(_:)))
        let observer = BDTouchObserver(target: nil, action: nil)
        observer.probe = self
        observer.delegate = self
        sv.addGestureRecognizer(observer)
        offsetObservation = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            MainActor.assumeIsolated { self?.offsetChanged(sv.contentOffset.x) }
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private func ms(_ t: TimeInterval) -> String { String(format: "%.1f", (t - (t0 ?? t)) * 1000) }

    func touch(_ phase: String, _ set: Set<UITouch>, _ event: UIEvent) {
        guard let touch = set.first else { return }
        if phase == "b", t0 == nil || lifted { clear(); t0 = touch.timestamp }
        newestTouch = touch.timestamp
        if phase == "e" || phase == "c" { lifted = true }
        let coalesced = event.coalescedTouches(for: touch)?.count ?? 1
        if touches.count < 200 {
            touches.append("\(phase)@\(ms(touch.timestamp)):\(String(format: "%.1f", touch.location(in: nil).x))"
                           + (coalesced > 1 ? "+\(coalesced)" : ""))
        }
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard let sv = scrollView else { return }
        let state: String
        switch g.state {
        case .began: state = "b"
        case .changed: state = "c"
        case .ended: state = "e"
        case .cancelled: state = "x"
        case .failed: state = "f"
        default: state = "?"
        }
        var s = "\(state)@\(ms(newestTouch)):\(Int(g.velocity(in: sv).x.rounded()))/\(Int(g.translation(in: sv).x.rounded()))"
        if g.state == .ended || g.state == .cancelled {
            s += " dec=\(sv.isDecelerating ? 1 : 0) off=\(Int(sv.contentOffset.x.rounded())) now=\(ms(ProcessInfo.processInfo.systemUptime))"
        }
        if pans.count < 200 { pans.append(s) }
    }

    private func offsetChanged(_ x: CGFloat) {
        guard t0 != nil else { return }
        if lifted {
            guard afterLift < 12 else { return }
            afterLift += 1
        }
        if offsets.count < 300 {
            offsets.append("\(ms(ProcessInfo.processInfo.systemUptime)):\(String(format: "%.1f", x))")
        }
    }

    func clear() {
        t0 = nil; lifted = false; afterLift = 0
        touches = []; pans = []; offsets = []
    }

    /// Back to the origin (stops a deceleration in flight) and forgets the last drag.
    func resetScroll() {
        scrollView?.setContentOffset(.zero, animated: false)
        clear()
    }

    func summary() -> String {
        let rest = scrollView.map { Int($0.contentOffset.x.rounded()) }.map(String.init) ?? "-"
        return "rest=\(rest) T=\(touches.joined(separator: ",")) P=\(pans.joined(separator: ",")) O=\(offsets.joined(separator: ","))"
    }
}

/// Sees every touch of the scroll view and never recognizes (fails at the lift).
final class BDTouchObserver: UIGestureRecognizer {
    weak var probe: BDNativeProbe?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { probe?.touch("b", touches, event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { probe?.touch("m", touches, event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        probe?.touch("e", touches, event)
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        probe?.touch("c", touches, event)
        state = .failed
    }
}

/// A view inside the native content: its superview chain leads to SwiftUI's `UIScrollView`.
private struct BDScrollViewFinder: UIViewRepresentable {
    final class Finder: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let s = v {
                if let sv = s as? UIScrollView { BDNativeProbe.shared.attach(sv); return }
                v = s.superview
            }
        }
    }
    func makeUIView(context: Context) -> Finder {
        let f = Finder()
        f.isUserInteractionEnabled = false
        return f
    }
    func updateUIView(_ uiView: Finder, context: Context) {}
}
#endif

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
        .frame(width: BDArgs.width, height: 1600)
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
    @State private var nativeInfo = ""

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 24) {
                Button("Snapshot") { snapshot() }.accessibilityIdentifier("Snapshot")
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
            }
            scroller
                .frame(height: 500)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scroller")
            Text(info).font(.caption2).lineLimit(4).accessibilityIdentifier("bd.info").accessibilityValue(info)
            Text(nativeInfo).font(.caption2).lineLimit(1).accessibilityIdentifier("bd.native").accessibilityValue(nativeInfo)
        }
        .padding(8)
        .onAppear { state.delegate = BDProbe.shared }
    }

    private func snapshot() {
        info = BDProbe.shared.summary()
        #if canImport(UIKit)
        if BDArgs.native { nativeInfo = BDNativeProbe.shared.summary() }
        #endif
    }

    private func reset() {
        if BDArgs.native {
            #if canImport(UIKit)
            BDNativeProbe.shared.resetScroll()
            #endif
        } else {
            state.stopScrollingAndZooming()
            state.setContentOffset(.zero, animated: false)
        }
        BDProbe.shared.reset()
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        info = ""
        nativeInfo = ""
    }

    @ViewBuilder private var scroller: some View {
        if BDArgs.native {
            ScrollView([.horizontal, .vertical]) {
                BDContent().background(GeometryReader { g in
                    let f = g.frame(in: .named("bd.native"))
                    let _ = BDProbe.shared.record(CGPoint(x: -f.minX, y: -f.minY))
                    Color.clear
                })
                #if canImport(UIKit)
                .background(BDScrollViewFinder())
                #endif
            }
            .coordinateSpace(name: "bd.native")
        } else {
            ZTronScrollView([.horizontal, .vertical], state: state) { BDContent() }
        }
    }
}
