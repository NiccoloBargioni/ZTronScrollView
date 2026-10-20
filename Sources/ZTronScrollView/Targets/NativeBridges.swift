import SwiftUI

// Conversions between the scroll-target mirror and SwiftUI's own types (SPEC S8-4, design M6 §1; D3 gating). SwiftUI's
// `ScrollTarget` and `ScrollTargetBehaviorContext` are not publicly constructible, so native behaviors cannot run in
// the release pipeline; ours run inside a native `ScrollView` through the twin and `ZTronBridgedScrollTargetBehavior`.
// `ScrollTarget`/`Context` converters live with their types in `ScrollTargetBehavior.swift`.

@available(iOS 17, *)
extension ZTronViewAlignedScrollTargetBehavior.LimitBehavior {
    /// SwiftUI's limit behavior. `.alwaysByOne` and `.alwaysByFew` exist from iOS 18; on iOS 17 both are `.always`
    /// (by one). SwiftUI's value has no inspectable state, so there is no reverse conversion.
    public var native: ViewAlignedScrollTargetBehavior.LimitBehavior {
        switch kind {
        case .automatic: return .automatic
        case .never: return .never
        case .alwaysByOne:
            if #available(iOS 18, *) { return .alwaysByOne }
            return .always
        case .alwaysByFew:
            if #available(iOS 18, *) { return .alwaysByFew }
            return .always
        }
    }
}

@available(iOS 17, *)
extension ZTronViewAlignedScrollTargetBehavior {
    /// SwiftUI's view-aligned behavior (the anchor needs iOS 26 and is dropped before it).
    public var native: ViewAlignedScrollTargetBehavior {
        if #available(iOS 26, *) {
            return ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior.native, anchor: anchor)
        }
        return ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior.native)
    }
}

@available(iOS 17, *)
extension ZTronPagingScrollTargetBehavior {
    public init(_ native: PagingScrollTargetBehavior) { self.init() }
    public var native: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}

@available(iOS 18, *)
extension AnyZTronScrollTargetBehavior {
    /// SwiftUI's type-erased behavior: the library's built-ins become SwiftUI's own, anything else runs bridged. (SwiftUI's
    /// behaviors cannot run in this library, so there is no reverse conversion.)
    public var native: AnyScrollTargetBehavior {
        if let paging = base as? ZTronPagingScrollTargetBehavior { return AnyScrollTargetBehavior(paging.native) }
        if let aligned = base as? ZTronViewAlignedScrollTargetBehavior { return AnyScrollTargetBehavior(aligned.native) }
        return AnyScrollTargetBehavior(ZTronBridgedScrollTargetBehavior(self))
    }
}

@available(iOS 17, *)
extension View {
    /// Applies SwiftUI's `scrollTargetBehavior` for `behavior` (the twin's native half).
    @ViewBuilder
    func applyingNativeScrollTargetBehavior(_ behavior: AnyZTronScrollTargetBehavior) -> some View {
        if let paging = behavior.base as? ZTronPagingScrollTargetBehavior {
            scrollTargetBehavior(paging.native)
        } else if let aligned = behavior.base as? ZTronViewAlignedScrollTargetBehavior {
            scrollTargetBehavior(aligned.native)
        } else {
            scrollTargetBehavior(ZTronBridgedScrollTargetBehavior(behavior))
        }
    }
}
