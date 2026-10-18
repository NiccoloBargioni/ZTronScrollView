import SwiftUI
import ScrollArbitration

enum GestureMode {
    case simultaneous, plain, highPriority
    static let current: GestureMode = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-gestureMode"), i + 1 < args.count else { return .simultaneous }
        switch args[i + 1] { case "gesture": return .plain; case "high": return .highPriority; default: return .simultaneous }
    }()
}

extension View {
    /// Attaches `gesture` with the arbitration name on iOS 18+ and without it below.
    @ViewBuilder func spikeGesture<G: Gesture>(_ gesture: G) -> some View {
        if #available(iOS 18, *) {
            switch GestureMode.current {
            case .simultaneous: self.simultaneousGesture(gesture, name: scrollArbitrationGestureName)
            case .plain: self.gesture(gesture, name: scrollArbitrationGestureName)
            case .highPriority: self.highPriorityGesture(gesture, name: scrollArbitrationGestureName)
            }
        } else {
            switch GestureMode.current {
            case .simultaneous: self.simultaneousGesture(gesture)
            case .plain: self.gesture(gesture)
            case .highPriority: self.highPriorityGesture(gesture)
            }
        }
    }

    @ViewBuilder func onValueChange<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17, *) { self.onChange(of: value) { _, new in action(new) } }
        else { self.onChange(of: value, perform: action) }
    }
}

struct StandInPage: View {
    let index: Int
    let arbiter: ReferenceScrollArbiter
    let recorder: SequenceRecorder
    @Environment(\.scrollArbiter) private var envArbiter
    @StateObject private var model = StandInModel()
    @State private var committed = CGSize.zero
    @State private var dragging = CGSize.zero
    @State private var scale: CGFloat = 1
    @State private var pinching: CGFloat = 1
    @State private var taps = 0
    @GestureState private var panTouching = false

    private var space: CoordinateSpace { CoordinateSpace.named(arbiter.coordinateSpaceName) }
    private var boxX: CGFloat { committed.width + dragging.width }
    private var boxY: CGFloat { committed.height + dragging.height }

    var body: some View {
        let id = "page.\(index)"
        VStack(spacing: 16) {
            Toggle("canFollow", isOn: $model.canFollowValue).accessibilityIdentifier("\(id).canFollow")
            Toggle("participant moving", isOn: $model.moving).accessibilityIdentifier("\(id).moving")
            Text("page \(index)").font(.headline)
            Rectangle().fill(Color.blue.opacity(0.6)).frame(width: 120, height: 120)
                .scaleEffect(scale * pinching)
                .offset(x: boxX, y: boxY)
                .accessibilityElement()
                .accessibilityIdentifier("\(id).box")
                .accessibilityValue(Text(String(format: "%.0f,%.0f,%.2f", boxX, boxY, scale * pinching)))
            Button("Tap") { taps += 1; recorder.buttonTapped() }
                .buttonStyle(.bordered).accessibilityIdentifier("\(id).button")
            Text("\(taps)").accessibilityIdentifier("\(id).buttonCount").accessibilityLabel("\(taps)")
            Spacer()
        }
        .padding(.top, 8)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(frameReader)
        .modifier(ObserverAttachment(model: model, arbiter: arbiter, recorder: recorder, space: space))
        .spikeGesture(pan)
        .modifier(PinchAttachment(scale: $scale, pinching: $pinching))
        .ignoresSafeArea()
        .coordinateSpace(name: arbiter.coordinateSpaceName)
        .accessibilityIdentifier(id)
        .onValueChange(of: panTouching) { if !$0 { recorder.panEndedSwiftUI(); model.panOwner = nil } }
        .onDisappear { if let t = model.token { envArbiter?.unregister(t); model.token = nil } }
    }

    private var frameReader: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: space)
            Color.clear
                .onAppear {
                    if model.token == nil { model.token = envArbiter?.register(model, frame: frame) }
                }
                .onValueChange(of: frame) { f in if let t = model.token { envArbiter?.update(t, frame: f) } }
        }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: space)
            .updating($panTouching) { _, state, _ in state = true }
            .onChanged { value in
                if model.panOwner == nil {
                    recorder.panStartedSwiftUI()
                    recorder.swiftuiStart(value.startLocation, fromPan: true)
                    if let token = model.token, let envArbiter {
                        model.panOwner = envArbiter.owner(ofDragFrom: value.startLocation, translation: value.translation,
                                                          touchCount: max(1, model.observerCount), participant: token)
                    } else { model.panOwner = .container }
                    recorder.onChange?()
                }
                if model.panOwner == .participant {
                    dragging = value.translation
                    recorder.boxMoved()
                }
            }
            .onEnded { value in
                if model.panOwner == .participant {
                    committed = CGSize(width: committed.width + value.translation.width,
                                       height: committed.height + value.translation.height)
                }
                dragging = .zero
                model.panOwner = nil
            }
    }
}

/// Always-on touch observer: `SpatialEventGesture` on 18+, `DragGesture(minimumDistance: 0)` below.
private struct ObserverAttachment: ViewModifier {
    let model: StandInModel
    let arbiter: ReferenceScrollArbiter
    let recorder: SequenceRecorder
    let space: CoordinateSpace
    @GestureState private var touching = false

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.spikeGesture(
                SpatialEventGesture(coordinateSpace: .named(arbiter.coordinateSpaceName))
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { events in
                        let active = events.filter { $0.phase == .active }
                        model.observerCount = active.count
                        if !model.sequenceBegun, let first = active.first {
                            model.sequenceBegun = true
                            recorder.observerStarted()
                            recorder.swiftuiStart(first.location, fromPan: false)
                            arbiter.beginSequence()
                        }
                    }
                    .onEnded { _ in finish() }
            )
            .onValueChange(of: touching) { if !$0 { finish() } }
        } else {
            content.spikeGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: space)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        model.observerCount = 1
                        if !model.sequenceBegun {
                            model.sequenceBegun = true
                            recorder.observerStarted()
                            recorder.swiftuiStart(value.startLocation, fromPan: false)
                            arbiter.beginSequence()
                        }
                    }
                    .onEnded { _ in finish() }
            )
            .onValueChange(of: touching) { if !$0 { finish() } }
        }
    }

    @MainActor private func finish() {
        guard model.sequenceBegun else { return }
        model.sequenceBegun = false
        model.observerCount = 0
        recorder.observerEnded()
        arbiter.endSequence()
    }
}

private struct PinchAttachment: ViewModifier {
    @Binding var scale: CGFloat
    @Binding var pinching: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.spikeGesture(
                MagnifyGesture()
                    .onChanged { pinching = $0.magnification }
                    .onEnded { scale *= $0.magnification; pinching = 1 })
        } else {
            content.spikeGesture(
                MagnificationGesture()
                    .onChanged { pinching = $0 }
                    .onEnded { scale *= $0; pinching = 1 })
        }
    }
}
