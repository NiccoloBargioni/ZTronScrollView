import SwiftUI

/// What `withScalingHeader` stores on the view value (`ScrollViewConfig.header`, cold). The builder is type-erased: the
/// erased type is fixed at the call site, so the header's identity and `@State` survive every update, and the member can
/// return `Self`. `==` compares the value fields only (a new builder closure is always applied, R7).
struct HeaderSpec {
    var size: ZTronHeaderSize
    var behavior: ZTronHeaderScalingBehavior
    var snap: ZTronHeaderSnap
    var fade: ZTronHeaderFade?
    var background: ZTronHeaderBackground?
    var overflow: ZTronHeaderOverflow = .uncapped
    var builder: (ZTronHeaderProxy) -> AnyView

    var sizing: HeaderSizing { HeaderSizing(size: size, behavior: behavior, snap: snap, overflow: overflow) }
}

/// The cold values the state needs to resolve and snap the header (`ZTronScrollState.headerSpec`).
struct HeaderSizing: Equatable {
    var size: ZTronHeaderSize
    var behavior: ZTronHeaderScalingBehavior
    var snap: ZTronHeaderSnap
    var overflow: ZTronHeaderOverflow = .uncapped

    /// `HeaderMath.resolve` plus its DEBUG warnings; `nil` while the width is unknown or `.fit` unmeasured.
    @MainActor func resolve(width: CGFloat, natural: CGFloat?, vertical: Bool, containerHeight: CGFloat) -> HeaderMetrics? {
        let r = HeaderMath.resolve(size: size, width: width, natural: natural, behavior: behavior, vertical: vertical,
                                   containerHeight: containerHeight, overflow: overflow)
        #if DEBUG
        if let warning = r.warning { HeaderDiagnostics.note(warning) }
        if r.metrics != nil, behavior == .stretch, !vertical {
            HeaderDiagnostics.note("withScalingHeader: .stretch is inert on a scroll view without the vertical axis (a fixed banner)")
        }
        #endif
        return r.metrics
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
