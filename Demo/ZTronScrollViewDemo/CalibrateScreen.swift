import SwiftUI
import ZTronScrollView

// Physics calibration harness (docs/design/PHYSICS-calibration.md). `-ZTronScreen calibrate` shows our
// ZTronScrollView; `-ZTronCalibrateNative` swaps in a native SwiftUI ScrollView (iOS 18+). `-ZTronCalibrateShort` uses
// content that fits the viewport. Both log (uptime, contentOffset.y, phase) at every offset change plus every finger
// event, and write one JSON per gesture to Documents/cal/<variant>-<gesture>.json when the UI test taps "cal.save".

enum CalConfig {
    static let args = ProcessInfo.processInfo.arguments
    static let native = args.contains("-ZTronCalibrateNative")
    static let short = args.contains("-ZTronCalibrateShort")
    static let rowHeight: CGFloat = 60
    static let viewportHeight: CGFloat = 600
    /// ~10 viewports tall, or half a viewport ("fits").
    static let rows = short ? 5 : 100
    static var contentHeight: CGFloat { CGFloat(rows) * rowHeight }
    static var maxY: CGFloat { max(0, contentHeight - viewportHeight) }
    static var variant: String { (native ? "native" : "ztron") + (short ? "-short" : "") }
    static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    /// Start offset per gesture.
    static func start(for gesture: String) -> CGFloat {
        switch gesture {
        case "slow": return 2000
        case "medium": return 1000
        case "edge": return max(0, maxY - 400)
        default: return 0
        }
    }
}

/// Reference type so logging never invalidates a view body.
@MainActor
final class CalRecorder: ZTronScrollViewDelegate {
    var gesture = "none"
    private var samples: [[Double]] = []      // [t, y, phase]
    private var fingers: [[Double]] = []      // [t, y, kind] kind 0 = down/move, 1 = up
    private var lastY: Double = .nan
    var phase: Int = 0
    weak var state: ZTronScrollState?

    func clear() { samples = []; fingers = []; lastY = .nan }

    func record(y: CGFloat) {
        let v = Double(y)
        if v == lastY { return }
        lastY = v
        samples.append([CalConfig.now(), v, Double(phase)])
    }

    func recordPhase(_ p: Int, y: CGFloat) {
        phase = p
        samples.append([CalConfig.now(), Double(y), Double(p)])
        lastY = Double(y)
    }

    func finger(_ y: CGFloat, up: Bool) { fingers.append([CalConfig.now(), Double(y), up ? 1 : 0]) }

    // Ours: didScroll is coalesced to one call per clock tick (or per drag write flush).
    func scrollViewDidScroll(_ state: ZTronScrollState) {
        phase = state.phase.rawValue
        record(y: state.contentOffset.y)
    }

    func save() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let dict: [String: Any] = [
            "variant": CalConfig.variant, "gesture": gesture,
            "os": "\(os.majorVersion).\(os.minorVersion)",
            "viewport": Double(CalConfig.viewportHeight), "content": Double(CalConfig.contentHeight),
            "maxY": Double(CalConfig.maxY), "start": Double(CalConfig.start(for: gesture)),
            "samples": samples, "fingers": fingers,
        ]
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("cal")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(CalConfig.variant)-\(gesture).json")
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) {
            try? data.write(to: url)
        }
        return "\(url.lastPathComponent) n=\(samples.count) f=\(fingers.count)"
    }
}

struct CalRows: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<CalConfig.rows, id: \.self) { i in
                Text("Row \(i)")
                    .frame(maxWidth: .infinity, minHeight: CalConfig.rowHeight, maxHeight: CalConfig.rowHeight)
                    .background(i % 2 == 0 ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
            }
        }
    }
}

struct CalibrateScreen: View {
    @State private var recorder = CalRecorder()
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var prepToken = 0

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(["slow", "medium", "fast", "edge", "top", "catch", "bottom"], id: \.self) { g in
                    Button(g) { prep(g) }.accessibilityIdentifier("cal.prep.\(g)")
                }
                Button("save") { info = recorder.save() }.accessibilityIdentifier("cal.save")
            }
            .font(.caption)
            Text(info).font(.caption2).accessibilityIdentifier("cal.info").accessibilityValue(info)
            scroller
                .frame(height: CalConfig.viewportHeight)
                .border(Color.gray)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { v in recorder.finger(v.location.y, up: false) }
                        .onEnded { v in recorder.finger(v.location.y, up: true) }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("cal.scroller")
            Spacer(minLength: 0)
        }
        .onAppear {
            recorder.state = state
            state.delegate = recorder
        }
    }

    @ViewBuilder private var scroller: some View {
        if CalConfig.native {
            if #available(iOS 18, *) {
                NativeCalScroller(recorder: recorder, prepToken: prepToken)
            } else {
                Text("native calibration needs iOS 18")
            }
        } else {
            ZTronScrollView(.vertical, state: state) { CalRows() }
        }
    }

    private func prep(_ g: String) {
        recorder.gesture = g
        let y = CalConfig.start(for: g)
        if CalConfig.native {
            NativeCalCommand.shared.target = y
            prepToken += 1
        } else {
            state.stopScrollingAndZooming()
            state.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            recorder.clear()
            info = "ready \(g) y=\(Int(y))"
        }
    }
}

@MainActor
final class NativeCalCommand { static let shared = NativeCalCommand(); var target: CGFloat = 0 }

@available(iOS 18, *)
struct NativeCalScroller: View {
    let recorder: CalRecorder
    let prepToken: Int
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView(.vertical) { CalRows() }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
                recorder.record(y: y)
            }
            .onScrollPhaseChange { _, new, ctx in
                let p: Int
                switch new {
                case .idle: p = 0
                case .tracking: p = 1
                case .interacting: p = 2
                case .decelerating: p = 3
                case .animating: p = 4
                @unknown default: p = 9
                }
                recorder.recordPhase(p, y: ctx.geometry.contentOffset.y + ctx.geometry.contentInsets.top)
            }
            .onChange(of: prepToken) { _, _ in
                position.scrollTo(y: NativeCalCommand.shared.target)
            }
    }
}
