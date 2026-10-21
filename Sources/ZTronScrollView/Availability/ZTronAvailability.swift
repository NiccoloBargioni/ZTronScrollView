import Foundation

/// Resolves ``ZTronCapability`` at runtime (SPEC S3).
///
/// A capability is available when the build compiled its preferred API in, the running OS ships it, **and** it is
/// not force-fallbacked. Call sites still need the literal check so the compiler type-checks the gated API:
///
/// ```swift
/// if ZTronAvailability.isAvailable(.visualEffect), #available(iOS 17, *) { /* preferred */ } else { /* fallback */ }
/// ```
///
/// **APIs newer than the Xcode 26 SDK** (D3: Xcode 26.x must still build the library for the iOS 15/16 smoke tests).
/// `#available` does not hide a symbol from the type checker, and an iOS 26 SDK cannot declare an iOS 27 type, so
/// every call site of such an API (today: `GestureInputKinds`, the `inputKinds:` gesture initializers) is also
/// wrapped in a compile-time check, with the fallback in both `#else` branches:
///
/// ```swift
/// #if compiler(>=6.4)                       // Xcode 27+: the iOS 27 SDK declares the API
/// if ZTronAvailability.isAvailable(.gestureInputKinds), #available(iOS 27, *) { /* preferred */ } else { /* fallback */ }
/// #else
/// /* fallback */
/// #endif
/// ```
///
/// Reviews reject an iOS 27+ symbol outside such a block; ``ZTronCapability/isInBuildSDK`` uses the same condition.
///
/// The force-fallback switch exists only in DEBUG builds, so CI exercises every fallback on newer simulators.
/// In release builds the switch functions are inert no-ops and ``forcedFallbacks`` is always empty.
/// All members are thread-safe (the DEBUG store is lock-protected).
public enum ZTronAvailability {
    /// `true` when the preferred API is compiled in (``ZTronCapability/isInBuildSDK``), the running OS ships it, and
    /// the DEBUG switch has not forced its fallback.
    public static func isAvailable(_ capability: ZTronCapability) -> Bool {
        if capability == .uikitTouchObserver, isUIKitTouchObserverForcedOn { return true }
        return osSupports(capability) && !isForced(capability)
    }

    /// `true` in DEBUG builds, where the force-fallback switch works; `false` in release builds.
    public static var isForcingSupported: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Forces (`on == true`) or clears the fallback for one capability.
    /// Ignored for ungated capabilities (`frameClock`) and in release builds.
    public static func forceFallback(_ capability: ZTronCapability, _ on: Bool) {
        #if DEBUG
        ForcedFallbackStore.shared.set(capability, on)
        #endif
    }

    /// Forces (`on == true`) every gated capability's fallback, or clears all forced fallbacks.
    /// Ignored in release builds.
    public static func forceAllFallbacks(_ on: Bool) {
        #if DEBUG
        ForcedFallbackStore.shared.setAll(on)
        #endif
    }

    /// DEBUG only: `on == true` makes ``ZTronCapability/uikitTouchObserver`` available on iOS 17+ too, so the 17.5 / 27.0
    /// simulators run the iOS 15-16 observer shell (the demo's `-ZTronForceUIKitObserver`; combine it with
    /// `forceFallback(.spatialEvents, true)`, the state only uses the observer when spatial events are off). A switch of its
    /// own, independent of the forced-fallback set: `forceAllFallbacks` neither sets nor clears it, and it wins over a forced
    /// fallback of the same capability. Inert in release builds.
    public static func forceUIKitTouchObserver(_ on: Bool) {
        #if DEBUG
        ForcedFallbackStore.shared.setUIKitObserverOn(on)
        #endif
    }

    /// The capabilities currently force-fallbacked. Always empty in release builds.
    public static var forcedFallbacks: Set<ZTronCapability> {
        #if DEBUG
        return ForcedFallbackStore.shared.snapshot
        #else
        return []
        #endif
    }

    /// Replaces the whole forced set in one locked write (gated capabilities only), so a concurrent reader sees
    /// either the old or the new set, never a mix. Inert in release builds. Used by the test support's `withOSPath`.
    static func replaceForcedFallbacks(with forced: Set<ZTronCapability>) {
        #if DEBUG
        ForcedFallbackStore.shared.replace(with: forced)
        #endif
    }

    static var isUIKitTouchObserverForcedOn: Bool {
        #if DEBUG
        return ForcedFallbackStore.shared.uikitObserverOn
        #else
        return false
        #endif
    }

    static func isForced(_ capability: ZTronCapability) -> Bool {
        #if DEBUG
        return ForcedFallbackStore.shared.contains(capability)
        #else
        return false
        #endif
    }

    /// The literal `#available` result for `capability` on the running OS (`false` when the API is compiled out of
    /// this build), ignoring the switch. Keep each branch's version in sync with ``ZTronCapability/minimumOS`` (tested
    /// on the running OS only; the 16.x boundaries need an SDK check, see `docs/design/M1-physics.md` §6).
    static func osSupports(_ capability: ZTronCapability) -> Bool {
        switch capability {
        case .frameClock:
            return true
        case .uikitTouchObserver:
            if #unavailable(iOS 17) { return true } else { return false }
        case .layoutProtocol, .geometryChange, .accessibilityZoom:
            if #available(iOS 16, *) { return true } else { return false }
        case .scrollBounceBehaviorType:
            if #available(iOS 16.4, *) { return true } else { return false }
        case .perPropertyObservation, .visualEffect, .magnifyGesture, .nativeCurves, .animationCompletion,
             .keyPathTransaction, .keyboardScrolling, .sensoryFeedback, .namedCoordinateSpace:
            if #available(iOS 17, *) { return true } else { return false }
        case .subviewContainers:
            if #available(iOS 18, *) { return true } else { return false }
        case .spatialEvents, .liveMagnifyCentroid:
            // The API ships in iOS 18; used from 28 only (D34, D37, see ``ZTronCapability/spatialEvents``).
            if #available(iOS 28, *) { return true } else { return false }
        case .gestureInputKinds:
            #if compiler(>=6.4)
            if #available(iOS 27, *) { return true } else { return false }
            #else
            return false
            #endif
        }
    }
}

#if DEBUG
/// Process-wide forced-fallback set. `NSLock` keeps it Sendable on iOS 15 with a Swift 6.0 toolchain
/// (`Mutex` needs iOS 18, `OSAllocatedUnfairLock` iOS 16). Compiled only in DEBUG builds.
final class ForcedFallbackStore: @unchecked Sendable {
    static let shared = ForcedFallbackStore()

    private let lock = NSLock()
    private var forced: Set<ZTronCapability> = []
    private var observerOn = false

    var uikitObserverOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return observerOn
    }

    func setUIKitObserverOn(_ on: Bool) {
        lock.lock()
        defer { lock.unlock() }
        observerOn = on
    }

    func contains(_ capability: ZTronCapability) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return forced.contains(capability)
    }

    var snapshot: Set<ZTronCapability> {
        lock.lock()
        defer { lock.unlock() }
        return forced
    }

    func set(_ capability: ZTronCapability, _ on: Bool) {
        guard capability.isGated else { return }
        lock.lock()
        defer { lock.unlock() }
        if on {
            forced.insert(capability)
        } else {
            forced.remove(capability)
        }
    }

    func setAll(_ on: Bool) {
        replace(with: on ? Set(ZTronCapability.allCases) : [])
    }

    func replace(with newValue: Set<ZTronCapability>) {
        let gated = newValue.filter(\.isGated)
        lock.lock()
        defer { lock.unlock() }
        forced = gated
    }
}
#endif
