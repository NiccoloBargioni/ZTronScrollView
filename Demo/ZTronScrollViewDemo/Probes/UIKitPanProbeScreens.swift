import SwiftUI
import UIKit
import ZTronScrollView

// UIKITPAN-s1 probe screens (docs/design/UIKIT-pan.md §4), driven by `UIKitPanProbeUITests`:
// - the sheet pager (`-ZTronScreen sheet -ZTronSheetPlain uikitpan`, Q1/Q2/Q8; also the S pager of Q9's cover);
// - `-ZTronScreen uikitPanPage -ZTronProbeTarget carousel|list|zoomer|nativeCarousel|nativeList|plain [-ZTronProbeCover plain|pager]`:
//   N, a target between bands of SwiftUI's own vertical `ScrollView` (DBG-s8's MixedProbe / MixedTopology page), Q3 and Q9;
// - `-ZTronScreen uikitPanPager [-ZTronProbeDisabled]`: a 2-axis probe view with controls under a nav bar, a tab bar and a
//   pinned header, Q5 and Q7;
// - `-ZTronScreen uikitPanDetect -ZTronProbeParent nativeV|nativeH|list|form|tabPage|sheet|ztron|none`: Q4.

// MARK: - S: the sheet pager (4 pages; page 1 is a zoomer)

struct ProbeSheetPager: View {
    private let pager = ProbeHub.shared.model("pager", axes: .horizontal, paging: true, factor: CGSize(width: 4, height: 1))
    private let zoomer = ProbeHub.shared.model("zoomer", axes: [.horizontal, .vertical], factor: CGSize(width: 1, height: 1))

    var body: some View {
        let pd = ProbeHub.shared.driver("pager", model: pager)
        let zd = ProbeHub.shared.driver("zoomer", model: zoomer)
        zd.isInner = true
        return ProbeScroller(model: pager, driver: pd) { size in
            HStack(spacing: 0) {
                ProbePage(index: 0)
                ProbeScroller(model: zoomer, driver: zd) { _ in ProbeZoomerContent(model: zoomer) }
                    .frame(width: size.width, height: size.height)
                ProbePage(index: 2)
                ProbePage(index: 3)
            }
            .frame(width: size.width * 4, height: size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("probe.pager")
    }

    /// `P0`: page 0, zoomer at 1×. `ZMid`: page 1, zoomer 2× at the middle. `ZEdge`: page 1, zoomer 2× at its trailing edge.
    static func position(_ kind: String) {
        let hub = ProbeHub.shared
        guard let pager = hub.models["pager"], let zoomer = hub.models["zoomer"] else { return }
        zoomer.factor = kind == "P0" ? CGSize(width: 1, height: 1) : CGSize(width: 2, height: 2)
        let m = zoomer.maxOff
        zoomer.off = kind == "P0" ? .zero : CGPoint(x: kind == "ZEdge" ? m.x : (m.x / 2).rounded(), y: (m.y / 2).rounded())
        pager.off = CGPoint(x: kind == "P0" ? 0 : pager.viewport.width, y: 0)
        zoomer.objectWillChange.send()
        pager.start = pager.off
        zoomer.start = zoomer.off
    }
}

private struct ProbePage: View {
    let index: Int
    var body: some View {
        GeometryReader { g in
            ZStack {
                (index % 2 == 0 ? Color.blue : Color.teal).opacity(0.25)
                Text("Page \(index)").font(.title)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

private struct ProbeZoomerContent: View {
    @ObservedObject var model: ProbeModel
    var body: some View {
        GeometryReader { g in
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { c in
                            ((r + c) % 2 == 0 ? Color.purple : Color.pink).opacity(0.3)
                        }
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .overlay(Text("Zoomer ×\(Int(model.factor.width))").font(.title2))
        }
    }
}

// MARK: - N: a target inside SwiftUI's own vertical ScrollView

struct UIKitPanPageScreen: View {
    static let target = ProbeArgs.value("-ZTronProbeTarget") ?? "carousel"
    static let cover = ProbeArgs.value("-ZTronProbeCover")
    @State private var covered = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 4) {
                HStack {
                    ProbeReadout(onReset: {
                        proxy.scrollTo("pageMid", anchor: .top)
                        Self.resetNative()
                    })
                    if Self.cover != nil {
                        Button("Cover") { covered = true }.font(.footnote).accessibilityIdentifier("probe.cover")
                    }
                }
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        Color.red.opacity(0.4).frame(height: 200).background(ProbeScrollFinder(page: true))
                        Color.clear.frame(height: 1).id("pageMid")
                        Color.orange.opacity(0.3).frame(height: 60)
                        target.frame(height: 200).accessibilityElement(children: .contain).accessibilityIdentifier("probe.target")
                        Color.green.opacity(0.3).frame(height: 900)
                    }
                }
                .border(Color.gray)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("pageMid", anchor: .top) } }
            }
            .padding(.horizontal, 8)
        }
        .background(ProbeTicker())
        .sheet(isPresented: $covered) { ProbeCover(kind: Self.cover ?? "plain") }
    }

    private static func resetNative() {
        guard let sv = ProbeHub.shared.nativeScroll else { return }
        let mx = max(0, sv.contentSize.width - sv.bounds.width), my = max(0, sv.contentSize.height - sv.bounds.height)
        sv.setContentOffset(CGPoint(x: (mx / 2).rounded(), y: (my / 2).rounded()), animated: false)
    }

    @ViewBuilder private var target: some View {
        let hub = ProbeHub.shared
        switch Self.target {
        case "carousel":
            let m = hub.model("carousel", axes: .horizontal, factor: CGSize(width: 6, height: 1), home: CGPoint(x: 0.5, y: 0))
            ProbeScroller(model: m, driver: hub.driver("carousel", model: m, detectedAxis: .vertical)) { size in
                HStack(spacing: 8) { ForEach(0..<18, id: \.self) { Text("Card \($0)").frame(width: size.width / 3 - 8, height: size.height).background(Color.blue.opacity(0.3)) } }
            }
        case "list":
            let m = hub.model("list", axes: .vertical, factor: CGSize(width: 1, height: 6), home: CGPoint(x: 0, y: 0.5))
            ProbeScroller(model: m, driver: hub.driver("list", model: m, detectedAxis: .vertical)) { size in
                VStack(spacing: 0) { ForEach(0..<60, id: \.self) { Text("Row \($0)").frame(width: size.width, height: size.height / 10).background($0 % 2 == 0 ? Color.blue.opacity(0.2) : Color.clear) } }
            }
        case "zoomer":
            let m = hub.model("zoomer1x", axes: [.horizontal, .vertical], factor: CGSize(width: 1, height: 1))
            ProbeScroller(model: m, driver: hub.driver("zoomer1x", model: m, detectedAxis: .vertical)) { _ in
                Color.purple.opacity(0.25).overlay(Text("Zoomer 1×"))
            }
        case "nativeCarousel":
            ScrollView(.horizontal) {
                HStack(spacing: 8) { ForEach(0..<18, id: \.self) { Text("Card \($0)").frame(width: 110, height: 200).background(Color.blue.opacity(0.3)) } }
                    .background(ProbeScrollFinder(page: false))
            }
        case "nativeList":
            ScrollView(.vertical) {
                VStack(spacing: 0) { ForEach(0..<60, id: \.self) { Text("Row \($0)").frame(maxWidth: .infinity, minHeight: 20).background($0 % 2 == 0 ? Color.blue.opacity(0.2) : Color.clear) } }
                    .background(ProbeScrollFinder(page: false))
            }
        default:
            Color.blue.opacity(0.3).overlay(Text("plain"))
        }
    }
}

/// Q9: what covers the N carousel (a sheet at the large detent): a plain pane, or the S pager.
private struct ProbeCover: View {
    let kind: String
    var body: some View {
        VStack(spacing: 4) {
            ProbeReadout()
            if kind == "pager" {
                ProbeSheetPager()
            } else {
                Color.orange.opacity(0.3).overlay(Text("cover"))
            }
        }
        .padding(.top, 8)
        .modifier(ProbeLargeDetent())
    }
}

private struct ProbeLargeDetent: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16, *) { content.presentationDetents([.large]) } else { content }
    }
}

// MARK: - Q5 / Q7: a 2-axis probe view with controls, under a nav bar, a tab bar and a pinned header

@MainActor
final class ProbeControls: ObservableObject {
    static let shared = ProbeControls()
    @Published var taps = 0
    @Published var slider = 0.5
    @Published var toggle = false
    @Published var text = ""
    @Published var wheel = 10
    @Published var stepper = 0
    @Published var seg = 0

    var summary: String {
        "ctlB=\(taps) ctlS=\(String(format: "%.2f", slider)) ctlT=\(toggle ? 1 : 0) ctlX=\(text.isEmpty ? "-" : text) ctlW=\(wheel) ctlSt=\(stepper) ctlSeg=\(seg)"
    }
}

struct UIKitPanPagerScreen: View {
    private let model = ProbeHub.shared.model("controls", axes: [.horizontal, .vertical], factor: CGSize(width: 2, height: 2),
                                              home: CGPoint(x: 0.5, y: 0.5))

    var body: some View {
        NavigationView {
            TabView {
                page.tabItem { Label("Probe", systemImage: "hand.draw") }
                Text("Other").tabItem { Label("Other", systemImage: "circle") }
            }
            .navigationTitle("Probe")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .background(ProbeTicker())
    }

    private var page: some View {
        VStack(spacing: 4) {
            ProbeReadout(extra: { ProbeControls.shared.summary })
            ZStack(alignment: .top) {
                ProbeScroller(model: model, driver: ProbeHub.shared.driver("controls", model: model)) { size in
                    ZStack {
                        Color.gray.opacity(0.08)
                        ProbeControlsGrid(ctl: ProbeControls.shared)
                            .frame(width: size.width, height: size.height)
                            .position(x: size.width, y: size.height)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("probe.scroller")
                Text("Pinned header").frame(maxWidth: .infinity, minHeight: 44).background(Color.yellow)
                    .accessibilityIdentifier("probe.header")
            }
            .disabled(ProbeArgs.flag("-ZTronProbeDisabled"))
        }
    }
}

private struct ProbeControlsGrid: View {
    @ObservedObject var ctl: ProbeControls

    var body: some View {
        VStack(spacing: 6) {
            Color.clear.frame(height: 46)
            Button("Tap me") { ctl.taps += 1; probeCount("button.fired") }
                .frame(maxWidth: .infinity, minHeight: 40).background(Color.blue.opacity(0.15))
                .accessibilityIdentifier("ctl.button")
            Slider(value: $ctl.slider, in: 0...1).padding(.horizontal, 60).accessibilityIdentifier("ctl.slider")
            Toggle("Toggle", isOn: $ctl.toggle).padding(.horizontal, 40).accessibilityIdentifier("ctl.toggle")
            TextField("Field", text: $ctl.text).textFieldStyle(.roundedBorder).padding(.horizontal, 40)
                .accessibilityIdentifier("ctl.text")
            Picker("Wheel", selection: $ctl.wheel) { ForEach(0..<20, id: \.self) { Text("W\($0)").tag($0) } }
                .pickerStyle(.wheel).frame(height: 110).clipped().accessibilityIdentifier("ctl.wheel")
            Stepper("Step \(ctl.stepper)", value: $ctl.stepper).padding(.horizontal, 40).accessibilityIdentifier("ctl.stepper")
            Picker("Seg", selection: $ctl.seg) { Text("A").tag(0); Text("B").tag(1); Text("C").tag(2) }
                .pickerStyle(.segmented).padding(.horizontal, 40).accessibilityIdentifier("ctl.segment")
            Color.gray.opacity(0.25).frame(height: 70).overlay(Text("empty"))
                .accessibilityElement(children: .ignore).accessibilityIdentifier("ctl.empty")
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Q4: what `bounds(of: .scrollView(axis:))` sees inside a ZTron viewport

struct UIKitPanDetectScreen: View {
    static let parent = ProbeArgs.value("-ZTronProbeParent") ?? "none"
    @State private var sheet = parent == "sheet"
    @State private var inner = ZTronScrollState()
    @State private var outer = ZTronScrollState()

    var body: some View {
        VStack(spacing: 4) {
            ProbeReadout()
            parentView
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $sheet) { VStack { ProbeReadout(); innerView; Spacer() }.padding(.top, 8) }
    }

    private var innerView: some View {
        ZTronScrollView(.horizontal, state: inner) {
            HStack(spacing: 8) { ForEach(0..<12, id: \.self) { Text("Card \($0)").frame(width: 100, height: 80).background(Color.blue.opacity(0.3)) } }
        }
        .frame(height: 80)
        .background(ProbeDetectLeaf())
    }

    @ViewBuilder private var parentView: some View {
        switch Self.parent {
        case "nativeV": ScrollView(.vertical) { VStack { innerView; Color.green.opacity(0.2).frame(height: 1200) } }
        case "nativeH": ScrollView(.horizontal) { HStack { innerView.frame(width: 320); Color.green.opacity(0.2).frame(width: 800) } }
        case "list": List { innerView; Text("Row") }
        case "form": Form { innerView; Text("Row") }
        case "tabPage": TabView { innerView.tag(0); Color.green.opacity(0.2).tag(1) }.tabViewStyle(.page).frame(height: 200)
        case "ztron": ZTronScrollView(.vertical, state: outer) { VStack { innerView; Color.green.opacity(0.2).frame(height: 1200) } }
        case "sheet": Text("presenting")
        default: innerView
        }
    }
}

/// The design's detector shape (`onGeometryChange` on a background leaf) plus a GeometryReader read for comparison:
/// `S` any `.scrollView` space, `V` vertical, `H` horizontal, `-` none.
private struct ProbeDetectLeaf: View {
    var body: some View {
        if #available(iOS 17, *) {
            Color.clear
                .onGeometryChange(for: String.self) { Self.code($0) } action: { ProbeHub.shared.notes["det"] = $0 }
                .background(GeometryReader { p in Color.clear.onAppear { ProbeHub.shared.notes["detGR"] = Self.code(p) } })
        } else {
            Color.clear.onAppear { ProbeHub.shared.notes["det"] = "n/a" }
        }
    }

    @available(iOS 17, *)
    nonisolated static func code(_ p: GeometryProxy) -> String {
        let s = p.bounds(of: .scrollView) != nil, v = p.bounds(of: .scrollView(axis: .vertical)) != nil
        let h = p.bounds(of: .scrollView(axis: .horizontal)) != nil
        return "\(s ? "S" : "-")\(v ? "V" : "-")\(h ? "H" : "-")"
    }
}
