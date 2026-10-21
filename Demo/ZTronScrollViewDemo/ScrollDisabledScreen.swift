import SwiftUI
import ZTronScrollView

/// DBG-s3: SwiftUI's `scrollDisabled(_:)` against a `ZTronScrollView` (docs/progress/DBG-s3.md). One vertical scroller whose
/// disabling is chosen by `-ZTronSDMode none|native|ztron|nativeParent|nativeToggle|nativeFalse` (default `none`):
/// `native` = `.scrollDisabled(true)` on the scroller, `ztron` = `.ztronScrollDisabled(true)`, `nativeParent` = on a
/// wrapping stack, `nativeToggle` = `.scrollDisabled(off)` driven by the "Toggle" button (starts enabled), `nativeFalse` =
/// `.scrollDisabled(false)`. `-ZTronSDNativeScroll` swaps in SwiftUI's own `ScrollView` (baseline lane), `-ZTronSDSheet`
/// puts the scroller in a `.sheet`. The readout (`sd.info`) comes from the app: content offset, what a probe inside the
/// content and one beside the scroller read from `\.isScrollEnabled`, the delegate's drag callbacks.
enum SDArgs {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    private static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var mode: String { value("-ZTronSDMode") ?? "none" }
    static var native: Bool { args.contains("-ZTronSDNativeScroll") }
    static var sheet: Bool { args.contains("-ZTronSDSheet") }
    /// `-ZTronSDMedium`: the sheet gets `[.medium, .large]` detents and starts at medium (the SHEET-s1 shape, 16+).
    static var medium: Bool { args.contains("-ZTronSDMedium") }
    /// `-ZTronSDGrow`: the readout may grow from nothing to three lines, which shrinks the scroller's viewport (the SHEET-s1
    /// readout did, and read "offset 9" after a drag of a disabled view). Without it the readout has a fixed height.
    static var grow: Bool { args.contains("-ZTronSDGrow") }
    /// `-ZTronSDAnchorTop`: `defaultScrollAnchor(.top, for: .sizeChanges)` on the scroller, S7's one documented override: a viewport
    /// change (a sheet that resizes) no longer moves the offset, so what is left is what the finger did (DBG-s7).
    static var anchorTop: Bool { args.contains("-ZTronSDAnchorTop") }
}

@MainActor
final class SDProbe: ZTronScrollViewDelegate {
    static let shared = SDProbe()
    var offMin: CGFloat = 0, offMax: CGFloat = 0, off: CGFloat = 0
    var didScroll = 0, dragBegan = 0, dragEnded = 0
    /// What `@Environment(\.isScrollEnabled)` read in the content of the scroller / beside it (nil: never evaluated).
    var envInside: Bool?
    var envBeside: Bool?
    var nativeOffset: CGFloat = 0
    /// The pane's size in order of arrival and the first offsets the delegate saw, since launch (capped): a sheet that lays its
    /// content out at one size and settles at another shows up as two sizes and an offset that moved without a touch (DBG-s7).
    private(set) var sizeTrail: [String] = []
    private(set) var offTrail: [Int] = []

    func noteSize(_ size: CGSize) {
        let s = "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        if sizeTrail.last != s, sizeTrail.count < 12 { sizeTrail.append(s) }
    }

    func scrollViewDidScroll(_ state: ZTronScrollState) {
        didScroll += 1
        off = state.contentOffset.y
        offMin = min(offMin, off); offMax = max(offMax, off)
        let o = Int(off.rounded())
        if offTrail.last != o, offTrail.count < 12 { offTrail.append(o) }
    }
    func scrollViewWillBeginDragging(_ state: ZTronScrollState) { dragBegan += 1 }
    func scrollViewDidEndDragging(_ state: ZTronScrollState, willDecelerate decelerate: Bool) { dragEnded += 1 }

    func reset() { offMin = off; offMax = off; didScroll = 0; dragBegan = 0; dragEnded = 0 }

    /// `viewport`: the scroller's committed viewport height (0 for the native variant, which has no state).
    func summary(live: CGFloat, viewport: CGFloat = 0) -> String {
        func f(_ v: CGFloat) -> String { String(Int(v.rounded())) }
        func b(_ v: Bool?) -> String { v.map { $0 ? "1" : "0" } ?? "-" }
        var s = "off=\(f(live)) vp=\(f(viewport)) offMin=\(f(offMin)) offMax=\(f(offMax)) didScroll=\(didScroll) dragBegan=\(dragBegan) dragEnded=\(dragEnded) "
        s += "envInside=\(b(envInside)) envBeside=\(b(envBeside)) nativeOff=\(f(nativeOffset)) "
        s += "sz=\(sizeTrail.joined(separator: ">")) ot=\(offTrail.map(String.init).joined(separator: ","))"
        #if DEBUG
        let c = ZTronRenderCounters.snapshot
        for k in ["pan.ev.down", "pan.ev.drag", "pan.ev.cancel", "pan.ev.up", "pan.ev.dragEnd"] { s += " c.\(k)=\(c[k] ?? 0)" }
        #endif
        return s
    }
}

/// Reads `\.isScrollEnabled` where it is placed and stores it (an `@Environment` of a view body, 16+).
@available(iOS 16, *)
private struct EnvProbe: View {
    let inside: Bool
    @Environment(\.isScrollEnabled) private var enabled
    var body: some View {
        if inside { SDProbe.shared.envInside = enabled } else { SDProbe.shared.envBeside = enabled }
        return Color.clear.frame(width: 0, height: 0)
    }
}

private struct SDRows: View {
    var body: some View {
        VStack(spacing: 0) {
            if #available(iOS 16, *) { EnvProbe(inside: true) }
            ForEach(0..<60, id: \.self) { i in
                Text("Row \(i)").frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                    .background(i % 2 == 0 ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
            }
        }
    }
}

private struct SDScroller: View {
    let state: ZTronScrollState
    let off: Bool
    var body: some View {
        if SDArgs.native {
            ScrollView {
                SDRows().background(GeometryReader { g in
                    let _ = SDProbe.shared.nativeOffset = -g.frame(in: .named("sd.native")).minY
                    Color.clear
                })
            }
            .coordinateSpace(name: "sd.native")
            .modifier(SDDisable(off: off))
        } else if SDArgs.anchorTop {
            ZTronScrollView(.vertical, state: state) { SDRows() }
                .defaultScrollAnchor(.top, for: .sizeChanges)
                .modifier(SDDisable(off: off))
        } else {
            ZTronScrollView(.vertical, state: state) { SDRows() }
                .modifier(SDDisable(off: off))
        }
    }
}

private struct SDDisable: ViewModifier {
    let off: Bool
    @ViewBuilder func body(content: Content) -> some View {
        switch SDArgs.mode {
        case "native":
            if #available(iOS 16, *) { content.scrollDisabled(true) } else { content }
        case "nativeFalse":
            if #available(iOS 16, *) { content.scrollDisabled(false) } else { content }
        case "nativeToggle":
            if #available(iOS 16, *) { content.scrollDisabled(off) } else { content }
        case "nativeParent":
            if #available(iOS 16, *) { VStack(spacing: 0) { content }.scrollDisabled(true) } else { content }
        case "ztron":
            content.ztronScrollDisabled(true)
        default:
            content
        }
    }
}

private struct SDPane: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var off = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                Button("Snapshot") {
                    info = SDProbe.shared.summary(live: state.contentOffset.y, viewport: state.geometry.containerSize.height)
                }.accessibilityIdentifier("sd.snapshot")
                Button("Reset") { SDProbe.shared.reset() }.accessibilityIdentifier("sd.reset")
                Button("Toggle") { off.toggle() }.accessibilityIdentifier("sd.toggle")
            }
            Text(info).font(.system(size: 9)).lineLimit(SDArgs.grow ? 3 : 4)
                .frame(maxWidth: .infinity, minHeight: SDArgs.grow ? 0 : 48, alignment: .topLeading)
                .accessibilityIdentifier("sd.info").accessibilityValue(info)
            if #available(iOS 16, *) { EnvProbe(inside: false) }
            SDScroller(state: state, off: off)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sd.scroller")
        }
        .padding(.top, 8)
        .background(GeometryReader { g in
            let _ = SDProbe.shared.noteSize(g.size)
            Color.clear
        })
        .onAppear { state.delegate = SDProbe.shared }
    }
}

struct ScrollDisabledScreen: View {
    @State private var presented = false

    var body: some View {
        if SDArgs.sheet {
            Button("Present") { presented = true }
                .accessibilityIdentifier("sd.present")
                .sheet(isPresented: $presented) { SDPane().modifier(SDDetents()) }
        } else {
            SDPane()
        }
    }
}

private struct SDDetents: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16, *), SDArgs.medium {
            content.presentationDetents([.medium, .large])
        } else {
            content
        }
    }
}
