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

/// `-ZTronControlsWrap <offset|scale|rotation|opacity|compositing|native>` (the focus tests, `docs/progress/DBG-s3b.md`):
/// `scale` and `rotation` put an identity effect around the scroll view, which on iOS 17.5 makes SwiftUI interpolate the
/// keyboard avoidance (the resize watch then reports `.animating`); `native` swaps in a `ScrollView` as the reference.
struct ControlsScreen: View {
    @State private var state = ZTronScrollState()
    @State private var stateInfo = ""
    @State private var tall = false

    private var wrap: String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-ZTronControlsWrap"), i + 1 < a.count { return a[i + 1] }
        return "none"
    }

    @ViewBuilder private var scroller: some View {
        let scrollView = ZTronScrollView(.vertical, state: state) { ControlsContent() }
        switch wrap {
        case "offset": scrollView.offset(x: 0, y: 0)
        case "scale": scrollView.scaleEffect(1)
        case "rotation": scrollView.rotationEffect(.zero)
        case "opacity": scrollView.opacity(1)
        case "compositing": scrollView.compositingGroup()
        case "native": ScrollView { ControlsContent() }
        default: scrollView
        }
    }

    /// How many editing sessions of text inputs began and ended (DEBUG counters of the library): a focused field that is dismissed
    /// ends its session, so `/0` after a scroll means the keyboard was never taken away, even for an instant.
    private var editSessions: String {
        #if DEBUG
        " edit=\(ZTronRenderCounters.value("editing.begin"))/\(ZTronRenderCounters.value("editing.end"))"
        #else
        ""
        #endif
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Info") { stateInfo = "phase=\(state.phase.rawValue) y=\(Int(state.contentOffset.y))\(editSessions)" }
                    .accessibilityIdentifier("Info")
                // An animated scroll (phase `.animating`) and a slow resize (4 s, the content stays put and locked).
                Button("Animate") { state.setContentOffset(CGPoint(x: 0, y: 120), animated: true) }
                    .accessibilityIdentifier("Animate")
                Button("Resize") { withAnimation(.linear(duration: 4)) { tall.toggle() } }
                    .accessibilityIdentifier("Resize")
            }
            scroller
                .frame(height: tall ? 460 : 360)
                .border(Color.gray)
            Text(stateInfo).font(.caption2).accessibilityIdentifier("stateInfo").accessibilityValue(stateInfo)
        }
        .padding(8)
    }
}
