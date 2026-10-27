import SwiftUI

// Scaling header (SPEC S10, amendment 2026-10-19; design M8b §2): the public value types. The header is installed with
// `ZTronScrollView.withScalingHeader(size:scalingBehavior:snap:fade:header:)`, precedes the content (its resting height
// is reserved in `adjustedContentInset.top`), collapses by shrinking from the bottom with its top edge pinned and reacts
// to a pull past the top with `.preserve` (no consequence on the header) or `.stretch` (it grows with the pull).

/// How tall the header rests and how far it collapses.
public enum ZTronHeaderSize: Equatable, Sendable {
    /// Resting height `max`, collapses to `min`; no measurement. Labels are mandatory so the bounds cannot be swapped.
    case fixed(min: CGFloat = 0, max: CGFloat)
    /// Resting height = the scroll view's width ÷ `ratio` (width / height, SwiftUI's convention), recomputed when the width
    /// changes (rotation) as a discrete inset change. The right choice for an image banner: `.aspectRatio(16/9)` is what an
    /// `Image` with `.aspectRatio(16/9, contentMode: .fit)` would measure to, without measurement machinery.
    case aspectRatio(CGFloat, min: CGFloat = 0)
    /// Resting height = the header's ideal height at the scroll view's width (measured; height proposed `nil`). Re-measured
    /// on width and Dynamic Type changes and, on iOS 16+, when the header's content changes. Prefer `.fixed` /
    /// `.aspectRatio` when the height is known.
    case fit(min: CGFloat = 0)

    var minimum: CGFloat {
        switch self {
        case let .fixed(min, _), let .aspectRatio(_, min), let .fit(min): return min
        }
    }

    var isFit: Bool { if case .fit = self { return true } else { return false } }
}

/// What the resting height does when it does not fit the scroll view's container: the viewport below the safe area the
/// content adjusts for, `W × H` (e.g. a full-width 16:9 banner in landscape: 874 / (16/9) = 491 pt on a 381 pt tall
/// container, so the content starts below the screen). User decision 2026-10-25 (D59).
public enum ZTronHeaderOverflow: Equatable, Sendable {
    /// The size's own resting height, even when it is taller than the container (the content then starts below it).
    /// The default.
    case uncapped
    /// At most `fraction` (0…1) of the container's height; `min` is limited the same way.
    case capped(fraction: CGFloat)
    /// Refit into the container: `.aspectRatio(r)` becomes the aspect fit of `r` inside `W × H` (height `min(W / r, H)`),
    /// `.fixed` and `.fit` are limited to `H`; `min` is limited the same way.
    case refit
}

/// The reaction to a pull past the top: `.preserve` leaves the header at its resting height (the content pulls away and
/// a gap opens below the header), `.stretch` grows the header from its bottom edge with the (rubber-banded) pull.
public enum ZTronHeaderScalingBehavior: Sendable {
    case preserve, stretch
}

/// Snapping inside the collapse band. Positions are collapse progress: 0 expanded, 1 collapsed (the reference's inverse
/// convention is gone).
public struct ZTronHeaderSnap: Equatable, Sendable {
    enum Mode: Equatable, Sendable { case disabled, immediately, afterFinishAccelerating }
    let mode: Mode
    let positions: [CGFloat]

    /// No snapping (the default).
    public static let disabled = ZTronHeaderSnap(mode: .disabled, positions: [])
    /// The release target is moved to the nearest position (velocity-aware: it works on the projected rest) through the
    /// scroll-target pipeline, after the scroll view's own target behavior; `willEndDragging` sees the snapped target.
    public static func immediately(at positions: [CGFloat] = [0, 1]) -> Self {
        ZTronHeaderSnap(mode: .immediately, positions: positions)
    }
    /// Once the deceleration ends inside the band, the header animates to the nearest position.
    public static func afterFinishAccelerating(at positions: [CGFloat] = [0, 1]) -> Self {
        ZTronHeaderSnap(mode: .afterFinishAccelerating, positions: positions)
    }
}

/// A linear gradient from clear (at `start · height` from the header's top) to `color` (at its bottom edge), drawn over the
/// header inside its live frame and below any refresh indicator.
public struct ZTronHeaderFade: Equatable {
    let color: Color
    let start: CGFloat

    public static func linear(to color: Color, from start: CGFloat = 0.5) -> Self {
        ZTronHeaderFade(color: color, start: start)
    }
}

/// What a header child reads through ``ZTronHeaderGeometryReader`` (or `ZTronScrollGeometry.header`).
public struct ZTronHeaderGeometry: Equatable, Sendable {
    /// 0 expanded … 1 collapsed; 0 when the header cannot collapse.
    public var progress: CGFloat
    /// The live height, stretch included.
    public var height: CGFloat
    /// ≥ 0: how much `.stretch` grew the header past its resting height; always 0 under `.preserve`.
    public var stretch: CGFloat
    public var minHeight: CGFloat
    /// The resolved resting height (the reference's `maxHeight`).
    public var restingHeight: CGFloat
    /// The scroll view's width.
    public var width: CGFloat

    /// What a reader sees before the header resolves or without a header: all zeros.
    static let unresolved = ZTronHeaderGeometry(progress: 0, height: 0, stretch: 0, minHeight: 0, restingHeight: 0, width: 0)

    /// A reader transform that changes only `steps + 1` times over a full collapse: `round(progress · steps)`.
    public static func quantizedProgress(steps: Int) -> (ZTronHeaderGeometry) -> Int {
        { Int(($0.progress * CGFloat(steps)).rounded()) }
    }
}

/// The handle the header builder receives. It exposes no geometry, hot or cold: a child that takes it in its initializer
/// reads the geometry inside a ``ZTronHeaderGeometryReader`` only, so a hot read in the builder's own scope (which would
/// re-run the whole header every frame) cannot be written.
public struct ZTronHeaderProxy: Equatable {
    let state: ZTronScrollState

    public nonisolated static func == (a: Self, b: Self) -> Bool { a.state === b.state }
}

/// `state.snapHeader(to:)` targets. `.progress` and `.height` are clamped to the header's range.
public enum ZTronHeaderSnapTarget: Equatable, Sendable {
    case expanded, collapsed, progress(CGFloat), height(CGFloat)
}

/// The resolved, cold facts of an installed header (`ScrollMetrics.header`). `resting` is reserved in
/// `adjustedContentInset.top`; collapse and stretch never change it.
struct HeaderMetrics: Equatable, Sendable {
    var min: CGFloat
    var resting: CGFloat
    var behavior: ZTronHeaderScalingBehavior
    /// The scroll view's (viewport) width the size was resolved at.
    var width: CGFloat
    /// The vertical offset drives the header (`axes` contain `.vertical`). Off: a fixed banner, except while zoomed content
    /// pans vertically (D15).
    var vertical: Bool = true

    /// The collapse band: how far the header can shrink.
    var band: CGFloat { Swift.max(0, resting - min) }
}
