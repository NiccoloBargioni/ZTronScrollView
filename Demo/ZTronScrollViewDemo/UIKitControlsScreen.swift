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

    var readout: String {
        "stepper=\(steps) segment=\(segment) compact=\(Self.dayFormat.string(from: compactDate)) "
            + "wheel=\(Self.dayFormat.string(from: wheelDate)) menu=\(choice) colorChanges=\(colorChanges) color=\(colorHex)"
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

private struct NativeOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// `-ZTronScreen uikitControls`. `-ZTronNativeScroll` swaps the `ZTronScrollView` for SwiftUI's `ScrollView` with the same
/// content: the baseline that tells a failing control from a failing UI test (its offset comes from a preference, `phase=n/a`).
struct UIKitControlsScreen: View {
    private static let native = ProcessInfo.processInfo.arguments.contains("-ZTronNativeScroll")
    @State private var state = ZTronScrollState()
    @StateObject private var model = UIKitControlsModel()
    @State private var info = ""
    @State private var nativeY: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            Button("Info") {
                let y = Self.native ? nativeY : state.contentOffset.y
                info = "phase=\(Self.native ? "n/a" : "\(state.phase.rawValue)") y=\(Int(y.rounded()))"
            }
            .accessibilityIdentifier("Info")
            Text(info).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(info)
            Text(model.readout).font(.system(size: 9, design: .monospaced)).lineLimit(2)
                .accessibilityIdentifier("values").accessibilityValue(model.readout)
            if Self.native {
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
                ZTronScrollView(.vertical, state: state) { UIKitControlsContent(model: model) }
                    .frame(maxHeight: .infinity)
                    .border(Color.gray)
            }
        }
        .padding(8)
    }
}
