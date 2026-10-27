import SwiftUI
import ZTronScrollView

// M8b-3 R5: the seam lab (`-ZTronScreen seamlab`). A full-screen scaling-header scroll view drawn in pure colors so a
// screen recording can be classified per pixel (scripts/seam/analyze.py): pure blue background (also behind the
// content), a pure red header filling its live frame, a pure green first row (80 pt), then 40 rows alternating pure
// yellow / pure magenta (60 pt). No text in the measured column.
// `-ZTronHeaderSize fixed|aspect|fit` (fixed = .fixed(min: 64, max: 240), aspect = .aspectRatio(16/9, min: 64),
// fit = .fit(min: 64) over a 16:9 red view), `-ZTronHeaderBehavior preserve|stretch`,
// `-ZTronSeamStart rest|half|collapsed` (half = snapHeader(.progress(0.5), animated: false) before the first layout,
// collapsed = snapHeader(.collapsed)), `-ZTronSeamInset <pt>` (contentInset.top: the analyzer's control, a known gap
// between the header's bottom and the content's top), `-ZTronHeaderOverflow uncapped|capped|refit` (D59; capped =
// .capped(fraction: 0.5)), `-ZTronHeaderBackground ambient|glass|color|view` (ZTronHeaderBackground: with ambient, color
// and view the red content is a 16:9 box fitted into the frame and the background, red too, fills the rest of the live
// frame, so the analyzer measures the BACKGROUND's edges wherever the frame is not 16:9; glass keeps the filling content,
// a material is not a pure color), `-ZTronSeamMarker 1` (row 4, content y 320..380, pure cyan instead of yellow: a
// marker at a known content y that fixes the content's top when the green row is scrolled under a collapsed header;
// analyzer v2.2).
// The white square at the bottom-trailing corner (`seam.width`) animates the scroll view's width between full and 60 %
// of the screen (easeInOut 1.2 s), centered: an app-driven animated viewport resize. SeamLabUITests.testPull drags the
// content down from its middle and holds (the `.preserve` header moves down with it, the `.stretch` one grows).
// Left of it, `seam.scroll` toggles a transaction-driven scroll (`withAnimation(.easeInOut(duration: 1.2)) {
// state.scroll(to:) }`) between rest and y = 400 (past the collapse band, the content under the collapsed header), and
// `seam.snap` toggles `snapHeader(to: .collapsed / .expanded, animated: true)` (the clock path). `-ZTronSeamRefresh <s>`
// adds a `.system` refresher whose action takes `s` seconds: testPull then measures the refresh hold and its end.
// `-ZTronSeamScrollBand <f>` makes `seam.scroll` target the point `f` of the way into the collapse band;
// `-ZTronSeamWidthThenScroll <s>` makes `seam.width` also toggle that scroll `s` seconds into the width animation,
// `-ZTronSeamWidthWithScroll 1` in the same `withAnimation` as the size change. `-ZTronSeamAnimateHeight <f>` (review d16,
// M8b-s6): `seam.width` animates the scroll view's HEIGHT to `f` of the safe area's instead, top-pinned (its bottom leaves
// the home indicator: the bottom safe-area inset goes 34 -> 0 with the change; with `capped` / `refit` the limit engages).
// White probes (pure white, labelled "other" by the analyzer; scripts/seam/probe.py tracks them against the header's
// bottom edge): `-ZTronSeamSticky 1` puts a 120 x 16 pt bar in an `.overlay(alignment: .bottom)` of the header content (a
// sticky overlay); `-ZTronSeamHold 1` installs a refresher whose indicator is a 20 x 20 pt square and begins refreshing
// (no action) 0.8 s after launch, so every later stimulus runs during a refresh hold (M8b-s6).
// Resize variants (M8b-s6 close, the verifier's break probes): `-ZTronSeamBottomPinned 1` (the height change is bottom-pinned:
// the scroll view's top leaves the top safe area), `-ZTronSeamBoth 1` (height and width together), `-ZTronSeamSpring 1` (a
// bouncy spring instead of easeInOut), `-ZTronSeamRetarget <s>` (the toggle again `s` seconds into the change), and
// `-ZTronSeamLandscape 1` (SeamLabUITests.testWidth rotates to landscape first).

enum SeamLab {
    static let red = Color(red: 1, green: 0, blue: 0)
    static let green = Color(red: 0, green: 1, blue: 0)
    static let blue = Color(red: 0, green: 0, blue: 1)
    static let yellow = Color(red: 1, green: 1, blue: 0)
    static let magenta = Color(red: 1, green: 0, blue: 1)
    static let cyan = Color(red: 0, green: 1, blue: 1)

    static var size: ZTronHeaderSize {
        switch HeaderDemo.argument("-ZTronHeaderSize", "fixed") {
        case "aspect": return .aspectRatio(16.0 / 9.0, min: 64)
        case "fit": return .fit(min: 64)
        default: return .fixed(min: 64, max: 240)
        }
    }

    static var isFit: Bool { HeaderDemo.argument("-ZTronHeaderSize", "fixed") == "fit" }

    static var behavior: ZTronHeaderScalingBehavior {
        HeaderDemo.argument("-ZTronHeaderBehavior", "preserve") == "stretch" ? .stretch : .preserve
    }

    static var startsHalf: Bool { HeaderDemo.argument("-ZTronSeamStart", "rest") == "half" }
    static var startsCollapsed: Bool { HeaderDemo.argument("-ZTronSeamStart", "rest") == "collapsed" }

    static var inset: CGFloat { CGFloat(Double(HeaderDemo.argument("-ZTronSeamInset", "0")) ?? 0) }

    static var overflow: ZTronHeaderOverflow {
        switch HeaderDemo.argument("-ZTronHeaderOverflow", "uncapped") {
        case "capped": return .capped(fraction: 0.5)
        case "refit": return .refit
        default: return .uncapped
        }
    }

    static var marker: Bool { HeaderDemo.argument("-ZTronSeamMarker", "0") == "1" }

    static var backgroundName: String { HeaderDemo.argument("-ZTronHeaderBackground", "none") }

    static var background: ZTronHeaderBackground? {
        switch backgroundName {
        case "ambient": return .ambientBlur(radius: 20)
        case "glass": return .frostedGlass(radius: 20)
        case "color": return .color(red)
        case "view": return .view { LinearGradient(colors: [red, red], startPoint: .top, endPoint: .bottom) }
        default: return nil
        }
    }

    /// The header content leaves room for the background (a 16:9 box fitted into the live frame).
    static var letterboxed: Bool { ["ambient", "color", "view"].contains(backgroundName) }
}

struct SeamLabScreen: View {
    @State private var state: ZTronScrollState = {
        let s = ZTronScrollState()
        s.contentInset.top = SeamLab.inset
        // Queued before the first layout: applied unanimated once the header, viewport and content are known.
        if SeamLab.startsHalf { s.snapHeader(to: .progress(0.5), animated: false) }
        if SeamLab.startsCollapsed { s.snapHeader(to: .collapsed, animated: false) }
        return s
    }()
    @State private var narrow = false
    /// `-ZTronSeamFitGrow 1`: `seam.width` toggles the header's content between 16:9 and 4:3 instead (review d16).
    @State private var tall = false
    @State private var far = false
    @State private var snapped = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomTrailing) {
                // Laid out in the safe area like a native ScrollView: the library extends the viewport to the screen
                // edges it touches and reserves the safe area in adjustedContentInset (top0 = the safe-area top).
                scroller
                    .background(SeamLab.blue)
                    .frame(width: narrow && (SeamLab.heightFactor == nil || SeamLab.both) ? g.size.width * 0.6 : g.size.width,
                           height: g.size.height * (narrow ? SeamLab.heightFactor ?? 1 : 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: SeamLab.bottomPinned ? .bottom : .top)
                HStack(spacing: 4) {
                    Button {
                        snapped.toggle()
                        state.snapHeader(to: snapped ? .collapsed : .expanded, animated: true)
                    } label: {
                        Color.white.frame(width: 24, height: 24)
                    }
                    .accessibilityIdentifier("seam.snap")
                    Button {
                        toggleScroll()
                    } label: {
                        Color.white.frame(width: 24, height: 24)
                    }
                    .accessibilityIdentifier("seam.scroll")
                    Button {
                        if SeamLab.fitGrow {
                            // A `.fit` re-measure: the header's content changes height in an app animation.
                            withAnimation(.easeInOut(duration: 1.2)) { tall.toggle() }
                        } else if SeamLab.widthWithScroll {
                            // One transaction: the size change and the scroll command together.
                            withAnimation(.easeInOut(duration: 1.2)) { narrow.toggle(); toggleScroll(animated: false) }
                        } else {
                            withAnimation(SeamLab.resizeAnimation) { narrow.toggle() }
                            if let delay = SeamLab.retarget {
                                // The same toggle again mid-flight: SwiftUI composes the two changes additively.
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                                    withAnimation(SeamLab.resizeAnimation) { narrow.toggle() }
                                }
                            }
                        }
                        if let delay = SeamLab.widthThenScroll {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                                toggleScroll()
                            }
                        }
                    } label: {
                        Color.white.frame(width: 24, height: 24)
                    }
                    .accessibilityIdentifier("seam.width")
                }
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
        .background(SeamLab.blue.ignoresSafeArea())
        .overlay(alignment: .topLeading) { if SeamLab.info { SeamLabInfo(state: state) } }
        .task {
            guard SeamLab.hold else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            state.beginRefreshing()
        }
    }
}

extension SeamLabScreen {
    /// `seam.scroll`: a transaction-driven scroll between rest and y = 400, or (`-ZTronSeamScrollBand <f>`) the point `f`
    /// of the way into the collapse band (the header's bottom stays on the content's top all the way).
    private func toggleScroll(animated: Bool = true) {
        far.toggle()
        let top = -state.adjustedContentInset.top
        var y: CGFloat = 400
        if let f = SeamLab.scrollBand, let g = state.headerGeometry {
            y = top + f * max(0, g.restingHeight - g.minHeight)
        }
        let target = CGPoint(x: 0, y: far ? y : top)
        if animated {
            withAnimation(.easeInOut(duration: 1.2)) { state.scroll(to: target) }
        } else {
            state.scroll(to: target)
        }
    }

    /// The lab's scroll view; with `-ZTronSeamRefresh <s>` a `.system` refresher whose action takes `s` seconds (the
    /// refresh hold: the content rests below the indicator, the header follows it).
    private var scroller: ZTronScrollView<SeamLabContent> {
        let view = ZTronScrollView(SeamLab.horizontal ? .horizontal : .vertical, state: state) { SeamLabContent() }
            .scrollIndicators(.hidden)
            .withScalingHeader(size: SeamLab.size, scalingBehavior: SeamLab.behavior, background: SeamLab.background,
                               overflow: SeamLab.overflow) { [tall] _ in SeamLabHeader(tall: tall) }
        if SeamLab.hold {
            // A held refresh with a white probe as its indicator (centred in the indicator's frame).
            return view.refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20) }) {
                try? await Task.sleep(nanoseconds: 1_000_000_000_000)
            }
        }
        guard let seconds = SeamLab.refreshSeconds else { return view }
        // Trigger at 60 pt: the 220 pt drag of testPull crosses it under the rubber band and fires while pulling.
        return view.refresher(style: .system, configuration: ZTronRefreshConfiguration(triggerDistance: 60)) {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }
}

extension SeamLab {
    static var scrollBand: CGFloat? { Double(HeaderDemo.argument("-ZTronSeamScrollBand", "")).map { CGFloat($0) } }
    /// `-ZTronSeamWidthThenScroll <s>`: `seam.width` also toggles the scroll `s` seconds later, while the resize is open
    /// (a scroll command closes it inside its animated transaction: the header's held offset at the close).
    static var widthThenScroll: Double? { Double(HeaderDemo.argument("-ZTronSeamWidthThenScroll", "")) }
    /// `-ZTronSeamWidthWithScroll 1`: `seam.width` toggles the size and the scroll in ONE `withAnimation`.
    static var widthWithScroll: Bool { HeaderDemo.argument("-ZTronSeamWidthWithScroll", "0") == "1" }
    /// `-ZTronSeamFitGrow 1` (review d16): `seam.width` animates the `.fit` header's content between 16:9 and 4:3 (a
    /// re-measure of an animated header content change) instead of the width.
    static var fitGrow: Bool { HeaderDemo.argument("-ZTronSeamFitGrow", "0") == "1" }
    /// `-ZTronSeamAnimateHeight <f>` (review d16, M8b-s6): `seam.width` animates the scroll view's height to `f` of the
    /// safe area's (top-pinned) instead of its width.
    static var heightFactor: CGFloat? { Double(HeaderDemo.argument("-ZTronSeamAnimateHeight", "")).map { CGFloat($0) } }
    /// `-ZTronSeamBottomPinned 1` (M8b-s6 close, verifier probe vbottom): the scroll view is bottom-pinned, so a height
    /// change moves its TOP off the top safe area (the top inset goes 62 -> 0 with the change on 27.0, 59 -> 0 on 17.5).
    static var bottomPinned: Bool { HeaderDemo.argument("-ZTronSeamBottomPinned", "0") == "1" }
    /// `-ZTronSeamBoth 1` (vboth): with `-ZTronSeamAnimateHeight`, the width animates to 60 % too.
    static var both: Bool { HeaderDemo.argument("-ZTronSeamBoth", "0") == "1" }
    /// `-ZTronSeamSpring 1` (vspring): `seam.width` animates with `.spring(response: 0.55, dampingFraction: 0.5)` (the frame
    /// overshoots its target) instead of `.easeInOut(duration: 1.2)`.
    static var resizeAnimation: Animation {
        HeaderDemo.argument("-ZTronSeamSpring", "0") == "1" ? .spring(response: 0.55, dampingFraction: 0.5)
            : .easeInOut(duration: 1.2)
    }
    /// `-ZTronSeamRetarget <s>` (vretarget): `seam.width` toggles the size back `s` seconds later, while the first change
    /// is in flight (a toggle tapped twice quickly; SwiftUI composes the two animations additively).
    static var retarget: Double? { Double(HeaderDemo.argument("-ZTronSeamRetarget", "")) }
    /// `-ZTronSeamHold 1`: a held refresh (white probe indicator) from 0.8 s after launch.
    static var hold: Bool { HeaderDemo.argument("-ZTronSeamHold", "0") == "1" }
    /// `-ZTronSeamSticky 1`: a white bar in a bottom-aligned overlay of the header content (a sticky overlay).
    static var sticky: Bool { HeaderDemo.argument("-ZTronSeamSticky", "0") == "1" }
    static var refreshSeconds: Double? {
        Double(HeaderDemo.argument("-ZTronSeamRefresh", "")).map { max(0, $0) }
    }
}

/// `-ZTronSeamInfo 1` (diagnostics only, it draws over the lab): the state's geometry twice a second as an accessibility
/// value (`seam.info`) that SeamLabUITests prints.
struct SeamLabInfo: View {
    let state: ZTronScrollState
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let text = line()
            Text(text).font(.system(size: 6)).foregroundColor(.white)
                .accessibilityIdentifier("seam.info").accessibilityValue(text)
        }
        .allowsHitTesting(false)
        #if DEBUG
        .onAppear { if SeamLab.events { ZTronRenderCounters.eventCapacity = 400 } }
        #endif
    }

    private func line() -> String {
        let g = state.headerGeometry
        let vp = state.geometry.containerSize
        var text = String(format: "vp=%.1fx%.1f aci=%.1f/%.1f y=%.2f R=%.3f h=%.3f p=%.4f", vp.width,
                          vp.height, state.adjustedContentInset.top, state.adjustedContentInset.bottom,
                          state.contentOffset.y, g?.restingHeight ?? -1, g?.height ?? -1, g?.progress ?? -1)
        #if DEBUG
        if SeamLab.events { text += " EVENTS " + ZTronRenderCounters.eventsJoined }
        #endif
        return text
    }
}

extension SeamLab {
    static var info: Bool { ["1", "2"].contains(HeaderDemo.argument("-ZTronSeamInfo", "0")) }
    /// `-ZTronSeamInfo 2`: the state's DEBUG event log too (diagnostics).
    static var events: Bool { HeaderDemo.argument("-ZTronSeamInfo", "0") == "2" }
}

/// The header: pure red filling the live frame. Under `.fit` a 16:9 red view measures W · 9/16 at the proposed width.
/// With a letterboxing background the red content is a 16:9 box fitted into the frame (the background fills the rest).
struct SeamLabHeader: View {
    /// `-ZTronSeamFitGrow 1`: 4:3 instead of 16:9 (`.fit` re-measures a taller header).
    var tall = false

    var body: some View {
        if SeamLab.sticky {
            content.overlay(alignment: .bottom) { Color.white.frame(width: 120, height: 16) }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if SeamLab.letterboxed {
            SeamLab.red
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        } else if SeamLab.isFit {
            SeamLab.red
                .aspectRatio(tall ? 4.0 / 3.0 : 16.0 / 9.0, contentMode: .fit)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .background(SeamLab.red)
        } else {
            SeamLab.red
        }
    }
}

struct SeamLabContent: View {
    var body: some View {
        VStack(spacing: 0) {
            SeamLab.green.frame(height: 80)
            ForEach(0..<40, id: \.self) { i in
                (i == 4 && SeamLab.marker ? SeamLab.cyan : i % 2 == 0 ? SeamLab.yellow : SeamLab.magenta)
                    .frame(height: 60)
            }
        }
        .frame(minWidth: SeamLab.horizontal ? 2000 : 0, maxWidth: .infinity)
        .background(SeamLab.blue)
    }
}

extension SeamLab {
    /// `-ZTronSeamAxis horizontal` (review d16): the lab on a horizontal scroll view (the header is a fixed banner, the
    /// content 2000 pt wide).
    static var horizontal: Bool { HeaderDemo.argument("-ZTronSeamAxis", "vertical") == "horizontal" }
}
