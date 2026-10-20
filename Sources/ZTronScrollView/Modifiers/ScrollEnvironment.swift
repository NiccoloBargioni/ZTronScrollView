import SwiftUI
import ZTronScrollPhysics
import ScrollArbitration

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

// MARK: - Nested scroll policy (docs/design/NESTED-arbitration.md §3, resolutions R1–R7)

/// Which side of a nested pair follows a shared drag (the answer of a ``ZTronNestedScrollPolicy/custom(_:)`` policy).
public enum ZTronNestedScrollOwner: Sendable, Hashable {
    /// The inner `ZTronScrollView` (the one the drag started on) pans; its container ignores the sequence.
    case inner
    /// The container pans (pages); the inner ignores the sequence.
    case outer
}

/// What a ``ZTronNestedScrollPolicy/custom(_:)`` policy sees. Built cold inside the decision, in the drag handler,
/// never in a body: `geometry` is a non-tracked snapshot (reading it records no Observation access).
///
/// `fingerDirection` is ScrollArbitration's `FingerDirection` (the frozen 1.0.0 contract, S16); the library does not
/// re-export that module, so a client that names the type (or its cases outside a switch over this value) adds
/// `import ScrollArbitration`. The memberwise initializer is public so clients can unit-test their `.custom` closures.
@MainActor
public struct ZTronNestedScrollContext {
    /// The inner view's geometry at the decision: `contentOffset`, `zoomScale`, `visibleRect`, …
    public let geometry: ZTronScrollGeometry
    /// The inner view's resolved minimum zoom scale.
    public let minimumZoomScale: CGFloat
    /// The finger's direction along the container's paging axis (screen space); `ScrollArbitration.FingerDirection`.
    public let fingerDirection: FingerDirection
    /// What ``ZTronNestedScrollPolicy/innerWhileScrollable`` would answer: the inner can move with the finger on
    /// the paging axis without rubber-banding.
    public let canFollow: Bool

    public init(geometry: ZTronScrollGeometry, minimumZoomScale: CGFloat, fingerDirection: FingerDirection,
                canFollow: Bool) {
        self.geometry = geometry
        self.minimumZoomScale = minimumZoomScale
        self.fingerDirection = fingerDirection
        self.canFollow = canFollow
    }
}

/// How a `ZTronScrollView` yields a drag to the `ZTronScrollView` (or ScrollArbitration container) that holds it.
///
/// Rules 1–4 of the S16 contract (off-axis swipes and pinches stay inside; a moving side keeps its catch) always
/// run; the policy only replaces rule 5, "the inner can follow the finger on the paging axis". Declared on the inner
/// (`ZTronScrollView.nestedScrollPolicy(_:)`) or propagated by the environment (`View.ztronNestedScrollPolicy(_:)`);
/// the member wins. The default is ``automatic``.
public struct ZTronNestedScrollPolicy: Sendable {
    enum Kind: Sendable {
        case innerWhileScrollable, innerWhenZoomed, inner, outer, independent
        case custom(@MainActor @Sendable (ZTronNestedScrollContext) -> ZTronNestedScrollOwner)
    }
    let kind: Kind

    /// ``innerWhileScrollable``: UIScrollView parity.
    public static let automatic = ZTronNestedScrollPolicy(kind: .innerWhileScrollable)
    /// The inner follows while it can scroll in the finger's direction; the container takes the swipe at an edge
    /// (even while zoomed) and when the content fits.
    public static let innerWhileScrollable = ZTronNestedScrollPolicy(kind: .innerWhileScrollable)
    /// The inner follows iff `zoomScale > minimumZoomScale` (it rubber-bands at its edge while zoomed); at the
    /// minimum zoom the container takes every on-axis swipe.
    public static let innerWhenZoomed = ZTronNestedScrollPolicy(kind: .innerWhenZoomed)
    /// The container never takes a drag that starts on this view.
    public static let inner = ZTronNestedScrollPolicy(kind: .inner)
    /// This view never pans a shared on-axis drag (off-axis swipes and pinches stay here).
    public static let outer = ZTronNestedScrollPolicy(kind: .outer)
    /// No arbitration with the nested container (the `ZTronScrollView` that holds this view): both follow the drag,
    /// as standalone scrollers would. An external ScrollArbitration container (a ZTronPages pager) is still joined,
    /// with ``innerWhileScrollable``'s answer.
    public static let independent = ZTronNestedScrollPolicy(kind: .independent)
    /// Decides from a non-tracked ``ZTronNestedScrollContext`` at the swipe's hysteresis.
    public static func custom(_ decide: @escaping @MainActor @Sendable (ZTronNestedScrollContext) -> ZTronNestedScrollOwner)
        -> ZTronNestedScrollPolicy {
        ZTronNestedScrollPolicy(kind: .custom(decide))
    }

    var isIndependent: Bool {
        if case .independent = kind { return true }
        return false
    }

    /// Whether this view registers with `arbiter`: always with an external one; with the nested container of an
    /// outer `ZTronScrollView` unless ``independent``.
    func joins(_ arbiter: any ScrollArbiter) -> Bool {
        !(isIndependent && arbiter is NestedScrollArbiter)
    }
}

private struct NestedScrollPolicyKey: EnvironmentKey { static let defaultValue = ZTronNestedScrollPolicy.automatic }

extension EnvironmentValues {
    var ztronNestedScrollPolicy: ZTronNestedScrollPolicy {
        get { self[NestedScrollPolicyKey.self] }
        set { self[NestedScrollPolicyKey.self] = newValue }
    }
}

extension View {
    /// Environment twin of `ZTronScrollView.nestedScrollPolicy(_:)` (the member wins when both are set). Propagates:
    /// placed on a container's content it applies to every `ZTronScrollView` inside.
    public func ztronNestedScrollPolicy(_ policy: ZTronNestedScrollPolicy) -> some View {
        environment(\.ztronNestedScrollPolicy, policy)
    }
}
