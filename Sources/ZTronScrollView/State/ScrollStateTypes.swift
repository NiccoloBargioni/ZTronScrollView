import SwiftUI

/// Where a scroll view is in its interaction lifecycle (mirrors `ScrollPhase`, SPEC S11).
/// `tracking` (finger down), `interacting` (dragging), `decelerating` (finger-free release motion), `animating` (programmatic).
public enum ZTronScrollPhase: Int, Sendable, Equatable, CaseIterable {
    case idle, tracking, interacting, decelerating, animating
}

/// `UIScrollView.DecelerationRate` twin (`.normal` 0.998, `.fast` 0.99 per ms).
public enum ZTronDecelerationRate: Sendable, Equatable {
    case normal, fast
}

/// A zoom limit: an absolute scale, or relative to the content's fit / fill scale (recomputed on resize).
public enum ZTronZoomScale: Equatable, Sendable {
    case absolute(CGFloat), fit, fill
}

/// UIScrollViewDelegate twin (SPEC S11), complete list; every method is optional. Call order matches UIKit:
/// willBeginDragging -> didScroll... -> willEndDragging -> didEndDragging(willDecelerate:) ->
/// [willBeginDecelerating -> didScroll... -> didEndDecelerating]. `didScroll` fires at most once per frame / batch.
@MainActor
public protocol ZTronScrollViewDelegate: AnyObject {
    func scrollViewDidScroll(_ state: ZTronScrollState)
    func scrollViewWillBeginDragging(_ state: ZTronScrollState)
    /// `velocity` in pt/ms (UIKit). `targetContentOffset` may be changed; the release motion lands on it.
    func scrollViewWillEndDragging(_ state: ZTronScrollState, withVelocity velocity: CGPoint,
                                   targetContentOffset: inout CGPoint)
    func scrollViewDidEndDragging(_ state: ZTronScrollState, willDecelerate decelerate: Bool)
    func scrollViewWillBeginDecelerating(_ state: ZTronScrollState)
    func scrollViewDidEndDecelerating(_ state: ZTronScrollState)
    /// A programmatic animation (clock-driven or transaction-driven) finished.
    func scrollViewDidEndScrollingAnimation(_ state: ZTronScrollState)
    func scrollViewWillBeginZooming(_ state: ZTronScrollState)
    func scrollViewDidZoom(_ state: ZTronScrollState)
    func scrollViewDidEndZooming(_ state: ZTronScrollState, atScale scale: CGFloat)
    func scrollViewShouldScrollToTop(_ state: ZTronScrollState) -> Bool
    func scrollViewDidScrollToTop(_ state: ZTronScrollState)
    func scrollViewDidChangeAdjustedContentInset(_ state: ZTronScrollState)
}

public extension ZTronScrollViewDelegate {
    func scrollViewDidScroll(_ state: ZTronScrollState) {}
    func scrollViewWillBeginDragging(_ state: ZTronScrollState) {}
    func scrollViewWillEndDragging(_ state: ZTronScrollState, withVelocity velocity: CGPoint,
                                   targetContentOffset: inout CGPoint) {}
    func scrollViewDidEndDragging(_ state: ZTronScrollState, willDecelerate decelerate: Bool) {}
    func scrollViewWillBeginDecelerating(_ state: ZTronScrollState) {}
    func scrollViewDidEndDecelerating(_ state: ZTronScrollState) {}
    func scrollViewDidEndScrollingAnimation(_ state: ZTronScrollState) {}
    func scrollViewWillBeginZooming(_ state: ZTronScrollState) {}
    func scrollViewDidZoom(_ state: ZTronScrollState) {}
    func scrollViewDidEndZooming(_ state: ZTronScrollState, atScale scale: CGFloat) {}
    func scrollViewShouldScrollToTop(_ state: ZTronScrollState) -> Bool { true }
    func scrollViewDidScrollToTop(_ state: ZTronScrollState) {}
    func scrollViewDidChangeAdjustedContentInset(_ state: ZTronScrollState) {}
}

/// Rarely-changing layout facts. One cold value: viewport size, unscaled content size, insets, display scale.
struct ScrollMetrics: Equatable, Sendable {
    var viewportSize: CGSize = .zero
    var contentSize: CGSize = .zero
    /// Developer inset (`state.contentInset`).
    var contentInset: EdgeInsets = EdgeInsets()
    /// Observed safe area of the container (bars, keyboard), unmasked.
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    /// `contentInset` + the safe area on the adjusted edges (SPEC S6); derived by the state.
    var adjustedContentInset: EdgeInsets = EdgeInsets()
    /// Scaling-header height (M8b hook): shifts the unobscured center only, never the bounds.
    var headerObscured: CGFloat = 0
    var displayScale: CGFloat = 1
    /// Bumps per resize commit; the pan coordinator rebases its baseline when it changes.
    var resizeGeneration: UInt64 = 0
    /// The resize commit the transform effect maps through (design M5 section 2).
    var resize = ResizeCommit()
}

/// Which edges of the safe area become `adjustedContentInset` (UIKit `contentInsetAdjustmentBehavior`).
/// `.automatic` (= `.scrollableAxes`) adjusts on the edges of the scrollable axes, as a native ScrollView does.
public enum ZTronContentInsetAdjustmentBehavior: Sendable, Equatable {
    case automatic, scrollableAxes, never, always

    func edges(for axes: Axis.Set) -> Edge.Set {
        switch self {
        case .never: return []
        case .always: return .all
        case .automatic, .scrollableAxes:
            var e: Edge.Set = []
            if axes.contains(.vertical) { e.formUnion(.vertical) }
            if axes.contains(.horizontal) { e.formUnion(.horizontal) }
            return e
        }
    }
}

/// Registry of scroll targets (`ztronScrollID`, M6) the resize reflow rule asks for the item nearest to the visible
/// center. M5 ships the protocol; with no registry the anchor is the plain content point.
@MainActor
protocol ScrollTargetRegistry: AnyObject {
    func nearestTarget(to point: CGPoint) -> (id: AnyHashable, frame: CGRect)?
    func frame(of id: AnyHashable) -> CGRect?
}

/// The observation granularity on the fallback path: one `ObservableObject` per channel.
enum StateChannel: Int, CaseIterable, Sendable, Hashable {
    case offset, zoom, metrics, phase
    /// Target offset/zoom only (presentation writes never publish it): the transform host's wake-up channel.
    case target
}

/// Plain (never observed) mailbox the transform effect writes each interpolated frame (design §6). Lock-protected:
/// `GeometryEffect.effectValue` is not main-actor isolated, so `record` must be callable from any thread.
final class PresentationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _pending: (offset: CGPoint, zoom: CGFloat, size: CGSize)?
    private var _frames = 0

    var pending: (offset: CGPoint, zoom: CGFloat, size: CGSize)? {
        get { lock.lock(); defer { lock.unlock() }; return _pending }
        set { lock.lock(); defer { lock.unlock() }; _pending = newValue }
    }
    var frames: Int { lock.lock(); defer { lock.unlock() }; return _frames }

    func record(_ offset: CGPoint, _ zoom: CGFloat, size: CGSize = .zero) {
        lock.lock(); defer { lock.unlock() }
        _pending = (offset, zoom, size)
        _frames += 1
    }
}

#if DEBUG
/// DEBUG-only render counters (design §10). Plain dictionary, never observed; compiled out in release.
@MainActor
public enum ZTronRenderCounters {
    private static var counts: [String: Int] = [:]
    public static func increment(_ key: String) { counts[key, default: 0] += 1 }
    public static func value(_ key: String) -> Int { counts[key] ?? 0 }
    public static func reset() { counts.removeAll(); notes.removeAll() }
    public static var snapshot: [String: Int] { counts }
    /// Free-form DEBUG notes (e.g. the frame that incremented `resize.jumpFrames`); cleared by `reset()`.
    public static var notes: [String: String] = [:]
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
