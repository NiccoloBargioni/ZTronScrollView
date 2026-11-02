import SwiftUI
import ZTronScrollView

// M8b-3: the scaling-header screens (docs/design/M8b-refresh-header.md §3, SPEC S14 "Refresh and header").
// `-ZTronScreen profile`: `.fixed(min: 64, max: 240)`, `.preserve`, `-ZTronHeaderSnap immediately|after|disabled` (default
// immediately), `-ZTronHeaderPull openGap|followContent` (D65, default openGap: the header stays still and the pull's gap,
// with the `.system` refresher, opens below it; followContent: the header moves down with the content, the gap above it;
// set through the environment twin `ztronScalingHeaderPullBehavior`), the avatar scale and the title fade through the
// reader.
// `-ZTronScreen banner`: `-ZTronHeaderSize aspect|fixed|fit` (default aspect = `.aspectRatio(16/9)`),
// `-ZTronHeaderOverflow uncapped|capped|refit` (capped = `.capped(fraction: 0.6)`), `.stretch`, a fade,
// the title font from the live height, an overlay refresher over the stretched band, a horizontal-axis toggle.
// Both take `-ZTronHeaderBackground ambient|glass|color|view|none` (ZTronHeaderBackground, default none),
// `-ZTronHeaderCollapse compress|slide|slide0|slide1` (D68: `.compress`, default; `.slideBehind` with parallax 0.5, 0, 1;
// a slide adds a `Cover` button, `snapHeader(to: .height(12))`) and `-ZTronHeaderBackdrop on|off` (with a slide, the
// `backdrop:` color, white; default off: the rows' translucent tints show the header through them),
// `-ZTronHeaderFade single|split|split2|none` (D70; profile default none, banner default single: `.linear(to: .black,
// from: 0.4)`; split = rest that, collapse `.linear(to: .black, from: 0)`, pull nil; split2 = split with a pure red
// collapse state, two colours) and `-ZTronHeaderPlain 1` (the profile header's background pure white: the fade's
// pixels are the fade itself, HeaderUITests' pixel probe), and show
// `content.body`, `header.builder`, `header.frame`, `refresh.actions`, `header.measure` and a `stateInfo` line
// (`y`, `p` progress, `h` height, `R` resting, `smax` largest stretch, `taps` header button taps) after `Info`.

enum HeaderDemo {
    static func argument(_ name: String, _ fallback: String) -> String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
        return fallback
    }

    /// `-ZTronHeaderBackground`: the header's background (what shows where the content leaves the live frame uncovered).
    static var background: ZTronHeaderBackground? {
        switch argument("-ZTronHeaderBackground", "none") {
        case "ambient": return .ambientBlur(radius: 30)
        case "glass": return .frostedGlass(radius: 20)
        case "color": return .color(.black)
        case "view": return .view { LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing) }
        default: return nil
        }
    }

    /// `-ZTronHeaderCollapse compress|slide|slide0|slide1` (D68) with `-ZTronHeaderBackdrop on|off`.
    static var collapse: ZTronHeaderCollapseBehavior {
        let backdrop: Color? = argument("-ZTronHeaderBackdrop", "off") == "on" ? .white : nil
        switch argument("-ZTronHeaderCollapse", "compress") {
        case "slide": return .slideBehind(parallax: 0.5, backdrop: backdrop)
        case "slide0": return .slideBehind(parallax: 0, backdrop: backdrop)
        case "slide1": return .slideBehind(parallax: 1, backdrop: backdrop)
        default: return .compress
        }
    }

    static var slides: Bool { argument("-ZTronHeaderCollapse", "compress").hasPrefix("slide") }

    /// `-ZTronHeaderFade single|split|split2|none` (D70), `fallback` when absent.
    static func fade(_ fallback: String) -> ZTronHeaderFade? {
        let rest = ZTronHeaderFade.Gradient.linear(to: .black, from: 0.4)
        switch argument("-ZTronHeaderFade", fallback) {
        case "single": return .linear(to: .black, from: 0.4)
        case "split": return .init(rest: rest, collapse: .linear(to: .black, from: 0), pull: nil)
        case "split2": return .init(rest: rest, collapse: .linear(to: Color(red: 1, green: 0, blue: 0), from: 0), pull: nil)
        default: return nil
        }
    }

    /// `-ZTronHeaderPlain 1`: the profile header's background is pure white.
    static var plain: Bool { argument("-ZTronHeaderPlain", "0") == "1" }

    static let keys = ["content.body", "header.builder", "header.frame", "refresh.actions", "header.measure"]

    /// The largest stretch and height the header's readers saw since the last reset (written by leaves, read by `Info`).
    @MainActor static var maxStretch: CGFloat = 0
    @MainActor static var maxHeight: CGFloat = 0
    @MainActor static var taps = 0
    /// `-ZTronScreen appbanner`: the largest drawn bottom edge (global y) and width of the image its probe saw.
    @MainActor static var maxBottom: CGFloat = 0
    @MainActor static var maxWidth: CGFloat = 0

    /// The refresh action: `-ZTronLoadSeconds <s>` (default 0.6).
    static func load() async {
        let s = Double(argument("-ZTronLoadSeconds", "0.6")) ?? 0.6
        try? await Task.sleep(nanoseconds: UInt64(max(0, s) * 1_000_000_000))
    }
}

/// A content row that counts its own body: no collapse, stretch, snap or refresh may run it.
struct HeaderRow: View {
    let index: Int
    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("content.body")
        #endif
        return Text("Row \(index)")
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
            .background(index % 2 == 0 ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
            .accessibilityIdentifier("header.row.\(index)")
    }
}

/// The controls and the readout shared by both screens.
struct HeaderDemoChrome: View {
    let state: ZTronScrollState
    @Binding var info: String
    @Binding var snapshot: [String: Int]
    var extra: AnyView = AnyView(EmptyView())
    /// The `header.` identifiers VoiceOver reaches, in its order (`VoiceOverTree`, read on Info): `vo.header`'s value.
    @State private var voiceOver = ""

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Info") { readout() }.accessibilityIdentifier("Info")
                Button("Half") { state.snapHeader(to: .progress(0.5)) }.accessibilityIdentifier("header.half")
                Button("Collapse") { state.snapHeader(to: .collapsed) }.accessibilityIdentifier("header.collapse")
                Button("Expand") { state.snapHeader(to: .expanded) }.accessibilityIdentifier("header.expand")
                if HeaderDemo.slides {
                    // D68: 12 pt of a `.slideBehind` header left uncovered (visible, so hit-testable, but mostly covered).
                    Button("Cover") { state.snapHeader(to: .height(12)) }.accessibilityIdentifier("header.cover")
                }
                extra
            }
            HStack(spacing: 6) {
                ForEach(HeaderDemo.keys, id: \.self) { CounterRow(key: $0, value: snapshot[$0] ?? 0) }
            }
            Text(info).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(info)
                // An overlay: the list never changes the chrome's height (a taller readout resizes the scroll view).
                .overlay(Color.clear.accessibilityElement().accessibilityIdentifier("vo.header").accessibilityValue(voiceOver))
        }
        .font(.caption)
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.endRefreshing()
        state.snapHeader(to: .expanded, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            #if DEBUG
            ZTronRenderCounters.reset()
            #endif
            HeaderDemo.maxStretch = 0
            HeaderDemo.maxHeight = 0
            HeaderDemo.taps = 0
            HeaderDemo.maxBottom = 0
            HeaderDemo.maxWidth = 0
        }
    }

    private func readout() {
        #if DEBUG
        snapshot = ZTronRenderCounters.snapshot
        #endif
        voiceOver = VoiceOverTree.identifiers(prefix: "header.").joined(separator: ",")
        let g = state.headerGeometry
        info = String(format: "y=%.1f p=%.4f h=%.1f R=%.3f smax=%.1f hmax=%.1f taps=%d phase=%d bmax=%.2f wmax=%.2f",
                      state.contentOffset.y, g?.progress ?? -1, g?.height ?? -1, g?.restingHeight ?? -1, HeaderDemo.maxStretch,
                      HeaderDemo.maxHeight, HeaderDemo.taps, state.phase.rawValue, HeaderDemo.maxBottom, HeaderDemo.maxWidth)
    }
}

/// A button inside the header: hit-testable at every live height above 0.5.
struct HeaderTapButton: View {
    var body: some View {
        Button("Follow") { HeaderDemo.taps += 1 }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.85)))
            .accessibilityIdentifier("header.button")
    }
}

/// A childless accessibility element exactly as large as the header's live frame (a `.contain` container would report the
/// union of its children, overflow included): what the UI tests measure.
struct HeaderBox: View {
    var body: some View {
        Color.clear
            .accessibilityElement()
            .accessibilityLabel("header box")
            .accessibilityIdentifier("header.box")
    }
}

/// Records the largest stretch / height it saw (a per-frame reader: it is a leaf, nothing else runs).
struct HeaderProbe: View {
    let header: ZTronHeaderProxy
    var body: some View {
        ZTronHeaderGeometryReader(header) { g in
            let _ = HeaderDemo.maxStretch = max(HeaderDemo.maxStretch, g.stretch)
            let _ = HeaderDemo.maxHeight = max(HeaderDemo.maxHeight, g.height)
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

// MARK: Profile

struct ProfileScreen: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]

    /// `-ZTronHeaderPull openGap|followContent` (D65).
    private var pull: ZTronHeaderPullBehavior {
        HeaderDemo.argument("-ZTronHeaderPull", "openGap") == "followContent" ? .followContent : .openGap
    }

    private var snap: ZTronHeaderSnap {
        switch HeaderDemo.argument("-ZTronHeaderSnap", "immediately") {
        case "after": return .afterFinishAccelerating()
        case "disabled": return .disabled
        default: return .immediately()
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HeaderDemoChrome(state: state, info: $info, snapshot: $snapshot)
            ZTronScrollView(.vertical, state: state) {
                VStack(spacing: 0) { ForEach(0..<40, id: \.self) { HeaderRow(index: $0) } }
            }
            .withScalingHeader(size: .fixed(min: 64, max: 240), collapse: HeaderDemo.collapse, pull: .preserve, snap: snap,
                               fade: HeaderDemo.fade("none"), background: HeaderDemo.background) { header in
                ProfileHeader(header: header)
            }
            .refresher(style: .system) { await HeaderDemo.load() }
            .border(Color.gray)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("header.scroller")
        }
        .padding(.horizontal, 6)
        .ztronScalingHeaderPullBehavior(pull)
    }
}

struct ProfileHeader: View {
    let header: ZTronHeaderProxy
    var body: some View {
        ZStack(alignment: .bottom) {
            if HeaderDemo.plain {
                Color.white
            } else {
                LinearGradient(colors: [.indigo, .teal], startPoint: .top, endPoint: .bottom)
            }
            HStack(alignment: .bottom, spacing: 12) {
                // The avatar shrinks with the collapse; the title fades. Each is its own reader: the header around them
                // never re-runs.
                ZTronHeaderGeometryReader(header, of: { 1 - 0.5 * $0.progress }) { scale in
                    Circle().fill(Color.orange).frame(width: 72, height: 72).scaleEffect(scale, anchor: .bottomLeading)
                }
                ZTronHeaderGeometryReader(header, of: { (20 * (1 - $0.progress)).rounded() / 20 }) { opacity in
                    Text("Profile").font(.title2.bold()).foregroundColor(.white).opacity(opacity)
                }
                Spacer()
                HeaderTapButton()
            }
            .padding(10)
            HeaderProbe(header: header)
        }
        // Takes the live frame even when the avatar row is taller (the overflow is clipped, the row stays glued to the
        // bottom edge): the root's frame IS the header's live height for the UI tests.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .bottom)
        .background(HeaderBox())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("header.root")
    }
}

// MARK: Banner

struct BannerScreen: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]
    @State private var horizontal = HeaderDemo.argument("-ZTronBannerAxis", "vertical") == "horizontal"

    private var overflow: ZTronHeaderOverflow {
        switch HeaderDemo.argument("-ZTronHeaderOverflow", "uncapped") {
        case "capped": return .capped(fraction: 0.6)
        case "refit": return .refit
        default: return .uncapped
        }
    }

    private var size: ZTronHeaderSize {
        switch HeaderDemo.argument("-ZTronHeaderSize", "aspect") {
        case "fixed": return .fixed(min: 0, max: 200)
        case "fit": return .fit()
        default: return .aspectRatio(16.0 / 9.0)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HeaderDemoChrome(state: state, info: $info, snapshot: $snapshot, extra: AnyView(
                Button(horizontal ? "Vertical" : "Horizontal") { horizontal.toggle() }.accessibilityIdentifier("banner.axis")))
            scroller
                .id(horizontal)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("header.scroller")
        }
        .padding(.horizontal, 6)
    }

    private var scroller: some View {
        let base = ZTronScrollView(horizontal ? .horizontal : .vertical, state: state) {
            if horizontal {
                HStack(spacing: 0) { ForEach(0..<20, id: \.self) { HeaderRow(index: $0).frame(width: 120) } }
            } else {
                VStack(spacing: 0) { ForEach(0..<40, id: \.self) { HeaderRow(index: $0) } }
            }
        }
        let current = base.withScalingHeader(size: size, collapse: HeaderDemo.collapse, pull: .stretch,
                                             fade: HeaderDemo.fade("single"), background: HeaderDemo.background,
                                             overflow: overflow) { header in
            BannerHeader(header: header)
        }
        #if DEBUG
        // The deprecated spelling (`scalingBehavior:` → `pull:`), kept so the demo compiles it (with its warning); the
        // collapse switch (D68) needs the current one.
        let headed = HeaderDemo.slides ? current
            : base.withScalingHeader(size: size, scalingBehavior: .stretch, fade: HeaderDemo.fade("single"),
                                     background: HeaderDemo.background, overflow: overflow) { header in
                BannerHeader(header: header)
            }
        #else
        let headed = current
        #endif
        return headed.refresher(overlay: true) { await HeaderDemo.load() }
    }
}

struct BannerHeader: View {
    let header: ZTronHeaderProxy
    var body: some View {
        // `.fit` measures this: a 16:9 picture has an ideal height at the scroll view's width.
        Image("app.global.about.us.snapshot")
            .resizable()
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [.purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .bottomLeading) { BannerTitle(header: header).padding(10) }
            .overlay(alignment: .topTrailing) { HeaderTapButton().padding(10) }
            .overlay(HeaderProbe(header: header))
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(HeaderBox())
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("header.root")
    }
}

/// The "sticky overlay": follows the live bottom edge by layout, resizes its font through the reader.
struct BannerTitle: View {
    let header: ZTronHeaderProxy
    var body: some View {
        ZTronHeaderGeometryReader(header, of: { $0.height.rounded() }) { h in
            Text("Banner").font(.system(size: 17 + 0.08 * h, weight: .bold)).foregroundColor(.white)
                .accessibilityIdentifier("banner.title")
        }
    }
}

// MARK: App banner (D69's motivating setup)

/// Stand-in for the user's theme (`Color(source: self.theme, value: \.appBackground)`), as in ScalingHeaderAPITests.
struct AppBannerTheme {
    var appBackground = Color(red: 0.08, green: 0.09, blue: 0.11)
}

private extension Color {
    init(source: AppBannerTheme, value: KeyPath<AppBannerTheme, Color>) { self = source[keyPath: value] }
}

/// `-ZTronScreen appbanner`: the user's setup from the D69 report (2026-11-01), as spelled: a `NavigationView` around a
/// `GeometryReader` around the scroll view, `.aspectRatio(16/9, min: 0)`, `pull: .stretch`, `fade: .linear(to:
/// appBackground)`, `overflow: .refit`, and an aspect-fit 16:9 `Image` with `maxWidth: .infinity`. Before D69 a pull grew
/// the header's frame while the aspect-fit image inside it stayed W × W·9/16 (nothing visibly grew); now the image is drawn
/// scaled by (R + g) / R about its top centre, its bottom edge on the content's top. `-ZTronAppBannerCall deprecated`
/// makes the same call through the deprecated `scalingBehavior: .stretch` spelling (the user's literal call).
/// The chrome (`HeaderDemoChrome`) floats over the bottom of the screen as an overlay, so the scroll view's layout is the
/// user's; its `appbanner.pull` button holds a pull of 60 pt (`setContentOffset` past the top, unanimated: like UIKit, the
/// offset stays until the next touch) and `appbanner.rest` puts the content back at the top. Test probe (HeaderUITests):
/// an accessibility element overlaid on the image (`appbanner.image`, the image's frame), whose geometry reader records
/// the largest drawn bottom edge and width it saw (`bmax`, `wmax` in `stateInfo`); a scroll delegate records the largest
/// pull (`smax`).
struct AppBannerScreen: View {
    let theme = AppBannerTheme()
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]
    @State private var probe = AppBannerPullProbe()

    private static var deprecatedCall: Bool { HeaderDemo.argument("-ZTronAppBannerCall", "current") == "deprecated" }

    var body: some View {
        NavigationView {
            GeometryReader { _ in
                scroller
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("header.scroller")
            }
            .navigationTitle("About us")
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .bottom) {
                HeaderDemoChrome(state: state, info: $info, snapshot: $snapshot, extra: AnyView(HStack(spacing: 8) {
                    Button("Pull") { pull(60) }.accessibilityIdentifier("appbanner.pull")
                    Button("Rest") { pull(0) }.accessibilityIdentifier("appbanner.rest")
                }))
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(Color(white: 0.92))
            }
        }
        .onAppear { state.delegate = probe }
    }

    private var scroller: ZTronScrollView<AppBannerContent> {
        let base = ZTronScrollView(.vertical, state: state) { AppBannerContent() }
        if Self.deprecatedCall {
            return base.withScalingHeader(size: .aspectRatio(16.0/9.0, min: 0.0), scalingBehavior: .stretch,
                                          fade: .linear(to: Color(source: self.theme, value: \.appBackground)), overflow: .refit,
                                          header: { _ in Image("app.global.about.us.snapshot").resizable().aspectRatio(16.0/9.0, contentMode: .fit)
                                              .overlay(AppBannerImageProbe())
                                              .frame(maxWidth: .infinity) })
        }
        return base.withScalingHeader(size: .aspectRatio(16.0/9.0, min: 0.0), pull: .stretch,
                                      fade: .linear(to: Color(source: self.theme, value: \.appBackground)), overflow: .refit,
                                      header: { _ in Image("app.global.about.us.snapshot").resizable().aspectRatio(16.0/9.0, contentMode: .fit)
                                          .overlay(AppBannerImageProbe())
                                          .frame(maxWidth: .infinity) })
    }

    /// A pull of `g` pt, held: the offset `g` past the top edge, unanimated (0: back at the top; `Reset`'s
    /// `snapHeader(to: .expanded)` leaves a view at or above rest where it is, S10 "Snapping").
    private func pull(_ g: CGFloat) {
        state.setContentOffset(CGPoint(x: 0, y: -state.adjustedContentInset.top - g), animated: false)
    }
}

/// The rows (each counts its own body).
struct AppBannerContent: View {
    var body: some View {
        VStack(spacing: 0) { ForEach(0..<40, id: \.self) { HeaderRow(index: $0) } }
    }
}

/// Records the largest pull (the header's stretch) the scroll view reported.
@MainActor
final class AppBannerPullProbe: ZTronScrollViewDelegate {
    func scrollViewDidScroll(_ state: ZTronScrollState) {
        HeaderDemo.maxStretch = max(HeaderDemo.maxStretch, state.headerGeometry?.stretch ?? 0)
    }
}

/// The test probe overlaid on the user's image: a childless accessibility element exactly as large as the image's frame
/// (`appbanner.image`), whose reader records the largest global bottom edge and width (render-time scale included).
struct AppBannerImageProbe: View {
    var body: some View {
        GeometryReader { g in
            let f = g.frame(in: .global)
            let _ = MainActor.assumeIsolated {
                HeaderDemo.maxBottom = max(HeaderDemo.maxBottom, f.maxY)
                HeaderDemo.maxWidth = max(HeaderDemo.maxWidth, f.width)
            }
            Color.clear
        }
        .accessibilityElement()
        .accessibilityLabel("app banner image")
        .accessibilityIdentifier("appbanner.image")
    }
}
