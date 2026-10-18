import SwiftUI

/// Where a scroll view is in its interaction lifecycle (mirrors `ScrollPhase`, SPEC S11).
/// M2 only produces `idle` and `animating`; the gesture phases are written by M3.
public enum ZTronScrollPhase: Int, Sendable, Equatable, CaseIterable {
    case idle, tracking, interacting, decelerating, animating
}

/// UIScrollViewDelegate twin (SPEC S11). M2 subset: the callbacks the state can fire without gestures. All optional.
@MainActor
public protocol ZTronScrollViewDelegate: AnyObject {
    /// Fires at most once per frame / batch whenever the presentation offset or zoom changed (all sources).
    func scrollViewDidScroll(_ state: ZTronScrollState)
    /// Fires when a programmatic animation (clock-driven or transaction-driven) finished.
    func scrollViewDidEndScrollingAnimation(_ state: ZTronScrollState)
}

public extension ZTronScrollViewDelegate {
    func scrollViewDidScroll(_ state: ZTronScrollState) {}
    func scrollViewDidEndScrollingAnimation(_ state: ZTronScrollState) {}
}

/// Rarely-changing layout facts. One cold value: viewport size, unscaled content size, insets, display scale.
struct ScrollMetrics: Equatable, Sendable {
    var viewportSize: CGSize = .zero
    var contentSize: CGSize = .zero
    var contentInsets: EdgeInsets = EdgeInsets()
    var displayScale: CGFloat = 1
}

/// The observation granularity on the fallback path: one `ObservableObject` per channel.
enum StateChannel: Int, CaseIterable, Sendable, Hashable {
    case offset, zoom, metrics, phase
}

/// Plain (never observed) mailbox the transform effect writes each interpolated frame (design §6).
@MainActor
final class PresentationBox {
    var pending: (offset: CGPoint, zoom: CGFloat)?
    var frames = 0

    func record(_ offset: CGPoint, _ zoom: CGFloat) {
        pending = (offset, zoom)
        frames += 1
    }
}

#if DEBUG
/// DEBUG-only render counters (design §10). Plain dictionary, never observed; compiled out in release.
@MainActor
public enum ZTronRenderCounters {
    private static var counts: [String: Int] = [:]
    public static func increment(_ key: String) { counts[key, default: 0] += 1 }
    public static func value(_ key: String) -> Int { counts[key] ?? 0 }
    public static func reset() { counts.removeAll() }
    public static var snapshot: [String: Int] { counts }
}
#endif

extension View {
    /// `onChange(of:)` on iOS 15 (single value) and 17 (old/new form) with one signature.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform: @escaping (V) -> Void) -> some View {
        if #available(iOS 17, *) {
            onChange(of: value) { _, new in perform(new) }
        } else {
            onChange(of: value, perform: perform)
        }
    }
}
