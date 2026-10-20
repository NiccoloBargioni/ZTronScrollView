import SwiftUI

extension View {
    /// `onScrollVisibilityChange(threshold:_:)` for views inside a ``ZTronScrollView`` on iOS 15+: `action(true)` when at
    /// least `threshold` of the view's area is inside the visible rect, `action(false)` when it drops below it (`threshold`
    /// 0 means any visible area). The first evaluation reports the current state once. Runs cold inside the scroll
    /// state's delivery (no view update while scrolling or zooming); the frame is the one layout reports, never read
    /// per frame. Outside a `ZTronScrollView` it applies SwiftUI's modifier on iOS 18 and does nothing before.
    public func onZTronScrollVisibilityChange(threshold: Double = 0.5, _ action: @escaping (Bool) -> Void) -> some View {
        modifier(ScrollVisibilityModifier(threshold: threshold, action: action))
    }
}

struct ScrollVisibilityModifier: ViewModifier {
    let threshold: Double
    let action: (Bool) -> Void
    @Environment(\.ztronScrollState) private var state
    @State private var box = VisibilityObserverBox()

    @ViewBuilder
    func body(content: Content) -> some View {
        if let state {
            // R7: the closures are re-assigned on every evaluation, never captured once.
            let _ = assign()
            content
                .background(VisibilityFrameReporter(box: box, useGeometryChange: state.usesGeometryChange))
                .onAppear { register(in: state) }
                .onDisappear { unregister(from: state) }
        } else if #available(iOS 18, *) {
            content.onScrollVisibilityChange(threshold: threshold, action)
        } else {
            content
        }
    }

    private func assign() {
        box.threshold = threshold
        box.action = action
    }

    private func register(in state: ZTronScrollState) {
        guard box.token == nil else { return }
        box.token = box.add(to: state.observers)
        state.deliverObservers()
    }

    private func unregister(from state: ZTronScrollState) {
        guard let token = box.token else { return }
        state.observers.remove(token)
        box.token = nil
    }
}

private struct VisibilityFrameKey: PreferenceKey {
    static let defaultValue = CGRect.null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// Reports the view's frame in the unscaled content space to the box: `onGeometryChange` where available, a background
/// `GeometryReader` with a preference on the fallback path (same pair as the `ztronScrollID` reporter; the branch is a
/// `let` flag of the state, R6).
struct VisibilityFrameReporter: View {
    let box: VisibilityObserverBox
    let useGeometryChange: Bool

    var body: some View {
        if useGeometryChange, #available(iOS 16, *) {
            Color.clear
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: ZTronCoordinateSpaces.content) },
                                  action: { box.setFrame($0) })
        } else {
            GeometryReader { proxy in
                Color.clear.preference(key: VisibilityFrameKey.self, value: proxy.frame(in: ZTronCoordinateSpaces.content))
            }
            .onPreferenceChange(VisibilityFrameKey.self) { if !$0.isNull { box.setFrame($0) } }
        }
    }
}
