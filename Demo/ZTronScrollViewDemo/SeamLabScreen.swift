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
// between the header's bottom and the content's top), `-ZTronHeaderOverflow uncapped|capped|capped<digits>|refit` (D59;
// capped = .capped(fraction: 0.5), capped25 = .capped(fraction: 0.25)), `-ZTronHeaderBackground ambient|glass|color|view` (ZTronHeaderBackground: with ambient, color
// and view the red content is a 16:9 box fitted into the frame and the background, red too, fills the rest of the live
// frame, so the analyzer measures the BACKGROUND's edges wherever the frame is not 16:9; glass keeps the filling content,
// a material is not a pure color), `-ZTronSeamMarker 1` (row 4, content y 320..380, pure cyan instead of yellow: a
// marker at a known content y that fixes the content's top when the green row is scrolled under a collapsed header;
// analyzer v2.2).
// The white square at the bottom-trailing corner (`seam.width`) animates the scroll view's width between full and 60 %
// of the screen (easeInOut 1.2 s), centered: an app-driven animated viewport resize. SeamLabUITests.testPull drags the
// content down from its middle and holds (the `.preserve` header stays still and the gap opens below it, or with
// `-ZTronSeamPull followContent` moves down with the content, D65; the `.stretch` one grows).
// `-ZTronSeamPull openGap|followContent` (D65): the member `scalingHeaderPullBehavior(_:)` (default: not set, `.openGap`).
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
// (no action) 0.8 s after launch, so every later stimulus runs during a refresh hold (M8b-s6); `-ZTronSeamHoldEdge
// top|bottom|leading|trailing` and `-ZTronSeamHoldOverlay 1` pick its edge and placement (open item 19);
// `-ZTronSeamHoldSystem <H>` makes it the built-in `.system` indicator (L 60) with `holdOffset` H instead (R1-RC1-1, header
// behaviors fixer round 2: a gray spinner, scripts/seam/spinner.py), `-ZTronSeamHoldEnd <s>` ends the refresh (`endRefreshing`)
// `s` seconds after it began (its retraction).
// Resize variants (M8b-s6 close, the verifier's break probes): `-ZTronSeamBottomPinned 1` (the height change is bottom-pinned:
// the scroll view's top leaves the top safe area), `-ZTronSeamBoth 1` (height and width together), `-ZTronSeamSpring 1` (a
// bouncy spring instead of easeInOut), `-ZTronSeamRetarget <s>` (the toggle again `s` seconds into the change), and
// `-ZTronSeamLandscape 1` (SeamLabUITests.testWidth rotates to landscape first).
// `-ZTronSeamCollapse compress|slideBehind[:k]` (D68): the `collapse:` mode (default compress; slideBehind = parallax 0.5,
// slideBehind:0 / slideBehind:1 that parallax): the red header keeps its height behind the content (whose opaque blue
// background covers it) and moves up by k times the covered distance; `seam.scroll`'s band is then R. `-ZTronSeamRuler 1`:
// six white bars in the header (header y 20 + 40 i, 2 + 2 i pt tall, x 5–45 % of its width): the header's position read
// from any bar left uncovered and unclipped (as it moves up, the header is clipped at the scroll view's frame, here the
// safe-area top, like the content), so the parallax can be measured.
// `-ZTronSeamFade single|split|split2` (D70; default none): a pure white fade over the red header (a pixel's opacity is
// its green channel): single = `.linear(to: white, from: 0.5)` in every state; split = rest that, collapse
// `.linear(to: white, from: 0)`, pull nil (full at a pull of R / 2); split2 = split with a pure black collapse state (two
// colours: the over-operator pair). The seam analyzer does not apply to a faded header (its bottom rows are white);
// fade recordings are read by the fade tracker (scratchpad b4/fade.py). SeamLabUITests reads `-ZTronSeamPullDrag <pt>`
// (testPull's drag, default 220 pt from 55 % of the window's height; longer drags start at 25 %).
// `-ZTronSeamAppBanner 1` (D69, the user's setup): the lab inside a `NavigationView` (an inline bar with a blank title) and the
// user's `GeometryReader`, the header `.aspectRatio(16/9, min: 0)` (whatever `-ZTronHeaderSize` says) whose content is the
// user's chain on a pure red image: `Image(...).resizable().aspectRatio(16/9, contentMode: .fit).frame(maxWidth: .infinity)`.
// With `-ZTronHeaderBehavior stretch -ZTronHeaderOverflow refit` it is the user's call (the fade is `-ZTronSeamFade`'s,
// none by default: the seam analyzer reads an unfaded red header).

enum SeamLab {
    static let red = Color(red: 1, green: 0, blue: 0)
    static let green = Color(red: 0, green: 1, blue: 0)
    static let blue = Color(red: 0, green: 0, blue: 1)
    static let yellow = Color(red: 1, green: 1, blue: 0)
    static let magenta = Color(red: 1, green: 0, blue: 1)
    static let cyan = Color(red: 0, green: 1, blue: 1)

    static var size: ZTronHeaderSize {
        if appBanner { return .aspectRatio(16.0 / 9.0, min: 0) }
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
        let arg = HeaderDemo.argument("-ZTronHeaderOverflow", "uncapped")
        switch arg {
        case "capped": return .capped(fraction: 0.5)
        case "refit": return .refit
        default:
            // `capped<digits>` (D64): `.capped(fraction: 0.<digits>)`, e.g. capped25 = 0.25 (engaged in portrait).
            if arg.hasPrefix("capped"), let f = Double("0." + arg.dropFirst(6)) { return .capped(fraction: CGFloat(f)) }
            return .uncapped
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
    /// Core check (M8b-s6 close): `-ZTronSeamFakeKeyboard <pt>` (seam.width toggles a bottom safeAreaInset of <pt>, easeInOut 1.2 s) and
    /// `-ZTronSeamKeyboard 1` (seam.width toggles the focus of a 24 pt white TextField: the real keyboard).
    @State private var kbFake = false
    @FocusState private var kbFocus: Bool
    @State private var kbText = ""
    /// Core check (M8b-s6 close): `-ZTronSeamRetargetNear <eps>` with `-ZTronSeamRetarget <s>`: `s` seconds into the change the height
    /// is retargeted to the DRAWN height + eps (a non-collinear retarget near the presented value).
    @State private var retargetHeight: CGFloat? = nil

    var body: some View {
        if SeamLab.appBanner {
            // A no-break space as the title: the bar is shown (an empty title shows none on 27.0) with no glyph in it.
            NavigationView { lab.navigationTitle("\u{00A0}").navigationBarTitleDisplayMode(.inline) }
        } else {
            lab
        }
    }

    private var lab: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomTrailing) {
                // Laid out in the safe area like a native ScrollView: the library extends the viewport to the screen
                // edges it touches and reserves the safe area in adjustedContentInset (top0 = the safe-area top).
                scroller
                    .background(SeamLab.blue)
                    .frame(width: narrow && (SeamLab.heightFactor == nil || SeamLab.both) ? g.size.width * 0.6 : g.size.width,
                           height: retargetHeight ?? g.size.height * (narrow ? SeamLab.heightFactor ?? 1 : 1))
                    .modifier(SeamLabDrawnHeight(value: retargetHeight ?? g.size.height * (narrow ? SeamLab.heightFactor ?? 1 : 1)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: SeamLab.bottomPinned ? .bottom : .top)
                HStack(spacing: 4) {
                    Button {
                        snapped.toggle()
                        state.snapHeader(to: snapped ? .collapsed : .expanded, animated: true)
                    } label: {
                        Color.white.frame(width: 24, height: 24)
                    }
                    .accessibilityIdentifier("seam.snap")
                    if SeamLab.realKeyboard {
                        TextField("", text: $kbText).focused($kbFocus).frame(width: 24, height: 24).background(Color.white)
                            .accessibilityIdentifier("seam.kb")
                    }
                    Button {
                        toggleScroll()
                    } label: {
                        Color.white.frame(width: 24, height: 24)
                    }
                    .accessibilityIdentifier("seam.scroll")
                    Button {
                        if SeamLab.fakeKeyboard != nil {
                            withAnimation(.easeInOut(duration: 1.2)) { kbFake.toggle() }
                        } else if SeamLab.realKeyboard {
                            kbFocus.toggle()
                        } else if SeamLab.fitGrow {
                            // A `.fit` re-measure: the header's content changes height in an app animation.
                            withAnimation(.easeInOut(duration: 1.2)) { tall.toggle() }
                        } else if SeamLab.widthWithScroll {
                            // One transaction: the size change and the scroll command together.
                            withAnimation(.easeInOut(duration: 1.2)) { narrow.toggle(); toggleScroll(animated: false) }
                        } else {
                            withAnimation(SeamLab.resizeAnimation) { narrow.toggle(); retargetHeight = nil }
                            if let delay = SeamLab.retarget, let eps = SeamLab.retargetNear, narrow {
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                                    let d = SeamLabDrawnHeight.drawn
                                    print("SEAMLAB retarget near drawn \(d) -> \(d + eps)")
                                    withAnimation(SeamLab.resizeAnimation) { retargetHeight = d + eps }
                                }
                            } else if let delay = SeamLab.retarget, SeamLab.retargetNear == nil {
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
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: kbFake ? SeamLab.fakeKeyboard ?? 0 : 0) }
        .background(SeamLab.blue.ignoresSafeArea())
        .overlay(alignment: .topLeading) { if SeamLab.info { SeamLabInfo(state: state) } }
        .task {
            if let y = SeamLab.startY {
                try? await Task.sleep(nanoseconds: 600_000_000)
                state.scroll(to: CGPoint(x: 0, y: y))
            }
            guard SeamLab.hold else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            let edge = SeamLab.holdEdge
            if edge == .bottom || edge == .trailing {
                // The far end first: `beginRefreshing` reveals the hold only when the content is at its edge.
                let g = state.geometry, i = state.adjustedContentInset
                state.scroll(to: edge == .bottom
                    ? CGPoint(x: 0, y: max(-i.top, g.contentSize.height - g.containerSize.height + i.bottom))
                    : CGPoint(x: max(-i.leading, g.contentSize.width - g.containerSize.width + i.trailing), y: 0))
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            state.beginRefreshing(edge: edge)
            guard let end = SeamLab.holdEnd else { return }
            try? await Task.sleep(nanoseconds: UInt64(end * 1_000_000_000))
            state.endRefreshing(edge: edge)
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
        let base = ZTronScrollView(SeamLab.horizontal ? .horizontal : .vertical, state: state) { SeamLabContent() }
            .scrollIndicators(.hidden)
        var view = SeamLab.noHeader ? base : base
            .withScalingHeader(size: SeamLab.size, collapse: SeamLab.collapse, pull: SeamLab.behavior, fade: SeamLab.fade,
                               background: SeamLab.background, overflow: SeamLab.overflow) { [tall] _ in SeamLabHeader(tall: tall) }
        if let pull = SeamLab.pull { view = view.scalingHeaderPullBehavior(pull) }
        if SeamLab.hold {
            if let ho = SeamLab.holdSystem {
                // R1-RC1-1: the built-in `.system` indicator (L 60) with `holdOffset` ho.
                return view.refresher(style: .system, overlay: SeamLab.holdOverlay,
                                      configuration: ZTronRefreshConfiguration(indicatorHeight: 60, holdOffset: ho,
                                                                               allowedEdges: Edge.Set(SeamLab.holdEdge))) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
            }
            // A held refresh with a white probe as its indicator (centred in the indicator's frame), on the edge
            // `-ZTronSeamHoldEdge` names (open item 19), in the gap or floating (`-ZTronSeamHoldOverlay 1`).
            return view.refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20) },
                                  overlay: SeamLab.holdOverlay,
                                  configuration: ZTronRefreshConfiguration(allowedEdges: Edge.Set(SeamLab.holdEdge))) {
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
    /// `-ZTronSeamFade single|split|split2` (D70, see the file header).
    static var fade: ZTronHeaderFade? {
        let white = Color(red: 1, green: 1, blue: 1), black = Color(red: 0, green: 0, blue: 0)
        let rest = ZTronHeaderFade.Gradient.linear(to: white, from: 0.5)
        switch HeaderDemo.argument("-ZTronSeamFade", "none") {
        case "single": return .linear(to: white, from: 0.5)
        case "split": return .init(rest: rest, collapse: .linear(to: white, from: 0), pull: nil)
        case "split2": return .init(rest: rest, collapse: .linear(to: black, from: 0), pull: nil)
        default: return nil
        }
    }
    /// `-ZTronSeamRuler 1` (D68): white position marks in the header.
    static var ruler: Bool { HeaderDemo.argument("-ZTronSeamRuler", "0") == "1" }
    /// `-ZTronSeamCollapse compress|slideBehind[:k]` (D68).
    static var collapse: ZTronHeaderCollapseBehavior {
        let arg = HeaderDemo.argument("-ZTronSeamCollapse", "compress")
        guard arg.hasPrefix("slideBehind") else { return .compress }
        let k = arg.split(separator: ":").dropFirst().first.flatMap { Double($0) } ?? 0.5
        return .slideBehind(parallax: CGFloat(k))
    }
    /// `-ZTronSeamPull openGap|followContent` (D65); absent: not set (the library default, `.openGap`).
    static var pull: ZTronHeaderPullBehavior? {
        switch HeaderDemo.argument("-ZTronSeamPull", "") {
        case "openGap": return .openGap
        case "followContent": return .followContent
        default: return nil
        }
    }
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
    /// `-ZTronSeamHeaderText 1` (D69, risk 7): black 24 pt text centred in the header, to compare its edges at rest and
    /// scaled by a `.stretch` hold (blur of a scaled stack). Not for seam analysis (black reads as "outside the window").
    static var headerText: Bool { HeaderDemo.argument("-ZTronSeamHeaderText", "0") == "1" }
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
        } else if SeamLab.ruler {
            content.overlay(alignment: .topLeading) { SeamLabRuler() }
        } else if SeamLab.headerText {
            content.overlay { Text("Stretch Aa 0123").font(.system(size: 24, weight: .bold)).foregroundColor(.black) }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        if SeamLab.appBanner {
            SeamLab.redImage.resizable().aspectRatio(16.0 / 9.0, contentMode: .fit).frame(maxWidth: .infinity)
        } else if SeamLab.letterboxed {
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

/// `-ZTronSeamRuler 1` (D68): the header's position marks (see the file header).
struct SeamLabRuler: View {
    var body: some View {
        GeometryReader { g in
            ForEach(0..<6, id: \.self) { i in
                Color.white
                    .frame(width: g.size.width * 0.4, height: CGFloat(2 + 2 * i))
                    .offset(x: g.size.width * 0.05, y: CGFloat(20 + 40 * i))
            }
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


// MARK: Core check probes (M8b-s6 close): retarget near the drawn size, no header, start offset
extension SeamLab {
    static var retargetNear: CGFloat? { Double(HeaderDemo.argument("-ZTronSeamRetargetNear", "")).map { CGFloat($0) } }
    static var noHeader: Bool { HeaderDemo.argument("-ZTronSeamNoHeader", "0") == "1" }
    static var startY: CGFloat? { Double(HeaderDemo.argument("-ZTronSeamStartY", "")).map { CGFloat($0) } }
}

// MARK: Open item 19 probes: the hold's edge and placement
extension SeamLab {
    /// `-ZTronSeamHoldEdge top|bottom|leading|trailing` (with `-ZTronSeamHold 1`): the held refresher's edge; default the
    /// axis' start edge. An end edge scrolls to that end first, so the hold is revealed.
    static var holdEdge: Edge {
        switch HeaderDemo.argument("-ZTronSeamHoldEdge", "") {
        case "top": return .top
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        default: return horizontal ? .leading : .top
        }
    }
    /// `-ZTronSeamHoldOverlay 1`: the held refresher floats over the content (overlay placement).
    static var holdOverlay: Bool { HeaderDemo.argument("-ZTronSeamHoldOverlay", "0") == "1" }
    /// `-ZTronSeamHoldSystem <H>` (with `-ZTronSeamHold 1`): the built-in `.system` indicator, `holdOffset` H (R1-RC1-1).
    static var holdSystem: CGFloat? { Double(HeaderDemo.argument("-ZTronSeamHoldSystem", "")).map { CGFloat($0) } }
    /// `-ZTronSeamHoldEnd <s>` (with `-ZTronSeamHold 1`): `endRefreshing` `s` seconds after the hold began.
    static var holdEnd: Double? { Double(HeaderDemo.argument("-ZTronSeamHoldEnd", "")) }
}

/// Reads the presented (animated) frame height every frame (`-ZTronSeamRetargetNear`).
/// A GeometryEffect is asked about the animated (drawn) size every frame, as the library's own transform is.
nonisolated struct SeamLabDrawnHeight: GeometryEffect {
    var value: CGFloat
    nonisolated(unsafe) static var drawn: CGFloat = 0
    var animatableData: EmptyAnimatableData { get { EmptyAnimatableData() } set { } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        SeamLabDrawnHeight.drawn = size.height
        return ProjectionTransform()
    }
}

// MARK: Core check probes: keyboard
extension SeamLab {
    static var fakeKeyboard: CGFloat? { Double(HeaderDemo.argument("-ZTronSeamFakeKeyboard", "")).map { CGFloat($0) } }
    static var realKeyboard: Bool { HeaderDemo.argument("-ZTronSeamKeyboard", "0") == "1" }
}

// MARK: The user's setup (D69)
extension SeamLab {
    /// `-ZTronSeamAppBanner 1` (see the file header).
    static var appBanner: Bool { HeaderDemo.argument("-ZTronSeamAppBanner", "0") == "1" }
    /// A pure red 16 × 9 picture (the user's `Image`, in the lab's colour).
    static let redImage: Image = {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: 16, height: 9, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Image(systemName: "xmark") }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
        guard let cg = ctx.makeImage() else { return Image(systemName: "xmark") }
        return Image(decorative: cg, scale: 1)
    }()
}
