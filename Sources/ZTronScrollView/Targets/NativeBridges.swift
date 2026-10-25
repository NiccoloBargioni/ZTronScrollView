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

// MARK: Position and anchors (M6 session 3)

@available(iOS 18, *)
extension ZTronScrollAnchorRole {
    public init(_ native: ScrollAnchorRole) {
        if native == .sizeChanges {
            self = .sizeChanges
        } else if native == .alignment {
            self = .alignment
        } else {
            self = .initialOffset
        }
    }

    public var native: ScrollAnchorRole {
        switch self {
        case .initialOffset: return .initialOffset
        case .sizeChanges: return .sizeChanges
        case .alignment: return .alignment
        }
    }
}

@available(iOS 18, *)
extension ZTronScrollPosition {
    /// Reads SwiftUI's position (a view id, a point or an edge; `isPositionedByUser` comes along). A native position that
    /// names nothing becomes the empty position. The reverse conversion (``native``) cannot carry `isPositionedByUser`:
    /// SwiftUI only reads it.
    public init(_ native: ScrollPosition) {
        self.init(native, serial: 0)
    }

    init(_ native: ScrollPosition, serial: UInt64) {
        let request: Request?
        if let id = native.viewID {
            request = .id(AnyHashable(id), nil)
        } else if let edge = native.edge {
            request = .edge(edge)
        } else if let point = native.point {
            request = .point(point)
        } else if #available(iOS 26, *), let axes = Self.axes(native) {
            request = axes
        } else {
            request = nil
        }
        self.init(request: request, serial: serial, isPositionedByUser: native.isPositionedByUser)
        sendableID = native.viewID
    }

    /// iOS 26 reads one-axis requests back (`x` / `y`); before that they read as no request.
    @available(iOS 26, *)
    private static func axes(_ native: ScrollPosition) -> Request? {
        switch (native.x, native.y) {
        case let (x?, y?): return .xy(CGPoint(x: x, y: y))
        case let (x?, nil): return .x(x)
        case let (nil, y?): return .y(y)
        case (nil, nil): return nil
        }
    }

    /// SwiftUI's position for this request (`x` / `y` requests become one-axis `scrollTo`s).
    public var native: ScrollPosition {
        switch request {
        case let .id(id, anchor)?:
            if let typed = sendableID { return ScrollPosition(id: typed, anchor: anchor) }
            return ScrollPosition(id: SendableID(id), anchor: anchor)
        case let .edge(edge)?: return ScrollPosition(edge: edge)
        case let .point(point)?: return ScrollPosition(point: point)
        case let .x(x)?: return ScrollPosition(x: x)
        case let .y(y)?: return ScrollPosition(y: y)
        case let .xy(p)?: return ScrollPosition(x: p.x, y: p.y)
        case nil: return ScrollPosition()
        }
    }
}

/// SwiftUI's `ScrollPosition(id:)` wants a `Sendable` id. For an id the app gave as non-`Sendable` this carries it, and
/// converts back to the wrapped value when type-erased (`_HasCustomAnyHashableRepresentation`, a public stdlib protocol) so it
/// reads back equal; SwiftUI itself matches views by the id's own type, so such a request does not find the view (PARITY-s1:
/// every `Sendable` id goes through `sendableID` instead).
@available(iOS 18, *)
private struct SendableID: Hashable, @unchecked Sendable, _HasCustomAnyHashableRepresentation {
    let base: AnyHashable
    init(_ base: AnyHashable) { self.base = base }
    func _toCustomAnyHashable() -> AnyHashable? { base }
}
