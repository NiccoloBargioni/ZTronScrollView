import SwiftUI
import ZTronScrollPhysics

// Type mirror of SwiftUI's scroll-target family (SPEC S8-4, docs/design/M6-targets.md §2): `ScrollTarget`,
// `ScrollTargetBehavior` with its Context / Properties / PropertiesContext, `AnyScrollTargetBehavior`. SwiftUI's own
// types exist only on iOS 17+ and cannot be constructed publicly, so the mirror is what runs in the release pipeline.
// Names follow the SDK (`properties(context:)`, `limitsScrolls`); `limitsVelocity` is the design's spelling of the same flag.

/// Where a release will land: mirrors `ScrollTarget`, in SwiftUI's space (D27, measured against a native `ScrollView`).
/// `rect` is the visible rect the scroll view should end at, in content coordinates: its origin is the content offset
/// plus the adjusted content inset on the start edges (so a view at rest at the top reports `y == 0`, whatever the safe
/// area), its size the unobscured container (`containerSize`, the viewport minus the insets). `anchor` places the rect's
/// origin along the container: the pipeline lands at `rect.origin + anchor · (rect.size - containerSize)` minus the
/// start insets (`nil` = `.zero`). With zero insets content coordinates and offsets are the same numbers.
public struct ZTronScrollTarget: Equatable, Sendable {
    public var rect: CGRect
    public var anchor: UnitPoint?

    public init(rect: CGRect, anchor: UnitPoint? = nil) {
        self.rect = rect
        self.anchor = anchor
    }
}

@available(iOS 17, *)
extension ZTronScrollTarget {
    /// Reads SwiftUI's target. SwiftUI's `ScrollTarget` has no public initializer, so the reverse conversion can only
    /// write into a target SwiftUI hands out (``write(to:)``).
    public init(_ native: ScrollTarget) {
        self.init(rect: native.rect, anchor: native.anchor)
    }

    /// Writes `rect` and `anchor` into a native target in place (the only way to produce a native value).
    public func write(to native: inout ScrollTarget) {
        native.rect = rect
        native.anchor = anchor
    }
}

/// Source of the `EnvironmentValues` a context answers its dynamic-member reads from: a captured copy for the release
/// pipeline, SwiftUI's own context when a behavior runs bridged inside a native `ScrollView` (the whole native
/// environment is not readable, only key paths).
protocol TargetEnvironmentSource {
    func value<T>(_ keyPath: KeyPath<EnvironmentValues, T>) -> T
}

struct CapturedTargetEnvironment: TargetEnvironmentSource {
    var values = EnvironmentValues()
    func value<T>(_ keyPath: KeyPath<EnvironmentValues, T>) -> T { values[keyPath: keyPath] }
}

/// What the library's own behaviors need beyond the public context (internal: the pipeline fills it, built-ins read it).
/// The geometry here stays in OFFSET space (`UIScrollView.contentOffset`, bounds from `-inset.start`); the public
/// context and target are in content coordinates, and `decideTarget` is the one place that converts.
struct TargetReleaseInfo {
    /// The offset at the lift.
    var origin: CGPoint = .zero
    /// The offset when the drag began (page boundaries are measured from the page it started on).
    var dragStart: CGPoint = .zero
    /// The accelerated release velocity (pt/s) before ``ZTronScrollTargetBehaviorProperties/limitsVelocity``.
    var rawVelocity: CGVector = .zero
    /// Adjusted content inset (`state.adjustedContentInset`).
    var insets = EdgeInsets()
    /// The inset on the start edges (x: leading, y: top): content coordinates are offsets plus this.
    var startInset: CGPoint = .zero
    /// The whole viewport (the public `containerSize` is this minus the insets).
    var viewport: CGSize = .zero
    /// Scrollable offset range per axis at the current zoom.
    var boundsX = AxisBounds(min: 0, max: 0)
    var boundsY = AxisBounds(min: 0, max: 0)
    var zoomScale: CGFloat = 1
    /// The scroll view's registered targets (`ztronScrollID`); `nil` outside a `ZTronScrollView`.
    var registry: TargetRegistry?
}

/// What a behavior sees at a release: mirrors `ScrollTargetBehaviorContext`. `velocity` is the release velocity in pt/s
/// (limited when the behavior's properties say so), `contentSize` is the zoomed content size (UIKit's `contentSize`),
/// `containerSize` the unobscured size (viewport minus the adjusted insets, SwiftUI's). Environment values are read
/// with `context.horizontalSizeClass`.
@dynamicMemberLookup
public struct ZTronScrollTargetBehaviorContext {
    public let originalTarget: ZTronScrollTarget
    public let velocity: CGVector
    public let contentSize: CGSize
    public let containerSize: CGSize
    public let axes: Axis.Set
    let environment: any TargetEnvironmentSource
    let info: TargetReleaseInfo

    init(originalTarget: ZTronScrollTarget, velocity: CGVector, contentSize: CGSize, containerSize: CGSize, axes: Axis.Set,
         environment: any TargetEnvironmentSource = CapturedTargetEnvironment(), info: TargetReleaseInfo = TargetReleaseInfo()) {
        self.originalTarget = originalTarget
        self.velocity = velocity
        self.contentSize = contentSize
        self.containerSize = containerSize
        self.axes = axes
        self.environment = environment
        self.info = info
    }

    public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T {
        environment.value(keyPath)
    }
}

@available(iOS 17, *)
private struct NativeTargetEnvironment: TargetEnvironmentSource {
    let context: ScrollTargetBehaviorContext
    func value<T>(_ keyPath: KeyPath<EnvironmentValues, T>) -> T { context[dynamicMember: keyPath] }
}

@available(iOS 17, *)
extension ZTronScrollTargetBehaviorContext {
    /// Reads SwiftUI's context (one way: SwiftUI's context is not constructible, so a native behavior cannot run in the
    /// release pipeline). The library-internal extras are derived from the public values; environment reads go through
    /// SwiftUI's context.
    public init(_ native: ScrollTargetBehaviorContext) {
        let target = ZTronScrollTarget(native.originalTarget)
        var info = TargetReleaseInfo()
        info.origin = target.rect.origin
        info.dragStart = target.rect.origin
        info.rawVelocity = native.velocity
        info.viewport = native.containerSize
        info.boundsX = AxisBounds(contentLength: native.contentSize.width, viewportLength: native.containerSize.width, insets: .zero)
        info.boundsY = AxisBounds(contentLength: native.contentSize.height, viewportLength: native.containerSize.height, insets: .zero)
        self.init(originalTarget: target, velocity: native.velocity, contentSize: native.contentSize,
                  containerSize: native.containerSize, axes: native.axes,
                  environment: NativeTargetEnvironment(context: native), info: info)
    }
}

/// What a behavior asks of the release before it runs: mirrors `ScrollTargetBehaviorProperties` (iOS 18.4's
/// `limitsScrolls`). With `limitsVelocity` the release velocity is capped so the natural landing point is at most one
/// container length from where the finger lifted, and ``ZTronScrollTargetBehavior/updateTarget(_:context:)`` sees that
/// capped velocity and landing point.
public struct ZTronScrollTargetBehaviorProperties: Equatable, Sendable {
    public var limitsVelocity: Bool

    public init() { limitsVelocity = false }
    public init(limitsVelocity: Bool) { self.limitsVelocity = limitsVelocity }

    /// SwiftUI's spelling of ``limitsVelocity``.
    public var limitsScrolls: Bool {
        get { limitsVelocity }
        set { limitsVelocity = newValue }
    }

    public static let `default` = ZTronScrollTargetBehaviorProperties()
}

/// Mirrors `ScrollTargetBehaviorPropertiesContext` (`axes`, `environment`) plus the sizes the library knows.
public struct ZTronScrollTargetBehaviorPropertiesContext {
    public let axes: Axis.Set
    public let contentSize: CGSize
    public let containerSize: CGSize
    public let environment: EnvironmentValues

    init(axes: Axis.Set, contentSize: CGSize, containerSize: CGSize, environment: EnvironmentValues = EnvironmentValues()) {
        self.axes = axes
        self.contentSize = contentSize
        self.containerSize = containerSize
        self.environment = environment
    }
}

/// Mirrors `ScrollTargetBehavior`. At a release the pipeline calls ``updateTarget(_:context:)`` with the natural
/// landing point of the fling; the behavior moves it (snap to a page, an item, a grid) and the scroll view lands there.
/// The requirements are main-actor isolated (the registry of targets lives there); a conformer may implement them
/// without isolation.
public protocol ZTronScrollTargetBehavior {
    typealias TargetContext = ZTronScrollTargetBehaviorContext
    typealias Properties = ZTronScrollTargetBehaviorProperties
    typealias PropertiesContext = ZTronScrollTargetBehaviorPropertiesContext

    @MainActor func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext)
    @MainActor func properties(context: PropertiesContext) -> Properties
}

extension ZTronScrollTargetBehavior {
    @MainActor public func properties(context: PropertiesContext) -> Properties { Properties() }
}

/// Marks library behaviors that retarget the release motion onto their snap point, even when it equals the natural
/// landing point (a page flick back at the first page must not bounce). A behavior with nothing to snap to (a view-aligned
/// scroll view without targets) answers `false` and keeps the plain decay, edge bounce included.
protocol ZTronSnappingBehavior {
    @MainActor func snaps(_ info: TargetReleaseInfo) -> Bool
}

extension ZTronSnappingBehavior {
    @MainActor func snaps(_ info: TargetReleaseInfo) -> Bool { true }
}

/// Mirrors `AnyScrollTargetBehavior` (`base`).
public struct AnyZTronScrollTargetBehavior: ZTronScrollTargetBehavior {
    public var base: any ZTronScrollTargetBehavior

    public init(_ base: some ZTronScrollTargetBehavior) {
        if let erased = base as? AnyZTronScrollTargetBehavior {
            self.base = erased.base
        } else {
            self.base = base
        }
    }

    @MainActor public func updateTarget(_ target: inout ZTronScrollTarget, context: TargetContext) {
        base.updateTarget(&target, context: context)
    }

    @MainActor public func properties(context: PropertiesContext) -> Properties {
        base.properties(context: context)
    }

    /// The behavior retargets (see ``ZTronSnappingBehavior``).
    @MainActor func snaps(_ info: TargetReleaseInfo) -> Bool { (base as? any ZTronSnappingBehavior)?.snaps(info) ?? false }
    /// Whether the behavior is a library snapping behavior at all (independent of the release).
    var snapsTarget: Bool { base is any ZTronSnappingBehavior }
}
