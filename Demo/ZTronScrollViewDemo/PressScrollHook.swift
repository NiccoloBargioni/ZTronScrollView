import SwiftUI
import ZTronScrollView
#if canImport(UIKit)
import UIKit
#endif

/// D11 narrowing (2026-11-09) harness: `-ZTronScrollOnPress <s>`: `s` seconds after a hooked Button's press begins, the
/// app scrolls the view by `-ZTronScrollOnPressBy <pt>` (default 8; negative pulls past the top) in an animation
/// (`withAnimation` + `scroll(to:)` on a ZTron view, `UIScrollView.setContentOffset(_:animated:)` on the native pan
/// screen, `-ZTronPanNative 1`). The press is still held when the motion starts, so its lift tests whether the press
/// survived the app-animated scroll (native: it does).
@MainActor
enum PressScrollHook {
    static let delay: Double? = ProcessInfo.processInfo.arguments.firstIndex(of: "-ZTronScrollOnPress").flatMap { i in
        i + 1 < ProcessInfo.processInfo.arguments.count ? Double(ProcessInfo.processInfo.arguments[i + 1]) : nil
    }
    static let by: CGFloat = ProcessInfo.processInfo.arguments.firstIndex(of: "-ZTronScrollOnPressBy").flatMap { i in
        i + 1 < ProcessInfo.processInfo.arguments.count ? Double(ProcessInfo.processInfo.arguments[i + 1]).map { CGFloat($0) } : nil
    } ?? 8
    static var isOn: Bool { delay != nil }
    /// The scroll the screen installs (ZTron or native).
    static var scroll: (() -> Void)?
    /// Whether the hooked scroll ran (read by the screens' info lines).
    static var fired = 0
    private static var armed = true

    static func pressBegan() {
        guard let delay, armed else { return }
        armed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { fired += 1; scroll?() }
    }
    static func rearm() { armed = true; fired = 0 }

    /// The ZTron scroll: an app-animated transaction scroll by `by` from where the view is.
    static func ztron(_ state: ZTronScrollState) -> () -> Void {
        { [weak state] in
            guard let state else { return }
            let y = state.contentOffset.y
            withAnimation(.easeInOut(duration: 0.5)) { state.scroll(to: CGPoint(x: state.contentOffset.x, y: y + by)) }
        }
    }

    #if canImport(UIKit)
    /// The native scroll: the first `UIScrollView` under the key window whose content is taller than its bounds.
    static func native() -> () -> Void {
        {
            guard let sv = firstScrollView() else { return }
            sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: sv.contentOffset.y + by), animated: true)
        }
    }
    static func firstScrollView() -> UIScrollView? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let root = scene?.keyWindow ?? scene?.windows.first else { return nil }
        func find(_ v: UIView) -> UIScrollView? {
            if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height + 1 { return s }
            for c in v.subviews { if let s = find(c) { return s } }
            return nil
        }
        return find(root)
    }
    #endif
}

/// A plain-looking style that reports the press's start to `PressScrollHook` (only used under `-ZTronScrollOnPress`).
struct PressHookStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onChangeCompatDemo(of: configuration.isPressed) { if $0 { PressScrollHook.pressBegan() } }
    }
}

extension View {
    /// `onChange(of:)` on every OS the demo runs (the iOS 17 two-argument form, else the iOS 14 one).
    @ViewBuilder func onChangeCompatDemo<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17, *) {
            onChange(of: value) { _, new in action(new) }
        } else {
            onChange(of: value, perform: action)
        }
    }

    /// The hook's style on this Button when `-ZTronScrollOnPress` is given, the default style otherwise.
    @ViewBuilder func pressScrollHooked() -> some View {
        if PressScrollHook.isOn { buttonStyle(PressHookStyle()) } else { self }
    }
}
