import SwiftUI
import ZTronScrollView
#if canImport(UIKit)
import UIKit
#endif

/// The values of the UIKit-backed controls of `UIKitControlsScreen`; the readout outside the scroll view prints them, so a
/// UI test reads one `Text` instead of each control's own accessibility value (which differs per OS and per control).
final class UIKitControlsModel: ObservableObject {
    /// Fixed so a calendar popover opens on the same month on every run: 15 March 2026, noon, local time.
    static let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @Published var steps = 0
    @Published var segment = 0
    @Published var compactDate = UIKitControlsModel.start
    @Published var wheelDate = UIKitControlsModel.start
    @Published var choice = "none"
    @Published var color = Color.red
    /// How many times the colour binding was set (the colour picker reports each selection while it is open).
    @Published var colorChanges = 0
    /// `-ZTronControlsWheels` (PICKER-s1): the `Picker(.wheel)` row and the slider of the wheels content.
    @Published var pick = 0
    @Published var slider = 0.0

    var readout: String {
        "stepper=\(steps) segment=\(segment) compact=\(Self.dayFormat.string(from: compactDate)) "
            + "wheel=\(Self.dayFormat.string(from: wheelDate)) menu=\(choice) colorChanges=\(colorChanges) color=\(colorHex) "
            + "pick=\(pick) slider=\(Int((slider * 100).rounded()))"
    }

    private var colorHex: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        #else
        return "-"
        #endif
    }
}

/// Touch-based UIKit controls behind SwiftUI (DBG-s4): Stepper, `Picker(.segmented)`, `DatePicker` (compact and wheel), `Menu`,
/// `ColorPicker`, all inside the scroll view. Every control has an identifier `ctl.<name>`.
struct UIKitControlsContent: View {
    @ObservedObject var model: UIKitControlsModel

    var body: some View {
        VStack(spacing: 14) {
            Stepper("Steps", value: $model.steps, in: 0...200).accessibilityIdentifier("ctl.stepper")
            Picker("Segment", selection: $model.segment) {
                Text("One").tag(0)
                Text("Two").tag(1)
                Text("Three").tag(2)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("ctl.segmented")
            DatePicker("Compact", selection: $model.compactDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .accessibilityIdentifier("ctl.date.compact")
            Menu("Menu") {
                Button("Alpha") { model.choice = "alpha" }
                Button("Beta") { model.choice = "beta" }
                Button("Gamma") { model.choice = "gamma" }
            }
            .accessibilityIdentifier("ctl.menu")
            ColorPicker("Color", selection: Binding(get: { model.color }, set: { model.color = $0; model.colorChanges += 1 }))
                .accessibilityIdentifier("ctl.color")
            DatePicker("Wheel", selection: $model.wheelDate, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .accessibilityIdentifier("ctl.date.wheel")
            ForEach(0..<40, id: \.self) { Text("Filler \($0)").frame(maxWidth: .infinity).padding(.vertical, 10) }
        }
        .padding(.horizontal, 12)
    }
}

/// `-ZTronControlsWheels` (PICKER-s1, open items 37-39): the two wheel pickers first (`DatePicker(.wheel)`, `Picker(.wheel)`),
/// then a slider (the UIKit control the decline must leave alone) and fillers, short enough to sit in a nested inner or a page.
struct WheelsContent: View {
    @ObservedObject var model: UIKitControlsModel

    var body: some View {
        VStack(spacing: 14) {
            DatePicker("Wheel", selection: $model.wheelDate, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .accessibilityIdentifier("ctl.date.wheel")
            Picker("Pick", selection: $model.pick) {
                ForEach(0..<30, id: \.self) { Text("Item \($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 150)
            .clipped()
            .accessibilityIdentifier("ctl.picker.wheel")
            Slider(value: $model.slider).accessibilityIdentifier("ctl.slider")
            ForEach(0..<30, id: \.self) { Text("Filler \($0)").frame(maxWidth: .infinity).padding(.vertical, 10) }
        }
        .padding(.horizontal, 12)
    }
}

private struct NativeOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct NativeOuterOffsetKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// `-ZTronScreen uikitControls`. `-ZTronNativeScroll` swaps the `ZTronScrollView` for SwiftUI's `ScrollView` with the same
/// content: the baseline that tells a failing control from a failing UI test (its offset comes from a preference, `phase=n/a`).
/// PICKER-s1: `-ZTronControlsWheels` shows `WheelsContent`; `-ZTronControlsTopology nested|pager` puts the scroll view in an
/// outer vertical `ZTronScrollView` (an inner 520 pt tall, outer fillers below) or as page 0 of a horizontal paging one (3
/// pages); native: `ScrollView` in `ScrollView`, or page 0 of a paging horizontal `ScrollView` (17+) / `TabView` (15-16).
/// `Info` adds the outer offset (`ox`, `oy`) and the probe's counters (`hit`, `miss`, `decl`); `pickerChain` is the class
/// chain the probe saw from the hit view up to the picker (observed names, DEBUG).
struct UIKitControlsScreen: View {
    private static let args = ProcessInfo.processInfo.arguments
    private static let native = args.contains("-ZTronNativeScroll")
    private static let wheels = args.contains("-ZTronControlsWheels")
    private static let topology: String = {
        if let i = args.firstIndex(of: "-ZTronControlsTopology"), i + 1 < args.count { return args[i + 1] }
        return "plain"
    }()
    @State private var state = ZTronScrollState()
    @State private var outer: ZTronScrollState = {
        let s = ZTronScrollState()
        s.isPagingEnabled = UIKitControlsScreen.topology == "pager"
        return s
    }()
    @StateObject private var model = UIKitControlsModel()
    @State private var info = ""
    @State private var chain = ""
    @State private var nativeY: CGFloat = 0
    @State private var nativeOuter: CGPoint = .zero

    var body: some View {
        VStack(spacing: 6) {
            Button("Info") {
                let y = Self.native ? nativeY : state.contentOffset.y
                let o = Self.native ? nativeOuter : outer.contentOffset
                let c = { (k: String) in ZTronRenderCounters.value(k) }
                info = "phase=\(Self.native ? "n/a" : "\(state.phase.rawValue)") y=\(Int(y.rounded())) "
                    + "ox=\(Int(o.x.rounded())) oy=\(Int(o.y.rounded())) "
                    + "hit=\(c("picker.hit")) miss=\(c("picker.miss")) decl=\(c("picker.declined"))"
                chain = "chain=\(ZTronRenderCounters.notes["picker.chain"] ?? "-") missed=\(ZTronRenderCounters.notes["picker.miss"] ?? "-")"
            }
            .accessibilityIdentifier("Info")
            Text(info).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(info)
            Text(chain).font(.system(size: 7)).lineLimit(2).accessibilityIdentifier("pickerChain").accessibilityValue(chain)
            Text(model.readout).font(.system(size: 9, design: .monospaced)).lineLimit(2)
                .accessibilityIdentifier("values").accessibilityValue(model.readout)
            if Self.topology != "plain" {
                GeometryReader { g in topologyView(page: g.size) }
                    .frame(maxHeight: .infinity)
                    .border(Color.gray)
            } else if Self.native {
                ScrollView(.vertical) {
                    UIKitControlsContent(model: model)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: NativeOffsetKey.self, value: -g.frame(in: .named("nativeScroll")).minY)
                        })
                }
                .coordinateSpace(name: "nativeScroll")
                .onPreferenceChange(NativeOffsetKey.self) { nativeY = $0 }
                .frame(maxHeight: .infinity)
                .border(Color.gray)
            } else {
                ZTronScrollView(.vertical, state: state) { content }
                    .frame(maxHeight: .infinity)
                    .border(Color.gray)
            }
        }
        .padding(8)
    }

    @ViewBuilder private var content: some View {
        if Self.wheels { WheelsContent(model: model) } else { UIKitControlsContent(model: model) }
    }

    private func outerFillers(_ n: Int) -> some View {
        ForEach(0..<n, id: \.self) { Text("Outer \($0)").frame(maxWidth: .infinity).padding(.vertical, 10) }
    }

    /// The controls' scroll view inside an outer one (`nested`) or as page 0 of a pager (`pager`), ZTron or native.
    @ViewBuilder private func topologyView(page: CGSize) -> some View {
        let innerHeight = min(520, page.height)
        if Self.native {
            if Self.topology == "nested" {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        nativeInner.frame(height: innerHeight)
                        outerFillers(30)
                    }
                    .background(GeometryReader { g in
                        Color.clear.preference(key: NativeOuterOffsetKey.self, value: CGPoint(x: 0, y: -g.frame(in: .named("nativeOuter")).minY))
                    })
                }
                .coordinateSpace(name: "nativeOuter")
                .onPreferenceChange(NativeOuterOffsetKey.self) { nativeOuter = $0 }
            } else {
                nativePager(page: page)
            }
        } else if Self.topology == "nested" {
            ZTronScrollView(.vertical, state: outer) {
                VStack(spacing: 0) {
                    ZTronScrollView(.vertical, state: state) { content }.frame(height: innerHeight)
                    outerFillers(30)
                }
            }
        } else {
            ZTronScrollView(.horizontal, state: outer) {
                HStack(spacing: 0) {
                    ZTronScrollView(.vertical, state: state) { content }.frame(width: page.width, height: page.height)
                    ForEach(1..<3, id: \.self) { _ in
                        ZTronScrollView(.vertical) { VStack { outerFillers(30) } }.frame(width: page.width, height: page.height)
                    }
                }
            }
        }
    }

    private var nativeInner: some View {
        ScrollView(.vertical) {
            content.background(GeometryReader { g in
                Color.clear.preference(key: NativeOffsetKey.self, value: -g.frame(in: .named("nativeScroll")).minY)
            })
        }
        .coordinateSpace(name: "nativeScroll")
        .onPreferenceChange(NativeOffsetKey.self) { nativeY = $0 }
    }

    /// Native pager: the page index is the outer offset (`ox` = index × page width).
    @ViewBuilder private func nativePager(page: CGSize) -> some View {
        if #available(iOS 17, *) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    nativeInner.frame(width: page.width, height: page.height)
                    ForEach(1..<3, id: \.self) { _ in
                        ScrollView(.vertical) { VStack { outerFillers(30) } }.frame(width: page.width, height: page.height)
                    }
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: NativeOuterOffsetKey.self, value: CGPoint(x: -g.frame(in: .named("nativeOuter")).minX, y: 0))
                })
            }
            .coordinateSpace(name: "nativeOuter")
            .scrollTargetBehavior(.paging)
            .onPreferenceChange(NativeOuterOffsetKey.self) { nativeOuter = $0 }
        } else {
            TabView {
                nativeInner.tag(0)
                ForEach(1..<3, id: \.self) { i in ScrollView(.vertical) { VStack { outerFillers(30) } }.tag(i) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
}
