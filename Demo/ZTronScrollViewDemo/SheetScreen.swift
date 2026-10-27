import SwiftUI
import ZTronScrollView
#if canImport(UIKit)
import UIKit
#endif

/// SHEET-s1 (docs/design/SHEET-spike.md): a vertical scroll view inside a SwiftUI bottom sheet, ours or SwiftUI's own
/// (`-ZTronSheetNative`) for the A/B. Launch args: `-ZTronSheetDetents medium,large|large` (default `medium,large`),
/// `-ZTronSheetStart medium|large` (the initial detent), `-ZTronSheetInteraction scrolls|resizes|default` (iOS 16.4),
/// `-ZTronSheetNoDismiss` (`interactiveDismissDisabled`). Every reading comes from the app: the sheet's top and height are
/// sampled on the display (window coordinates), the content offset from the scroll view, so a test sees a sheet that
/// moved during a drag and came back, which an XCUIElement frame read after the gesture would not.
enum SheetArgs {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    private static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var native: Bool { args.contains("-ZTronSheetNative") }
    static var detents: [String] { (value("-ZTronSheetDetents") ?? "medium,large").split(separator: ",").map(String.init) }
    static var start: String { value("-ZTronSheetStart") ?? detents.first ?? "medium" }
    static var interaction: String { value("-ZTronSheetInteraction") ?? "default" }
    static var noDismiss: Bool { args.contains("-ZTronSheetNoDismiss") }
    /// `-ZTronSheetYield none|scrollDisabled|ztronScrollDisabled|scrollDisabledAlways|ztronScrollDisabledAlways|hitTest|pullRelease|api`
    /// (comma-separated to combine, e.g. `api,pullRelease`): what the demo does so the sheet can have the drag. `scrollDisabled` /
    /// `hitTest` switch our view off while the sheet sits at a detent that is not its largest; `pullRelease` turns an
    /// overscroll release at the top (> 60 pt) into a detent change (large -> medium) or a dismissal, from the delegate;
    /// `api` is the library's `ztronScrollYieldsToSheet(detent != .large)` (SHEET-s2).
    static var yieldModes: [String] { (value("-ZTronSheetYield") ?? "none").split(separator: ",").map(String.init) }
    /// The experiment among `yieldModes` (everything but `api`).
    static var yield: String { yieldModes.first { $0 != "api" } ?? "none" }
    static var yieldsApi: Bool { yieldModes.contains("api") }
    /// `-ZTronSheetPlain simultaneous|simultaneous0|gesture|highPriority|maskedSubviews|maskedAtMedium|spatial|magnify|doubleTap|allMaskedAtMedium|magnifyLib|spatialTap2|none` (or `uikitpan`, the UIKITPAN-s1 probe pager): no scroll view at all, a plain pane with a SwiftUI
    /// DragGesture of that kind (or none) in its place, to tell the library's behaviour from SwiftUI's own.
    static var plain: String? { value("-ZTronSheetPlain") }
    /// `-ZTronSheetIntrospect`: passive target/action hooks on every gesture recognizer from the sheet content up to the window.
    static var introspect: Bool { args.contains("-ZTronSheetIntrospect") }
}

/// Everything the sheet readout reports; a plain class (no view observes it), written by the display-link sampler, the
/// scroll view's delegate and the native offset preference.
@MainActor
final class SheetProbe: ZTronScrollViewDelegate {
    static let shared = SheetProbe()

    var detent = SheetArgs.start
    var dismissCount = 0
    var sheetTop: CGFloat = 0
    var sheetHeight: CGFloat = 0
    var sheetTopMin: CGFloat = .greatestFiniteMagnitude
    var sheetTopMax: CGFloat = -.greatestFiniteMagnitude
    var offset: CGFloat = 0
    var offMin: CGFloat = .greatestFiniteMagnitude
    var offMax: CGFloat = -.greatestFiniteMagnitude
    /// UIKITPAN-s1 x channel (`-ZTronSheetPlain uikitpan`): the probe pager's x, the zoomer page's x, and display frames in
    /// which the sheet top and one of them both moved (> 0.5 pt).
    var offX: CGFloat = 0
    var offXMin: CGFloat = .greatestFiniteMagnitude
    var offXMax: CGFloat = -.greatestFiniteMagnitude
    var zxMin: CGFloat = .greatestFiniteMagnitude
    var zxMax: CGFloat = -.greatestFiniteMagnitude
    var bothX = 0
    private var lastX: CGFloat?
    private var lastZX: CGFloat?
    /// Display-link samples in which only the sheet moved, only the content offset moved, and both moved (> 0.5 pt).
    var sheetOnly = 0, offsetOnly = 0, both = 0
    var tracking = 0
    var dragBegan = 0, dragEnded = 0
    var nativeScrollTo: ((Int) -> Void)?
    var nativeOffset: CGFloat = 0
    var nativeCalls = 0
    var plainChanges = 0
    /// `-ZTronSheetYield pullRelease`: set by the presenting screen.
    var onPullRelease: (() -> Void)?
    var pullReleases = 0
    private var lastTop: CGFloat?
    private var lastOffset: CGFloat?

    func scrollViewDidScroll(_ state: ZTronScrollState) {}
    func scrollViewWillBeginDragging(_ state: ZTronScrollState) { dragBegan += 1 }
    func scrollViewDidEndDragging(_ state: ZTronScrollState, willDecelerate decelerate: Bool) {
        dragEnded += 1
        if SheetArgs.yield == "pullRelease", state.contentOffset.y < -60 {
            pullReleases += 1
            onPullRelease?()
        }
    }
    func noteNative(_ y: CGFloat) { nativeOffset = y; nativeCalls += 1 }

    func reset() {
        sheetTopMin = sheetTop; sheetTopMax = sheetTop
        offMin = offset; offMax = offset
        offXMin = offX; offXMax = offX; zxMin = lastZX ?? 0; zxMax = lastZX ?? 0; bothX = 0
        ProbeHub.shared.resetReadings()
        sheetOnly = 0; offsetOnly = 0; both = 0; tracking = 0; dragBegan = 0; dragEnded = 0; pullReleases = 0; plainChanges = 0
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
        #if canImport(UIKit)
        RecognizerLog.shared.reset()
        #endif
    }

    /// One display frame: the sheet's top / height in window coordinates and the content offset.
    func sample(top: CGFloat, height: CGFloat, offset newOffset: CGFloat, isTracking: Bool) {
        sheetTop = top; sheetHeight = height; offset = newOffset
        sheetTopMin = min(sheetTopMin, top); sheetTopMax = max(sheetTopMax, top)
        offMin = min(offMin, newOffset); offMax = max(offMax, newOffset)
        if isTracking { tracking += 1 }
        let x = ProbeHub.shared.models["pager"]?.off.x, zx = ProbeHub.shared.models["zoomer"]?.off.x
        if let x { offX = x; offXMin = min(offXMin, x); offXMax = max(offXMax, x) }
        if let zx { zxMin = min(zxMin, zx); zxMax = max(zxMax, zx) }
        if let lt = lastTop, let lo = lastOffset {
            let sheetMoved = abs(top - lt) > 0.5, offsetMoved = abs(newOffset - lo) > 0.5
            if sheetMoved && offsetMoved { both += 1 } else if sheetMoved { sheetOnly += 1 } else if offsetMoved { offsetOnly += 1 }
            let xMoved = (x.flatMap { a in lastX.map { abs(a - $0) > 0.5 } } ?? false) || (zx.flatMap { a in lastZX.map { abs(a - $0) > 0.5 } } ?? false)
            if sheetMoved && xMoved { bothX += 1 }
        }
        lastTop = top; lastOffset = newOffset; lastX = x; lastZX = zx
    }

    var summary: String {
        func f(_ v: CGFloat) -> String { v.isFinite && abs(v) < 1e6 ? String(Int(v.rounded())) : "-" }
        var s = "det=\(detent) top=\(f(sheetTop)) topMin=\(f(sheetTopMin)) topMax=\(f(sheetTopMax)) h=\(f(sheetHeight)) "
        s += "off=\(f(offset)) offMin=\(f(offMin)) offMax=\(f(offMax)) shOnly=\(sheetOnly) offOnly=\(offsetOnly) both=\(both) "
        if ProbeHub.shared.models["pager"] != nil {
            s += "offX=\(f(offX)) offXMin=\(f(offXMin)) offXMax=\(f(offXMax)) zxMin=\(f(zxMin)) zxMax=\(f(zxMax)) bothX=\(bothX) "
            s += "page=\(ProbeHub.shared.models["pager"]?.page ?? -1) "
        }
        s += "trk=\(tracking) dragBegan=\(dragBegan) dragEnded=\(dragEnded) dismissed=\(dismissCount) pull=\(pullReleases) nc=\(nativeCalls) pc=\(plainChanges)"
        #if DEBUG
        let c = ZTronRenderCounters.snapshot
        for k in ["pan.ev.down", "pan.ev.drag", "pan.ev.cancel", "pan.ev.up", "pan.ev.dragEnd", "uikit.began", "uikit.cancelled",
                  "content.body", "button.fired"] {
            s += " c.\(k)=\(c[k] ?? 0)"
        }
        for k in c.keys.sorted() where k.hasPrefix("uikitpan.") || k.hasPrefix("probe.") { s += " c.\(k)=\(c[k] ?? 0)" }
        #endif
        return s
    }
}

#if canImport(UIKit)
/// `-ZTronSheetIntrospect`: which recognizers fire while a drag runs. Only observes: each recognizer on a view between the
/// sheet content and the window gets one extra target/action (called on began / changed / ended / cancelled, never on failed).
@MainActor
final class RecognizerLog: NSObject {
    static let shared = RecognizerLog()
    private struct Counts { var began = 0, changed = 0, ended = 0, cancelled = 0 }
    private var counts: [String: Counts] = [:]
    private var firstBegan: [String] = []
    private var hooked = Set<ObjectIdentifier>()
    private var t0 = Date()

    func reset() { counts = [:]; firstBegan = []; t0 = Date() }

    /// Hooks every recognizer in the window's whole view tree (the sheet's own pan sits on a container, a scroll view's pan
    /// on a descendant of the hosting view); `hooked` makes it idempotent.
    func scan(from view: UIView) {
        var budget = 4000
        func walk(_ v: UIView) {
            guard budget > 0 else { return }
            budget -= 1
            for r in v.gestureRecognizers ?? [] where hooked.insert(ObjectIdentifier(r)).inserted {
                r.addTarget(self, action: #selector(fired(_:)))
            }
            v.subviews.forEach(walk)
        }
        walk(view.window ?? view)
    }

    private func key(_ r: UIGestureRecognizer) -> String {
        let owner = r.view.map { String(describing: type(of: $0)) } ?? "nil"
        let del = r.delegate.map { "(\(String(describing: type(of: $0))))" } ?? ""
        return "\(String(describing: type(of: r)))@\(owner)\(del)".replacingOccurrences(of: " ", with: "")
    }

    @objc private func fired(_ r: UIGestureRecognizer) {
        let k = key(r)
        var c = counts[k] ?? Counts()
        switch r.state {
        case .began:
            c.began += 1
            firstBegan.append("\(k)@\(Int(Date().timeIntervalSince(t0) * 1000))ms")
        case .changed: c.changed += 1
        case .ended: c.ended += 1
        case .cancelled: c.cancelled += 1
        default: break
        }
        counts[k] = c
    }

    var summary: String {
        let rows = counts.sorted { $0.key < $1.key }.map { "\($0.key):b\($0.value.began)/c\($0.value.changed)/e\($0.value.ended)/x\($0.value.cancelled)" }
        return "rec[\(rows.joined(separator: " "))] firstBegan[\(firstBegan.prefix(8).joined(separator: " "))]"
    }
}

/// Zero-size background view that samples, once per display frame, where the sheet's content is on screen.
private struct SheetSampler: UIViewRepresentable {
    let state: ZTronScrollState?
    func makeUIView(context: Context) -> SamplerView { SamplerView() }
    func updateUIView(_ view: SamplerView, context: Context) { view.state = state }

    final class SamplerView: UIView {
        var state: ZTronScrollState?
        private var link: CADisplayLink?
        private var frames = 0
        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate(); link = nil
            guard window != nil else { return }
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        }
        @objc private func tick() {
            guard window != nil else { return }
            frames += 1
            if SheetArgs.introspect, frames % 20 == 1 { RecognizerLog.shared.scan(from: self) }
            let r = convert(bounds, to: nil)
            let probe = SheetProbe.shared
            let off = state.map { $0.contentOffset.y } ?? probe.nativeOffset
            probe.sample(top: r.minY, height: r.height, offset: off, isTracking: state?.isTracking ?? false)
        }
    }
}
#endif

/// The 80 rows (44 pt) both variants show; no inputs, so nothing re-evaluates it (`content.body` stays 0). Row 3 carries a
/// Button (`button.fired`): controls in the content must keep working while the view yields to the sheet.
private struct SheetRows: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return VStack(spacing: 0) {
            ForEach(0..<80, id: \.self) { i in
                Group {
                    if i == 3 {
                        Button("Tap row 3") {
                            #if DEBUG
                            ZTronRenderCounters.increment("button.fired")
                            #endif
                        }.accessibilityIdentifier("sheet.contentButton")
                    } else {
                        Text("Row \(i)")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .background(i % 2 == 0 ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
                .id("row.\(i)")
            }
        }
    }
}

private struct SheetReadout: View {
    let state: ZTronScrollState
    @State private var info = ""
    @State private var rec = ""

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 14) {
                Button("Snapshot") {
                    info = SheetProbe.shared.summary
                    #if canImport(UIKit)
                    if SheetArgs.introspect { rec = RecognizerLog.shared.summary }
                    #endif
                }.accessibilityIdentifier("sheet.snapshot")
                Button("Reset") { SheetProbe.shared.reset() }.accessibilityIdentifier("sheet.reset")
                Button("Near") { scrollTo(row: 5) }.accessibilityIdentifier("sheet.near")
                Button("Mid") { scrollTo(row: 15) }.accessibilityIdentifier("sheet.mid")
                Button("Top") { scrollTo(row: 0) }.accessibilityIdentifier("sheet.top")
                if SheetArgs.plain == "uikitpan" {
                    ForEach(["P0", "ZMid", "ZEdge"], id: \.self) { k in
                        Button(k) { ProbeSheetPager.position(k) }.accessibilityIdentifier("probe.\(k)")
                    }
                }
            }
            .font(.footnote)
            Text(info).font(.system(size: 9)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("sheet.info").accessibilityValue(info)
            if SheetArgs.introspect {
                Text(rec).font(.system(size: 7)).lineLimit(2).accessibilityIdentifier("sheet.rec").accessibilityValue(rec)
            }
        }
        .padding(.horizontal, 8)
    }

    private func scrollTo(row: Int) {
        if SheetArgs.native {
            SheetProbe.shared.nativeScrollTo?(row)
        } else {
            state.setContentOffset(CGPoint(x: 0, y: CGFloat(row) * 44), animated: false)
        }
    }
}

/// `-ZTronSheetPlain`: a pane that fills the scroller's slot; a SwiftUI DragGesture of the given kind, or nothing.
private struct SheetPlainPane: View {
    let mode: String
    let atMedium: Bool
    var body: some View {
        let pane = VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { i in Text("Plain \(i)").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.orange.opacity(0.15)) }
        }
        .contentShape(Rectangle())
        switch mode {
        case "simultaneous": pane.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in SheetProbe.shared.plainChanges += 1 })
        case "simultaneous0": pane.simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in SheetProbe.shared.plainChanges += 1 })
        case "gesture": pane.gesture(DragGesture(minimumDistance: 10).onChanged { _ in SheetProbe.shared.plainChanges += 1 })
        case "highPriority": pane.highPriorityGesture(DragGesture(minimumDistance: 10).onChanged { _ in SheetProbe.shared.plainChanges += 1 })
        // The gesture is attached but masked off (`.subviews`): the shape a library could switch per state.
        case "maskedSubviews":
            pane.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in SheetProbe.shared.plainChanges += 1 }, including: .subviews)
        case "spatial":
            if #available(iOS 18, *) {
                pane.simultaneousGesture(SpatialEventGesture().onChanged { _ in SheetProbe.shared.plainChanges += 1 })
            } else {
                pane
            }
        case "magnify":
            pane.simultaneousGesture(MagnificationGesture().onChanged { _ in SheetProbe.shared.plainChanges += 1 })
        // UIKITPAN-s1 Q6: the library's own pinch and double-tap types, alone (MagnifyGesture 17+, SpatialTapGesture 16+).
        case "magnifyLib":
            if #available(iOS 17, *) {
                pane.simultaneousGesture(MagnifyGesture().onChanged { _ in SheetProbe.shared.plainChanges += 1 })
            } else {
                pane.simultaneousGesture(MagnificationGesture().onChanged { _ in SheetProbe.shared.plainChanges += 1 })
            }
        case "spatialTap2":
            if #available(iOS 16, *) {
                pane.simultaneousGesture(SpatialTapGesture(count: 2).onEnded { _ in SheetProbe.shared.plainChanges += 1 })
            } else {
                pane.simultaneousGesture(TapGesture(count: 2).onEnded { SheetProbe.shared.plainChanges += 1 })
            }
        case "doubleTap":
            pane.simultaneousGesture(TapGesture(count: 2).onEnded { SheetProbe.shared.plainChanges += 1 })
        // Everything the library attaches (pan, 0-distance observer / spatial events, pinch, double tap), masked together.
        case "allMaskedAtMedium":
            allGestures(pane, mask: atMedium ? .subviews : .all)
        case "maskedAtMedium":
            pane.simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in SheetProbe.shared.plainChanges += 1 },
                                     including: atMedium ? .subviews : .all)
        default: pane
        }
    }
}

/// `SpatialEventGesture` (iOS 18+) under the same mask; a no-op below.
private struct SpatialMasked: ViewModifier {
    let mask: GestureMask
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.simultaneousGesture(SpatialEventGesture().onChanged { _ in SheetProbe.shared.plainChanges += 1 }, including: mask)
        } else {
            content
        }
    }
}

@MainActor
private func allGestures<V: View>(_ pane: V, mask: GestureMask) -> some View {
    let tick: @MainActor () -> Void = { SheetProbe.shared.plainChanges += 1 }
    return pane
        .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in tick() }, including: mask)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in tick() }, including: mask)
        .simultaneousGesture(MagnificationGesture().onChanged { _ in tick() }, including: mask)
        .simultaneousGesture(TapGesture(count: 2).onEnded { tick() }, including: mask)
        .modifier(SpatialMasked(mask: mask))
}

private struct SheetNativeList: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                SheetRows()
                    .background(GeometryReader { g in
                        let _ = SheetProbe.shared.noteNative(-g.frame(in: .named("sheet.native")).minY)
                        Color.clear
                    })
            }
            .coordinateSpace(name: "sheet.native")
            .onAppear { SheetProbe.shared.nativeScrollTo = { row in proxy.scrollTo("row.\(row)", anchor: .top) } }
        }
    }
}

/// `-ZTronSheetYield scrollDisabled|hitTest|api`: our view switched off while the sheet is not at its largest detent.
private struct SheetYield: ViewModifier {
    let off: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if SheetArgs.yieldsApi {
            experiment(content).ztronScrollYieldsToSheet(off)
        } else {
            experiment(content)
        }
    }

    @ViewBuilder private func experiment(_ content: Content) -> some View {
        switch SheetArgs.yield {
        case "scrollDisabled":
            if #available(iOS 16, *) { content.scrollDisabled(off) } else { content }
        case "ztronScrollDisabled":
            content.ztronScrollDisabled(off)
        case "scrollDisabledAlways":
            if #available(iOS 16, *) { content.scrollDisabled(true) } else { content }
        case "ztronScrollDisabledAlways":
            content.ztronScrollDisabled(true)
        case "hitTest":
            content.allowsHitTesting(!off)
        default:
            content
        }
    }
}

private struct SheetContent: View {
    let detent: String
    @State private var state = ZTronScrollState()

    var body: some View {
        VStack(spacing: 4) {
            SheetReadout(state: state)
            Group {
                if SheetArgs.plain == "uikitpan" {
                    ProbeSheetPager()
                } else if let plain = SheetArgs.plain {
                    SheetPlainPane(mode: plain, atMedium: detent == "medium" && SheetArgs.detents.contains("large"))
                } else if SheetArgs.native {
                    SheetNativeList()
                } else {
                    ZTronScrollView(.vertical, state: state) { SheetRows() }
                }
            }
            .modifier(SheetYield(off: detent == "medium" && SheetArgs.detents.contains("large")))
            .border(Color.gray)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sheet.scroller")
        }
        .padding(.top, 8)
        .onAppear { state.delegate = SheetProbe.shared }
        #if canImport(UIKit)
        .background(SheetSampler(state: SheetArgs.native ? nil : state))
        #endif
    }
}

/// Detents, selection, content interaction and dismissal for the sheet (each newer API behind its `#available`).
private struct SheetChrome: ViewModifier {
    @Binding var detent: String

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.modifier(SheetDetents(detent: $detent)).modifier(SheetInteraction()).interactiveDismissDisabled(SheetArgs.noDismiss)
        } else if #available(iOS 16.0, *) {
            content.modifier(SheetDetents(detent: $detent)).interactiveDismissDisabled(SheetArgs.noDismiss)
        } else {
            content.interactiveDismissDisabled(SheetArgs.noDismiss)
        }
    }
}

@available(iOS 16.0, *)
private struct SheetDetents: ViewModifier {
    @Binding var detent: String
    func body(content: Content) -> some View {
        content.presentationDetents(Set(SheetArgs.detents.map { $0 == "large" ? PresentationDetent.large : .medium }),
                                    selection: Binding(get: { detent == "large" ? .large : .medium },
                                                       set: { detent = $0 == .large ? "large" : "medium"; SheetProbe.shared.detent = detent }))
    }
}

@available(iOS 16.4, *)
private struct SheetInteraction: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        switch SheetArgs.interaction {
        case "scrolls": content.presentationContentInteraction(.scrolls)
        case "resizes": content.presentationContentInteraction(.resizes)
        default: content
        }
    }
}

struct SheetScreen: View {
    @State private var presented = false
    @State private var detent = SheetArgs.start
    @State private var dismissCount = 0
    @State private var baseInfo = ""

    var body: some View {
        VStack(spacing: 12) {
            Button("Present") {
                SheetProbe.shared.detent = SheetArgs.start
                detent = SheetArgs.start
                SheetProbe.shared.onPullRelease = {
                    if detent == "large", SheetArgs.detents.contains("medium") {
                        detent = "medium"
                        SheetProbe.shared.detent = "medium"
                    } else if !SheetArgs.noDismiss {
                        presented = false
                    }
                }
                presented = true
            }
            .accessibilityIdentifier("sheet.present")
            Text("dismissed \(dismissCount)").accessibilityIdentifier("sheet.dismissCount").accessibilityValue("\(dismissCount)")
            Text(SheetArgs.native ? "native ScrollView" : "ZTronScrollView").font(.caption)
            Button("Base snapshot") { baseInfo = SheetProbe.shared.summary }.accessibilityIdentifier("sheet.baseSnapshot")
            Text(baseInfo).font(.system(size: 9)).accessibilityIdentifier("sheet.baseInfo").accessibilityValue(baseInfo)
        }
        .sheet(isPresented: $presented, onDismiss: {
            dismissCount += 1
            SheetProbe.shared.dismissCount += 1
        }) {
            SheetContent(detent: detent).modifier(SheetChrome(detent: $detent))
        }
    }
}
