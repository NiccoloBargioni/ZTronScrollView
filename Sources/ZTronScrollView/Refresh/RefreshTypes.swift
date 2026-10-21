import SwiftUI

/// What a refresh indicator is told (SPEC S9, design M8b §1.2). One value per edge; the indicator never owns the
/// refresh: writes to `mode` from a custom view map to begin / end, everything else is read-only.
public struct ZTronRefreshState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case notRefreshing, pulling, refreshing
    }

    public var mode: Mode
    /// The same value as `mode`, written inside an animation transaction (`resetAnimation`, else `.default`).
    public var modeAnimated: Mode
    /// Pull ÷ trigger distance, clamped to 0…1; stays 1 while `.refreshing`. After a release (or when a refresh ends) the
    /// indicator goes back with the content: `mode` is `.notRefreshing` and `dragPosition` follows the pull down to 0.
    public var dragPosition: CGFloat
    public var style: ZTronRefreshStyle
    public var edge: Edge

    public init(mode: Mode = .notRefreshing, modeAnimated: Mode? = nil, dragPosition: CGFloat = 0,
                style: ZTronRefreshStyle = .default, edge: Edge = .top) {
        self.mode = mode
        self.modeAnimated = modeAnimated ?? mode
        self.dragPosition = dragPosition
        self.style = style
        self.edge = edge
    }
}

/// `.system` looks and moves like `UIRefreshControl`; `.default` lets the indicator follow the pull with its own,
/// more flexible animation.
public enum ZTronRefreshStyle: Equatable, Sendable {
    case system, `default`
}

/// When the action starts: `.whilePulling` as the pull crosses the trigger distance (the finger still down, like
/// `UIRefreshControl`), `.onRelease` only when the finger lifts at or past it.
public enum ZTronRefreshTriggerMode: Equatable, Sendable {
    case whilePulling, onRelease
}

/// Tunables of one refresher. The defaults are `UIRefreshControl`-calibrated placeholders (design M8b §4 R1).
public struct ZTronRefreshConfiguration: Equatable {
    /// Pull (points of displayed overscroll) at which `dragPosition` reaches 1 and the action fires.
    public var triggerDistance: CGFloat
    /// Height of the built-in indicator.
    public var indicatorHeight: CGFloat
    /// Inset the refreshing edge keeps open for the indicator; `nil` = `indicatorHeight`.
    public var holdOffset: CGFloat?
    public var triggerMode: ZTronRefreshTriggerMode
    /// The indicator stays at least this long once the hold is applied, however fast the action returns.
    public var minimumVisibleTime: TimeInterval
    /// How the hold clears; `nil` = unanimated.
    public var resetAnimation: ZTronScrollAnimation?
    /// Edges this refresher answers; `nil` = the start edge of the primary axis (`.top`, `.leading` when horizontal-only).
    public var allowedEdges: Edge.Set?
    /// Extra content padding at the end edge while a bottom / trailing refresh is active (load more).
    public var loadMorePadding: CGFloat
    /// No pull while the zoom scale is above its minimum.
    public var disablesWhenZoomed: Bool

    public init(triggerDistance: CGFloat = 100, indicatorHeight: CGFloat = 60, holdOffset: CGFloat? = nil,
                triggerMode: ZTronRefreshTriggerMode = .whilePulling, minimumVisibleTime: TimeInterval = 0.5,
                resetAnimation: ZTronScrollAnimation? = .swiftUI(.easeOut(duration: 0.3)),
                allowedEdges: Edge.Set? = nil, loadMorePadding: CGFloat = 0, disablesWhenZoomed: Bool = true) {
        self.triggerDistance = triggerDistance
        self.indicatorHeight = indicatorHeight
        self.holdOffset = holdOffset
        self.triggerMode = triggerMode
        self.minimumVisibleTime = minimumVisibleTime
        self.resetAnimation = resetAnimation
        self.allowedEdges = allowedEdges
        self.loadMorePadding = loadMorePadding
        self.disablesWhenZoomed = disablesWhenZoomed
    }

    public static var `default`: ZTronRefreshConfiguration { ZTronRefreshConfiguration() }
    /// Bottom pull = load more, with 44 pt of end padding while it loads.
    public static var loadMore: ZTronRefreshConfiguration {
        ZTronRefreshConfiguration(allowedEdges: [.bottom], loadMorePadding: 44)
    }
}
