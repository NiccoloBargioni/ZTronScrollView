import SwiftUI
import ZTronScrollPhysics

/// Twin of SwiftUI's `ScrollBounceBehavior` (16.4); SwiftUI's own value cannot be read back without reflection, so
/// the library carries its own (see BounceBehavior's note).
public enum ZTronScrollBounceBehavior: Sendable, Equatable {
    case automatic, always, basedOnSize

    var physics: BounceBehavior {
        switch self {
        case .automatic: return .automatic
        case .always: return .always
        case .basedOnSize: return .basedOnSize
        }
    }
}

private struct ScrollEnabledKey: EnvironmentKey { static let defaultValue = true }
private struct BounceXKey: EnvironmentKey { static let defaultValue = ZTronScrollBounceBehavior.automatic }
private struct BounceYKey: EnvironmentKey { static let defaultValue = ZTronScrollBounceBehavior.automatic }

struct DoubleTapZoom: Equatable {
    var scale: ZTronZoomScale?
}
private struct DoubleTapKey: EnvironmentKey { static let defaultValue: DoubleTapZoom? = nil }
private struct ZoomLimitsKey: EnvironmentKey { static let defaultValue: ZoomLimits? = nil }

extension EnvironmentValues {
    var ztronDoubleTapZoom: DoubleTapZoom? {
        get { self[DoubleTapKey.self] }
        set { self[DoubleTapKey.self] = newValue }
    }
    var ztronZoomLimits: ZoomLimits? {
        get { self[ZoomLimitsKey.self] }
        set { self[ZoomLimitsKey.self] = newValue }
    }
    var ztronScrollIsEnabled: Bool {
        get { self[ScrollEnabledKey.self] }
        set { self[ScrollEnabledKey.self] = newValue }
    }
    var ztronHorizontalBounce: ZTronScrollBounceBehavior {
        get { self[BounceXKey.self] }
        set { self[BounceXKey.self] = newValue }
    }
    var ztronVerticalBounce: ZTronScrollBounceBehavior {
        get { self[BounceYKey.self] }
        set { self[BounceYKey.self] = newValue }
    }
}

extension ZTronZoomScale {
    var bound: ZoomBound {
        switch self {
        case let .absolute(v): return .absolute(v)
        case .fit: return .fit
        case .fill: return .fill
        }
    }
}

extension View {
    /// Environment twin of `ZTronScrollView.zoomRange(min:max:)` (the member wins when both are set).
    public func ztronScrollZoomRange(min: ZTronZoomScale, max: ZTronZoomScale) -> some View {
        environment(\.ztronZoomLimits, ZoomLimits(min: min.bound, max: max.bound))
    }

    /// Environment twin of `ZTronScrollView.doubleTapToZoom(_:scale:)`.
    public func ztronScrollDoubleTapToZoom(_ enabled: Bool = true, scale: ZTronZoomScale? = nil) -> some View {
        environment(\.ztronDoubleTapZoom, enabled ? DoubleTapZoom(scale: scale) : nil)
    }

    /// `scrollDisabled(_:)` for ZTronScrollView on iOS 15+: writes our key and, when available, SwiftUI's.
    @ViewBuilder
    public func ztronScrollDisabled(_ disabled: Bool) -> some View {
        if #available(iOS 16, *) {
            self.environment(\.ztronScrollIsEnabled, !disabled).scrollDisabled(disabled)
        } else {
            self.environment(\.ztronScrollIsEnabled, !disabled)
        }
    }

    /// `scrollBounceBehavior(_:axes:)` for ZTronScrollView on iOS 15+.
    public func ztronScrollBounceBehavior(_ behavior: ZTronScrollBounceBehavior, axes: Axis.Set = [.horizontal, .vertical])
        -> some View {
        transformEnvironment(\.self) { env in
            if axes.contains(.horizontal) { env.ztronHorizontalBounce = behavior }
            if axes.contains(.vertical) { env.ztronVerticalBounce = behavior }
        }
    }
}

/// Reads SwiftUI's `isScrollEnabled` (16+) without making the adapter's availability conditional.
@available(iOS 16, *)
struct NativeScrollEnabledReader: ViewModifier {
    let sink: (Bool) -> Void
    @Environment(\.isScrollEnabled) private var enabled
    func body(content: Content) -> some View {
        sink(enabled)
        return content
    }
}
