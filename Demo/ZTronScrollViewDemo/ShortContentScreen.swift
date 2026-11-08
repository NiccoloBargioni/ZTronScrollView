import SwiftUI
import ZTronScrollView

// D75 (M8b-s8 s10, design M8b-s8-d75 §8 step 7): `-ZTronScreen shortContent`, the "Short content" page. Content shorter
// than the viewport below a `.fixed(min: 64, max: 240)` scaling header, centred (`.defaultScrollAnchor(.center, for:
// .alignment)`; a zoomable view centres by default), with the three `fittingContent:` cases on a segmented picker
// (`short.fitting`: "Top" `.topAligned`, "Follows" `.headerFollows`, "Pinned" `.headerPinned`; a change is animated),
// the pull behaviour (`short.pull`: "Preserve" / "Stretch") and, with "Stretch", the `stretchContent:` picker
// (`header.stretchContent`). Rows: `short.add` / `short.remove` (animated, 0.5 s) and `short.addPlain` /
// `short.removePlain` (unanimated); `short.zoomable` toggles a zoomable variant (`zoomRange(1...4)`: pinch the rows).
// Launch arguments: `-ZTronShortFitting top|follows|pinned` (default follows), `-ZTronShortRows <n>` (default 5),
// `-ZTronShortPull preserve|stretch` (default preserve), `-ZTronShortZoomable 1`, `-ZTronStretchContent magnified|size`.
// The chrome's counters show `content.body` (only the inserted rows' own bodies run) and `header.builder` (a cold
// option change runs it once).

struct ShortContentScreen: View {
    @State private var state = ZTronScrollState()
    @State private var info = ""
    @State private var snapshot: [String: Int] = [:]
    @State private var fitting: ZTronHeaderFittingContent = {
        switch HeaderDemo.argument("-ZTronShortFitting", "follows") {
        case "top": return .topAligned
        case "pinned": return .headerPinned
        default: return .headerFollows
        }
    }()
    @State private var stretch = HeaderDemo.argument("-ZTronShortPull", "preserve") == "stretch"
    @State private var stretchContent = HeaderDemo.stretchContent
    @State private var rows = Int(HeaderDemo.argument("-ZTronShortRows", "5")) ?? 5
    @State private var zoomable = HeaderDemo.argument("-ZTronShortZoomable", "0") == "1"

    var body: some View {
        VStack(spacing: 4) {
            HeaderDemoChrome(state: state, info: $info, snapshot: $snapshot, below: AnyView(controls))
            scroller
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("short.scroller")
        }
        .padding(.horizontal, 6)
    }

    private var controls: some View {
        VStack(spacing: 4) {
            Picker("Fitting", selection: $fitting.animation(.easeInOut(duration: 0.5))) {
                Text("Top").tag(ZTronHeaderFittingContent.topAligned)
                Text("Follows").tag(ZTronHeaderFittingContent.headerFollows)
                Text("Pinned").tag(ZTronHeaderFittingContent.headerPinned)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("short.fitting")
            HStack(spacing: 8) {
                Picker("Pull", selection: $stretch) {
                    Text("Preserve").tag(false)
                    Text("Stretch").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 170)
                .accessibilityIdentifier("short.pull")
                if stretch { StretchContentPicker(value: $stretchContent) }
            }
            HStack(spacing: 10) {
                Button("Add") { withAnimation(.easeInOut(duration: 0.5)) { rows += 1 } }.accessibilityIdentifier("short.add")
                Button("Remove") { withAnimation(.easeInOut(duration: 0.5)) { rows = max(0, rows - 1) } }
                    .accessibilityIdentifier("short.remove")
                Button("Add plain") { rows += 1 }.accessibilityIdentifier("short.addPlain")
                Button("Remove plain") { rows = max(0, rows - 1) }.accessibilityIdentifier("short.removePlain")
                Toggle("Zoom", isOn: $zoomable).labelsHidden().accessibilityIdentifier("short.zoomable")
            }
        }
    }

    private var scroller: some View {
        let rows = rows
        var view = ZTronScrollView(.vertical, state: state) {
            VStack(spacing: 0) { ForEach(0..<rows, id: \.self) { HeaderRow(index: $0) } }
        }
        if zoomable { view = view.zoomRange(min: .absolute(1), max: .absolute(4)) }
        return view
            .defaultScrollAnchor(.center, for: .alignment)
            .withScalingHeader(size: .fixed(min: 64, max: 240), pull: stretch ? .stretch : .preserve,
                               fade: .linear(to: .black, from: 0.4), fittingContent: fitting,
                               stretchContent: stretchContent) { header in
                ShortContentHeader(header: header)
            }
            .refresher(style: .system) { await HeaderDemo.load() }
    }
}

/// The page's header: a gradient banner with a title and a symbol (text keeps its point size under `.keepTextSize`).
struct ShortContentHeader: View {
    let header: ZTronHeaderProxy

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                Text("Short content").font(.title2.bold())
            }
            .foregroundColor(.white)
            .padding(12)
            HeaderBox()
            HeaderProbe(header: header)
        }
        .accessibilityIdentifier("short.header")
    }
}
