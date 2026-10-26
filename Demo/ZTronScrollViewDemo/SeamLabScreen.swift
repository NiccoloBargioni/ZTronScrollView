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
// between the header's bottom and the content's top), `-ZTronHeaderOverflow uncapped|capped|refit` (D52; capped =
// .capped(fraction: 0.5)), `-ZTronHeaderBackground ambient|glass|color|view` (ZTronHeaderBackground: with ambient, color
// and view the red content is a 16:9 box fitted into the frame and the background, red too, fills the rest of the live
// frame, so the analyzer measures the BACKGROUND's edges wherever the frame is not 16:9; glass keeps the filling content,
// a material is not a pure color).
// The white square at the bottom-trailing corner (`seam.width`) animates the scroll view's width between full and 60 %
// of the screen (easeInOut 1.2 s), centered: an app-driven animated viewport resize. SeamLabUITests.testPull drags the
// content down from its middle and holds (the `.preserve` header moves down with it, the `.stretch` one grows).

enum SeamLab {
    static let red = Color(red: 1, green: 0, blue: 0)
    static let green = Color(red: 0, green: 1, blue: 0)
    static let blue = Color(red: 0, green: 0, blue: 1)
    static let yellow = Color(red: 1, green: 1, blue: 0)
    static let magenta = Color(red: 1, green: 0, blue: 1)

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

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomTrailing) {
                // Laid out in the safe area like a native ScrollView: the library extends the viewport to the screen
                // edges it touches and reserves the safe area in adjustedContentInset (top0 = the safe-area top).
                ZTronScrollView(.vertical, state: state) { SeamLabContent() }
                    .scrollIndicators(.hidden)
                    .withScalingHeader(size: SeamLab.size, scalingBehavior: SeamLab.behavior, background: SeamLab.background,
                                       overflow: SeamLab.overflow) { _ in SeamLabHeader() }
                    .background(SeamLab.blue)
                    .frame(width: narrow ? g.size.width * 0.6 : g.size.width, height: g.size.height)
                    .frame(maxWidth: .infinity)
                Button {
                    withAnimation(.easeInOut(duration: 1.2)) { narrow.toggle() }
                } label: {
                    Color.white.frame(width: 24, height: 24)
                }
                .accessibilityIdentifier("seam.width")
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
        .background(SeamLab.blue.ignoresSafeArea())
    }
}

/// The header: pure red filling the live frame. Under `.fit` a 16:9 red view measures W · 9/16 at the proposed width.
/// With a letterboxing background the red content is a 16:9 box fitted into the frame (the background fills the rest).
struct SeamLabHeader: View {
    var body: some View {
        if SeamLab.letterboxed {
            SeamLab.red
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        } else if SeamLab.isFit {
            SeamLab.red
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
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
                (i % 2 == 0 ? SeamLab.yellow : SeamLab.magenta).frame(height: 60)
            }
        }
        .frame(maxWidth: .infinity)
        .background(SeamLab.blue)
    }
}
