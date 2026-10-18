import SwiftUI
import ZTronScrollView

/// S12 checklist content: Toggle, Slider, TextField, Button inside the scroll view.
struct ControlsContent: View {
    @State private var on = false
    @State private var value = 0.2
    @State private var text = ""
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 16) {
            Toggle("Switch", isOn: $on).accessibilityIdentifier("ctl.toggle")
            Slider(value: $value, in: 0...1).accessibilityIdentifier("ctl.slider")
            TextField("Text", text: $text).textFieldStyle(.roundedBorder).accessibilityIdentifier("ctl.text")
            Button("Taps: \(taps)") { taps += 1 }.accessibilityIdentifier("ctl.button")
            ForEach(0..<40, id: \.self) { Text("Filler \($0)").frame(maxWidth: .infinity).padding(.vertical, 10) }
        }
        .padding(.horizontal, 12)
    }
}

struct ControlsScreen: View {
    @State private var state = ZTronScrollState()
    @State private var stateInfo = ""

    var body: some View {
        VStack(spacing: 6) {
            Button("Info") { stateInfo = "phase=\(state.phase.rawValue) y=\(Int(state.contentOffset.y))" }
                .accessibilityIdentifier("Info")
            ZTronScrollView(.vertical, state: state) { ControlsContent() }
                .frame(height: 360)
                .border(Color.gray)
            Text(stateInfo).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(stateInfo)
        }
        .padding(8)
    }
}
