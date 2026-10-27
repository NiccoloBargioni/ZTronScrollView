import SwiftUI
import ZTronScrollView

/// Samples the visible centre (unscaled content point at the centre of the unobscured viewport) on a timer, outside
/// any view body, and remembers the last value seen under the previous viewport size (SPEC S7 repro).
@MainActor
final class ResizeProbe: ZTronScrollViewDelegate {
    struct Sample { var size: CGSize; var u: CGPoint }
    private(set) var last: Sample?
    private(set) var beforeResize: CGPoint?
    private(set) var resizes = 0
    private var timer: Timer?
    weak var state: ZTronScrollState?

    /// u = (o + c - pad) / s; pad centres content smaller than the viewport (zoom enabled: centre alignment).
    static func centre(_ state: ZTronScrollState) -> (u: CGPoint, c: CGPoint, size: CGSize) {
        let g = state.geometry
        let s = max(state.zoomScale, 0.0001), o = state.contentOffset
        let v = g.containerSize, i = state.adjustedContentInset, k = g.contentSize
        let w = v.width - i.leading - i.trailing, h = v.height - i.top - i.bottom
        let pad = CGPoint(x: max(0, w - s * k.width) / 2, y: max(0, h - s * k.height) / 2)
        let c = CGPoint(x: i.leading + w / 2, y: i.top + h / 2)
        return (CGPoint(x: (o.x + c.x - pad.x) / s, y: (o.y + c.y - pad.y) / s), c, v)
    }

    func start(_ state: ZTronScrollState) {
        self.state = state
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Every presentation change (one per clock tick) is sampled too, so the pre-resize value is the last drawn tick.
    func scrollViewDidScroll(_ state: ZTronScrollState) { sample() }

    private func sample() {
        OverlayLockstep.tick()
        guard let state else { return }
        let r = Self.centre(state)
        if let l = last, l.size != r.size, l.size.width > 0 {
            beforeResize = l.u
            resizes += 1
        }
        last = Sample(size: r.size, u: r.u)
    }

    func reset() { beforeResize = nil; resizes = 0 }
}

/// 15 x 10 grid of 100 pt cells (1500 x 1000); every cell is an accessibility element (ground truth for the drawn
/// position). The body counts itself and has no inputs.
struct ResizeGrid: View {
    static let cell: CGFloat = 100
    static let cols = 15, rows = 10

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return VStack(spacing: 0) {
            ForEach(0..<Self.rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<Self.cols, id: \.self) { c in
                        Text("\(r),\(c)").font(.system(size: 14))
                            .frame(width: Self.cell, height: Self.cell)
                            .background((r + c) % 2 == 0 ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                            .border(Color.gray.opacity(0.4), width: 0.5)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("cell.\(r).\(c)")
                    }
                }
            }
        }
        .frame(width: CGFloat(Self.cols) * Self.cell, height: CGFloat(Self.rows) * Self.cell)
    }
}

/// 6 square columns that take the proposed (viewport) width; 30 rows. Reflows on rotation (content size follows the
/// viewport width), as full-width images and text do in a vertical scroll view.
struct ReflowGrid: View {
    static let cols = 6, rows = 30

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return VStack(spacing: 0) {
            ForEach(0..<Self.rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<Self.cols, id: \.self) { c in
                        Text("\(r),\(c)").font(.system(size: 14))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background((r + c) % 2 == 0 ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                            .border(Color.gray.opacity(0.4), width: 0.5)
                            .accessibilityElement(children: .ignore)
                            .accessibilityIdentifier("cell.\(r).\(c)")
                    }
                }
            }
        }
    }
}

/// Screen-space ground truth: small accessibility-identified markers at known fractions of the content
/// (`marker.detail` at (30 %, 65 %) = the zoomed detail, `marker.centre` at (50 %, 50 %), `marker.tl` / `marker.br`
/// corners). They live INSIDE the content, so their `XCUIElement.frame` is where the content is actually drawn.
struct ContentMarkers: View {
    static let points: [(String, CGFloat, CGFloat)] = [("detail", 0.3, 0.65), ("centre", 0.5, 0.5), ("tl", 0.1, 0.1), ("br", 0.9, 0.9)]

    var body: some View {
        GeometryReader { g in
            let _ = OverlayLockstep.noteContent(g.size)
            ForEach(Self.points, id: \.0) { m in
                Circle().fill(Color.red.opacity(0.6)).frame(width: 6, height: 6)
                    .position(x: g.size.width * m.1, y: g.size.height * m.2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("marker.\(m.0)")
            }
        }
    }
}

/// The user trees' content: the image as wide as the reader, with the markers. It depends on the reader's width, so its
/// body (`content.body`, DEBUG) runs when a rotation changes that width, and never on scrolling or zooming.
struct UserTreeContent: View {
    let width: CGFloat

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return Image("app.global.about.us.snapshot")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: width)
            .overlay(ContentMarkers())
    }
}

/// The user's view trees. `-ZTronResizeUserTree`: a 16:9 two-axis scroller inside a GeometryReader, content =
/// resizable fit image as wide as the GeometryReader. `-ZTronResizeUserTree2` (the user's current app): the same
/// scroller filling a full-screen GeometryReader under the navigation stack (no 16:9 box); in landscape the image is
/// much taller than the viewport, in portrait shorter than it at 1x (centred). `state:` replaces `showsIndicators:`
/// so the readouts can read the geometry (indicators do not affect it).
struct UserTreeScroller: View {
    let state: ZTronScrollState
    var fullScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in
                let scroller = ZTronScrollView([.horizontal, .vertical], state: state) {
                    UserTreeContent(width: proxy.size.width)
                }
                .zoomRange(min: .absolute(1), max: .absolute(4))
                .doubleTapToZoom()
                .resizeContentOverlays()
                .ztronScrollBounceBehavior(ResizeScreen.bounceAlways ? .always : .basedOnSize, axes: .horizontal)
                if fullScreen {
                    scroller
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("scrollerView")
                } else {
                    scroller
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("scrollerView")
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: Content-integral overlays (M6b, `-ZTronResizeOverlay` / `-ZTronResizeOverlayCounterScaled`)

/// The demo's overlays. Most are input-free (no stored properties); `OverlayLabel` has a constant input and the bare
/// `Text` overlay is `Equatable`. A re-evaluation of the call site (the user tree's `GeometryReader` rebuilds the scroll
/// view on every rotation) hands SwiftUI equal values, so none of their bodies runs again. Each body counts itself
/// (DEBUG) for the readout (`mk`, `bn`, `tn`, `lb`, `sp`, `ba`; the bare `Text` only through the library's `ovb`).
struct OverlayMarker: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("demo.overlayMarker.body")
        #endif
        return Circle().fill(Color.orange).frame(width: 6, height: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("overlay.detail")
    }
}

/// A 16:9 banner at the content's bottom with a button (`overlay.button` counts its taps). Under
/// `-ZTronResizeOverlayNoButton` it holds a plain label instead: a control re-renders when the scroll view's
/// `.disabled(blocked)` flips at the start and end of a motion, a label does not.
struct OverlayBanner: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("demo.overlayBanner.body")
        #endif
        return ZStack {
            Color.yellow.opacity(0.3)
            if ResizeScreen.overlayNoButton {
                Text("Banner")
            } else {
                Button("Banner") {
                    #if DEBUG
                    ZTronRenderCounters.increment("overlay.button")
                    #endif
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("overlay.banner.button")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overlay.banner")
    }
}

/// A faint tint over the whole content (`.fillMaxSize`); it takes no touches. Its reader records the size the host gave
/// it for the lockstep probe (`OverlayLockstep`); the reader's closure is not the tint's body.
struct OverlayTint: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("demo.overlayTint.body")
        #endif
        return Rectangle().fill(Color.blue.opacity(0.08))
            .background(GeometryReader { g in
                let _ = OverlayLockstep.noteFill(g.size)
                Color.clear
            })
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("overlay.fill")
    }
}

/// An overlay with a constant stored input (the common real-world case: a caption). Equal on every call-site
/// evaluation, so its body (`lb`) runs once.
struct OverlayLabel: View {
    let title: String

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("demo.overlayLabel.body")
        #endif
        return Text(title).font(.caption2).padding(2).background(Color.white.opacity(0.7))
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("overlay.label")
    }
}

/// A strip across the content's top, 5 % of the content's height tall (`.fillMaxWidth(height: .relative(0.05))`: the
/// free axis is a fraction of the content's height, not of the strip's width). Input-free, takes no touches (`sp`).
struct OverlayStrip: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("demo.overlayStrip.body")
        #endif
        return Rectangle().fill(Color.green.opacity(0.25))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("overlay.strip")
    }
}

/// A 12 pt bar along the content's trailing edge, the content's height tall (`.fillMaxHeight(width: .absolute(12))`,
/// unscaled points: 12 x zoom on screen). Input-free, takes no touches (`ba`).
struct OverlayBar: View {
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("demo.overlayBar.body")
        #endif
        return Rectangle().fill(Color.purple.opacity(0.35))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("overlay.bar")
    }
}

/// DEBUG per-frame lockstep probe (`-ZTronResizeOverlay`). The content's layout size (`ContentMarkers`' reader) and the
/// fill overlay's (`OverlayTint`'s reader) are recorded by their readers and compared on every `ResizeProbe` tick, i.e.
/// between drawn frames: `lag` counts the ticks where they differ (an overlay placed from measured metrics instead of
/// the layout proposal would be drawn one frame late through a reflow); `lks` counts the content sizes seen (the
/// positive control: every rotation changes it).
@MainActor
enum OverlayLockstep {
    private static var content: CGSize?
    private static var fill: CGSize?
    private static var seen: CGSize?

    static func noteContent(_ s: CGSize) { if ResizeScreen.overlay { content = s } }
    static func noteFill(_ s: CGSize) { fill = s }

    static func tick() {
        guard let c = content, let f = fill else { return }
        #if DEBUG
        if c != seen { seen = c; ZTronRenderCounters.increment("demo.lockstep.sizes") }
        if abs(c.width - f.width) > 0.01 || abs(c.height - f.height) > 0.01 {
            ZTronRenderCounters.increment("demo.lockstep.lag")
        }
        #endif
    }
}

extension ZTronScrollView {
    /// The demo overlays under `-ZTronResizeOverlay`, `self` unchanged otherwise (same type either way: no `AnyView`, no
    /// `if` around the scroll view). The tint goes first (lowest), then the strip and the bar, so the banner's button and
    /// the marker draw above them.
    func resizeContentOverlays() -> Self {
        guard ResizeScreen.overlay else { return self }
        return scrollContentIntegralOverlay { OverlayTint() }
            .scrollContentIntegralOverlay(anchor: .top, overlayAnchor: .top, size: .fillMaxWidth(height: .relative(0.05))) {
                OverlayStrip()
            }
            .scrollContentIntegralOverlay(anchor: .trailing, overlayAnchor: .trailing, size: .fillMaxHeight(width: .absolute(12))) {
                OverlayBar()
            }
            .scrollContentIntegralOverlay(anchor: .bottom, overlayAnchor: .bottom, size: .fillMaxWidth(16.0 / 9.0)) {
                OverlayBanner()
            }
            // Inside the content: a small element next to the safe area's edge (the content's top in portrait, its
            // leading or trailing edge in landscape) reports an accessibility frame stretched to the screen's edge.
            .scrollContentIntegralOverlay(anchor: .relative(ZTronUnitPoint(x: 0.7, y: 0.3)), overlayAnchor: .center, size: .ideal) {
                OverlayLabel(title: "Label")
            }
            .scrollContentIntegralOverlay(anchor: .topLeading, overlayAnchor: .topLeading, size: .ideal) { Text("Bare text") }
            .scrollContentIntegralOverlay(anchor: .relative(ZTronUnitPoint(x: 0.3, y: 0.65)), overlayAnchor: .center, size: .ideal,
                                          scaling: ResizeScreen.overlayCounterScaled ? .counterScaled : .withContent) {
                OverlayMarker()
            }
    }
}
/// `-ZTronScreen resize`: full-screen, zoomable grid; rotate the device and compare the centre readout.
struct ResizeScreen: View {
    private static let keys = ["content.body", "resize.jumpFrames", "transform.effect"]
    static let reflow = ProcessInfo.processInfo.arguments.contains("-ZTronResizeReflow")
    static let userTree2 = ProcessInfo.processInfo.arguments.contains("-ZTronResizeUserTree2")
    static let userTree = userTree2 || ProcessInfo.processInfo.arguments.contains("-ZTronResizeUserTree")
    /// `-ZTronResizeBounceAlways`: the user tree's horizontal bounce behavior becomes `.always` (user report 2026-10-19).
    static let bounceAlways = ProcessInfo.processInfo.arguments.contains("-ZTronResizeBounceAlways")
    /// `-ZTronResizeOverlayCounterScaled`: the user tree's marker overlay is `.counterScaled` (implies the overlays).
    static let overlayCounterScaled = ProcessInfo.processInfo.arguments.contains("-ZTronResizeOverlayCounterScaled")
    /// `-ZTronResizeOverlay`: content-integral overlays on the user trees (marker, banner, tint, label, text, strip, bar; M6b).
    static let overlay = overlayCounterScaled || ProcessInfo.processInfo.arguments.contains("-ZTronResizeOverlay")
    /// `-ZTronResizeOverlayNoButton`: the banner holds a label instead of its button (no control in the overlays).
    static let overlayNoButton = ProcessInfo.processInfo.arguments.contains("-ZTronResizeOverlayNoButton")
    @State private var state = ZTronScrollState()
    @State private var probe = ResizeProbe()
    /// Held, not observed: a Snapshot re-renders `ResizeReadoutText` only, never this body (M6b review).
    @State private var readout = ResizeReadout()
    /// Counter resets so far (`rst` in the overlay readout): a test waits for the reset its button scheduled.
    private static var resets = 0

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if Self.userTree {
                    if #available(iOS 16, *) {
                        NavigationStack { UserTreeScroller(state: state, fullScreen: Self.userTree2) }
                    } else {
                        NavigationView { UserTreeScroller(state: state, fullScreen: Self.userTree2) }.navigationViewStyle(.stack)
                    }
                } else if Self.reflow {
                    ZTronScrollView(.vertical, state: state) { ReflowGrid() }.zoomRange(min: .absolute(1), max: .absolute(4))
                } else {
                    ZTronScrollView([.horizontal, .vertical], state: state) { ResizeGrid() }.zoomRange(min: .fit, max: .absolute(4))
                }
            }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scroller")
            VStack(spacing: 4) {
                HStack {
                    Button("Snap") { snapshot() }.accessibilityIdentifier("Snapshot")
                    Button("Fit") { fit() }.accessibilityIdentifier("Fit")
                    Button("Zoom") { zoomIn() }.accessibilityIdentifier("Zoom")
                    Button("Edge") { edge() }.accessibilityIdentifier("Edge")
                    Button("Reset") { resetCounters() }.accessibilityIdentifier("Reset")
                }
                HStack {
                    Button("Mid") { middle() }.accessibilityIdentifier("Mid")
                    Button("Top") { nearEdge(top: true) }.accessibilityIdentifier("Top")
                    Button("Bottom") { nearEdge(top: false) }.accessibilityIdentifier("Bottom")
                }
                ResizeReadoutText(readout: readout)
            }
            .buttonStyle(.bordered)
        }
        .onAppear { state.delegate = probe; probe.start(state) }
    }

    private func fit() {
        state.stopScrollingAndZooming()
        state.setZoomScale(state.minimumZoomScale, animated: false)
        resetCounters()
    }

    /// 1.6x around content point (700, 450); reflow variant: around (50 %, 40 %) of the content; user tree: 2.5x on
    /// an off-centre detail at (30 %, 65 %).
    private func zoomIn() {
        state.stopScrollingAndZooming()
        let s: CGFloat = Self.userTree ? 2.5 : 1.6, v = state.geometry.containerSize, k = state.geometry.contentSize
        let p = Self.userTree ? CGPoint(x: k.width * 0.3, y: k.height * 0.65)
            : Self.reflow ? CGPoint(x: k.width / 2, y: k.height * 0.4) : CGPoint(x: 700, y: 450)
        state.zoom(to: CGRect(x: p.x - v.width / s / 2, y: p.y - v.height / s / 2, width: v.width / s, height: v.height / s),
                   animated: false)
        resetCounters()
    }

    /// Zoom 1, 20 pt inside the top (or bottom) edge: the centre is close to, but not at, a bound.
    private func nearEdge(top: Bool) {
        state.stopScrollingAndZooming()
        state.setZoomScale(1, animated: false)
        let v = state.geometry.containerSize, i = state.adjustedContentInset, k = state.geometry.contentSize
        let y = top ? -i.top + 20 : k.height + i.bottom - v.height - 20
        state.setContentOffset(CGPoint(x: -i.leading, y: y), animated: false)
        resetCounters()
    }

    /// Zoom 1, 40 pt short of the bottom-trailing edge.
    private func edge() {
        state.stopScrollingAndZooming()
        state.setZoomScale(1, animated: false)
        let v = state.geometry.containerSize, i = state.adjustedContentInset
        state.setContentOffset(CGPoint(x: 1500 - v.width + i.trailing - 40, y: 1000 - v.height + i.bottom - 40), animated: false)
        resetCounters()
    }

    /// Zoom 1, content point at 40 % of the content height centred (reflow variant).
    private func middle() {
        state.stopScrollingAndZooming()
        state.setZoomScale(1, animated: false)
        let v = state.geometry.containerSize, i = state.adjustedContentInset, k = state.geometry.contentSize
        let c = i.top + (v.height - i.top - i.bottom) / 2
        state.setContentOffset(CGPoint(x: -i.leading, y: k.height * 0.4 - c), animated: false)
        resetCounters()
    }

    private func resetCounters() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            #if DEBUG
            ZTronRenderCounters.reset()
            #endif
            probe.reset()
            Self.resets += 1
        }
    }

    private func snapshot() {
        var counters: [String: Int] = [:], note = ""
        #if DEBUG
        counters = ZTronRenderCounters.snapshot
        note = ZTronRenderCounters.notes["resize.jump"] ?? ""
        note += " slow{" + (ZTronRenderCounters.notes["transform.slow"] ?? "") + "}"
        note += " clamped{" + (ZTronRenderCounters.notes["transform.clampedAtRest"] ?? "") + "}"
        note += " events{" + ZTronRenderCounters.eventsJoined + "}"   // DEBUG event log (resize ordering probe)
        note += " ovpChanged=\(counters["contentOverlay.place.changed"] ?? 0) ovpLast{" + (ZTronRenderCounters.notes["contentOverlay.place.last"] ?? "") + "}"
        #endif
        let r = ResizeProbe.centre(state)
        let o = state.contentOffset, i = state.adjustedContentInset
        let pre = probe.beforeResize ?? CGPoint(x: -1, y: -1)
        readout.text = String(format: "z=%.4f ox=%.2f oy=%.2f ux=%.2f uy=%.2f cx=%.2f cy=%.2f vw=%.1f vh=%.1f it=%.1f il=%.1f ib=%.1f ir=%.1f phase=%d preux=%.2f preuy=%.2f resizes=%d jump=%d body=%d effect=%d min=%.4f cw=%.2f ch=%.2f cidle=%d vp=%d fast=%d slow=%d slowClosed=%d clamped=%d",
                      state.zoomScale, o.x, o.y, r.u.x, r.u.y, r.c.x, r.c.y, r.size.width, r.size.height,
                      i.top, i.leading, i.bottom, i.trailing, state.phase.rawValue, pre.x, pre.y, probe.resizes,
                      counters["resize.jumpFrames"] ?? 0, counters["content.body"] ?? 0, counters["transform.effect"] ?? 0,
                      state.minimumZoomScale, state.geometry.contentSize.width, state.geometry.contentSize.height,
                      counters["resize.contentSizeIdle"] ?? 0, counters["resize.viewport"] ?? 0,
                      counters["transform.fast"] ?? 0, counters["transform.slow"] ?? 0,
                      counters["transform.slowClosed"] ?? 0, counters["transform.clampedAtRest"] ?? 0)
            + (Self.overlay ? overlayFields(counters) : "") + " note=" + note
    }

    /// Content-overlay counters (`-ZTronResizeOverlay` only, so the readout is unchanged without it): library bodies
    /// (`ovb` overlay roots, `ovh` host, `ovr` iOS 15 reader closure, `ovp` Layout placements, `ocs` counter-scale leaf),
    /// the demo overlays' own bodies (`mk`, `bn`, `tn`, `lb`, `sp` strip, `ba` bar), the banner button's taps (`btap`),
    /// the lockstep probe (`lag` ticks with the fill's size off the content's, `lks` content sizes seen) and the resets so
    /// far (`rst`).
    private func overlayFields(_ c: [String: Int]) -> String {
        String(format: " ovb=%d ovh=%d ovr=%d ovp=%d ocs=%d mk=%d bn=%d tn=%d lb=%d sp=%d ba=%d btap=%d lag=%d lks=%d rst=%d",
               c["contentOverlay.body"] ?? 0, c["contentOverlay.host.body"] ?? 0, c["contentOverlay.reader"] ?? 0,
               c["contentOverlay.place"] ?? 0, c["contentOverlay.counterScale.body"] ?? 0,
               c["demo.overlayMarker.body"] ?? 0, c["demo.overlayBanner.body"] ?? 0, c["demo.overlayTint.body"] ?? 0,
               c["demo.overlayLabel.body"] ?? 0, c["demo.overlayStrip.body"] ?? 0, c["demo.overlayBar.body"] ?? 0,
               c["overlay.button"] ?? 0,
               c["demo.lockstep.lag"] ?? 0, c["demo.lockstep.sizes"] ?? 0, Self.resets)
    }
}

/// The readout's text, held by `ResizeScreen` and observed by `ResizeReadoutText` alone.
final class ResizeReadout: ObservableObject {
    @Published var text = ""
}

/// The readout, a leaf: a Snapshot re-renders this view only, and its fixed frame (three caption lines) keeps the
/// screen's layout the same whatever the text, so taking a readout adds no work of its own to the counters the next
/// readout reads. The accessibility value is the whole text (the tests parse it; the lines are truncated on screen).
struct ResizeReadoutText: View {
    @ObservedObject var readout: ResizeReadout

    var body: some View {
        Text(readout.text).font(.caption2).lineLimit(3)
            .background(Color.white.opacity(0.8))
            .accessibilityIdentifier("resizeInfo").accessibilityValue(readout.text)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42, alignment: .top)
    }
}
