import SwiftUI

/// What `withScalingHeader` stores on the view value (`ScrollViewConfig.header`, cold). The builder is type-erased: the
/// erased type is fixed at the call site, so the header's identity and `@State` survive every update, and the member can
/// return `Self`. `==` compares the value fields only (a new builder closure is always applied, R7).
struct HeaderSpec {
    var size: ZTronHeaderSize
    /// The `pull:` reaction (the former `scalingBehavior:`).
    var behavior: ZTronHeaderScalingBehavior
    /// D68: the `collapse:` reaction (with its `.slideBehind` backdrop).
    var collapse: ZTronHeaderCollapseBehavior = .compress
    var snap: ZTronHeaderSnap
    var fade: ZTronHeaderFade?
    var background: ZTronHeaderBackground?
    var overflow: ZTronHeaderOverflow = .uncapped
    var builder: (ZTronHeaderProxy) -> AnyView

    /// The state's cold values with the resolved pull behavior (D65: the member, else the environment, else `.openGap`;
    /// resolved by the container, which reads both).
    func sizing(pull: ZTronHeaderPullBehavior) -> HeaderSizing {
        HeaderSizing(size: size, behavior: behavior, collapse: collapse, snap: snap, overflow: overflow, pull: pull)
    }
}

/// The cold values the state needs to resolve and snap the header (`ZTronScrollState.headerSpec`).
struct HeaderSizing: Equatable {
    var size: ZTronHeaderSize
    var behavior: ZTronHeaderScalingBehavior
    /// D68: the collapse mode (carried into `HeaderMetrics.collapse`); a change (the backdrop's too) is a cold spec change.
    var collapse: ZTronHeaderCollapseBehavior = .compress
    var snap: ZTronHeaderSnap
    var overflow: ZTronHeaderOverflow = .uncapped
    /// D65: where a `.preserve` header's pull gap opens (carried into `HeaderMetrics.pull`). A change is a cold spec change
    /// (`headerSpecChanged()`), like a behavior change.
    var pull: ZTronHeaderPullBehavior = .openGap

    /// `HeaderMath.metrics` plus its DEBUG warnings (cold: the state's commits, never the layout path); `nil` while the
    /// width is unknown or `.fit` unmeasured.
    @MainActor func resolve(width: CGFloat, natural: CGFloat?, vertical: Bool, containerHeight: CGFloat) -> HeaderMetrics? {
        let metrics = HeaderMath.metrics(size: size, width: width, natural: natural, behavior: behavior,
                                         collapse: collapse.kind, pull: pull, vertical: vertical,
                                         containerHeight: containerHeight, overflow: overflow)
        #if DEBUG
        if let warning = HeaderMath.warning(size: size, width: width, natural: natural, containerHeight: containerHeight,
                                            overflow: overflow, collapse: collapse.kind) {
            HeaderDiagnostics.note(warning)
        }
        if let requested = collapse.requestedParallax, let k = collapse.parallax {
            HeaderDiagnostics.note("withScalingHeader: .slideBehind(parallax: \(requested)) is outside 0…1, read as \(k)")
        }
        if metrics != nil, behavior == .stretch, !vertical {
            HeaderDiagnostics.note("withScalingHeader: .stretch is inert on a scroll view without the vertical axis (a fixed banner)")
        }
        #endif
        return metrics
    }
}

#if DEBUG
/// DEBUG notes of the scaling header (degenerate sizes, inert `.stretch`): one `NSLog` line per distinct message per
/// process, also counted (`header.note`) and kept (`ZTronRenderCounters.notes["header.note"]`) for the tests.
@MainActor
enum HeaderDiagnostics {
    private static var seen = Set<String>()

    static func note(_ message: String) {
        ZTronRenderCounters.increment("header.note")
        ZTronRenderCounters.notes["header.note"] = message
        guard seen.insert(message).inserted, seen.count <= 64 else { return }
        NSLog("[ZTronScrollView] %@", message)
    }
}
#endif
