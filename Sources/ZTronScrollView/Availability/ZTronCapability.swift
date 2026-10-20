import Foundation

/// A newer-OS API family the library gates behind `#available` (SPEC S3).
///
/// One case per row of the availability matrix in `docs/design/design-note.md` (checked by hand against the Xcode 27
/// iOS SDK swiftinterfaces). The pinch row is split into `magnifyGesture` (17) and `liveMagnifyCentroid` (18), and
/// `scrollBounceBehaviorType` (16.4) covers `ScrollBounceBehavior`.
/// Resolve a capability with ``ZTronAvailability/isAvailable(_:)``; see its header for the call-site rules (including
/// APIs newer than the Xcode 26 SDK).
public enum ZTronCapability: String, CaseIterable, Sendable, Hashable {
    /// `@Observable` (iOS 17). Fallback: one `ObservableObject` per channel (offset, zoom, metrics, phase).
    case perPropertyObservation
    /// `Layout` (iOS 16). Fallback: `fixedSize` on scrollable axes plus a top-leading viewport frame.
    case layoutProtocol
    /// `onGeometryChange(for:of:action:)`, back-deployed (iOS 16): **only the single-value `action: (newValue)`
    /// overload**. The `action: (oldValue, newValue)` overload needs iOS 18, so call sites gated on this capability keep
    /// the previous value themselves. Fallback: `GeometryReader` + `PreferenceKey`.
    case geometryChange
    /// `visualEffect` (iOS 17). Fallback: a leaf modifier reading geometry.
    case visualEffect
    /// `SpatialEventGesture`: raw touches, catch, timestamps. The API ships in iOS 18 but the library uses it from
    /// **iOS 26** (D34): on 18.x its recognizer begins with the first touch movement and cancels the touches of
    /// UIKit-backed controls (a SwiftUI `Slider` inside the scroll view never moves). Fallback, also on 18.x:
    /// `DragGesture(minimumDistance: 0)`, armed only while content moves or a touch it saw is down (`CatchArming`).
    case spatialEvents
    /// `MagnifyGesture` (iOS 17). Fallback: `MagnificationGesture`.
    case magnifyGesture
    /// Live pinch centroid via `SpatialEventGesture` (used from iOS 26 like ``spatialEvents``, D34). Fallback:
    /// drag-location focal estimate.
    case liveMagnifyCentroid
    /// `GestureInputKinds`: pointer / indirect / pencil (iOS 27). No fallback: every input is treated as direct touch.
    /// The type exists only in the iOS 27 SDK: call sites need `#if compiler(>=6.4)` around `#available(iOS 27, *)`
    /// (see ``isInBuildSDK``), so Xcode 26.x still builds the library.
    case gestureInputKinds
    /// `Spring` / `UnitCurve` (iOS 17). Fallback: the physics package's own closed forms.
    case nativeCurves
    /// `Transaction.addAnimationCompletion` (iOS 17). Fallback: presentation probe settled for 2 frames.
    case animationCompletion
    /// `withTransaction(\.disablesAnimations, true)` (iOS 17 in older SDKs; kept at 17 so Xcode 26.x builds).
    /// Fallback: `withTransaction(Transaction)`.
    case keyPathTransaction
    /// `focusable` + `onKeyPress` (iOS 17). Fallback: hidden buttons with `keyboardShortcut`.
    case keyboardScrolling
    /// `accessibilityZoomAction` (iOS 16). Fallback: named accessibility actions.
    case accessibilityZoom
    /// `sensoryFeedback` (iOS 17). Fallback: none on the refresh trigger (documented).
    case sensoryFeedback
    /// `NamedCoordinateSpace` (iOS 17). Fallback: `coordinateSpace(name:)`.
    case namedCoordinateSpace
    /// `Group(subviews:)` and `ContainerValues` (iOS 18). Fallback: explicit child modifiers.
    case subviewContainers
    /// `ScrollBounceBehavior` (iOS 16.4), one direction only: the physics `BounceBehavior` converts **to** it (a
    /// `switch` onto its static members, e.g. to forward the policy to nested native scroll views). It cannot be read
    /// back: the type is an opaque, non-`Equatable` struct, so `.scrollBounceBehavior(_:axes:)` values in the
    /// environment cannot be mapped to cases without reflection. Fallback (every OS): the library's own
    /// `ztronScrollBounceBehavior(_:axes:)` modifier carrying `BounceBehavior`.
    case scrollBounceBehaviorType
    /// The passive UIKit touch observer (SPEC S2 amendment 2026-10-20, D31): touch-down at rest, live pinch centroid and
    /// finger count on **iOS 15-16 only**. The one capability whose preferred path is the OLD-OS one: it is available
    /// below iOS 17 (`preferredOSCeiling`), never on 17+ (which keeps the `DragGesture` fallback with its documented
    /// divergences) and never alongside `SpatialEventGesture`. Fallback: `DragGesture(minimumDistance: 0)` as on 17.
    /// DEBUG only: ``ZTronAvailability/forceUIKitTouchObserver(_:)`` turns it on for 17+ simulators.
    case uikitTouchObserver
    /// `TimelineView(.animation)` (iOS 15). Always available: never gated, never forced.
    case frameClock

    /// The library's minimum deployment target (SPEC S2).
    static let deploymentTarget: (major: Int, minor: Int) = (15, 0)

    /// The first iOS release on which the library uses the preferred API. Usually the release that ships it; later for
    /// `spatialEvents` and `liveMagnifyCentroid` (shipped in 18, used from 26, D34).
    public var minimumOS: (major: Int, minor: Int) {
        switch self {
        case .frameClock, .uikitTouchObserver:
            return (15, 0)
        case .layoutProtocol, .geometryChange, .accessibilityZoom:
            return (16, 0)
        case .scrollBounceBehaviorType:
            return (16, 4)
        case .perPropertyObservation, .visualEffect, .magnifyGesture, .nativeCurves, .animationCompletion,
             .keyPathTransaction, .keyboardScrolling, .sensoryFeedback, .namedCoordinateSpace:
            return (17, 0)
        case .subviewContainers:
            return (18, 0)
        case .spatialEvents, .liveMagnifyCentroid:
            return (26, 0)
        case .gestureInputKinds:
            return (27, 0)
        }
    }

    /// The first iOS release that no longer uses the preferred API, for the one capability whose preferred path is the
    /// old-OS one (`uikitTouchObserver`: available from `minimumOS` up to, excluding, this release). `nil` for every
    /// other capability: the preferred API runs on every OS from `minimumOS` on.
    var preferredOSCeiling: (major: Int, minor: Int)? {
        switch self {
        case .uikitTouchObserver:
            return (17, 0)
        default:
            return nil
        }
    }

    /// Whether this build's SDK declares the preferred API, so its call sites are compiled in.
    ///
    /// `false` only for capabilities newer than the oldest supported build SDK (Xcode 26.x, D3) when building with
    /// it: today `gestureInputKinds`, whose type first ships in the iOS 27 SDK (Swift 6.4 / Xcode 27). Every such call
    /// site is wrapped in the same `#if compiler(>=6.4)` as this property, and ``ZTronAvailability/isAvailable(_:)``
    /// reports `false` when the code is compiled out, even on an iOS 27 runtime.
    public var isInBuildSDK: Bool {
        switch self {
        case .gestureInputKinds:
            #if compiler(>=6.4)
            return true
            #else
            return false
            #endif
        default:
            return true
        }
    }

    /// Whether an alternative implementation exists below ``minimumOS``.
    /// `false` for `frameClock` (needs none) and `gestureInputKinds` (the feature is simply absent).
    public var hasFallback: Bool {
        switch self {
        case .frameClock, .gestureInputKinds:
            return false
        default:
            return true
        }
    }

    /// Whether the capability needs a runtime check on the deployment target (iOS 15).
    /// Only gated capabilities can be force-fallbacked; `frameClock` is the one ungated case.
    public var isGated: Bool {
        if preferredOSCeiling != nil { return true }
        let os = minimumOS
        let floor = Self.deploymentTarget
        return os.major > floor.major || (os.major == floor.major && os.minor > floor.minor)
    }
}
