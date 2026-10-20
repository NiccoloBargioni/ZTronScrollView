import SwiftUI

/// Mirrors `ScrollAnchorRole` (iOS 18): which of a scroll view's anchoring decisions a `defaultScrollAnchor` answers.
public enum ZTronScrollAnchorRole: Hashable, Sendable, CaseIterable {
    /// Where the content starts, once, at the first layout (`nil` = the leading / top edge).
    case initialOffset
    /// Which point of the visible area stays put when the viewport or the content size changes (`nil` = the center rule, SPEC S7).
    case sizeChanges
    /// How content that fits is placed in the viewport, and which point of a view-aligned item meets the container
    /// (`nil` = the top-leading corner, centered once zooming is enabled).
    case alignment
}

// MARK: Member (S8-2a)

extension ZTronScrollView {
    /// `defaultScrollAnchor(_:)` for this view on iOS 15+: the anchor for all three roles.
    public func defaultScrollAnchor(_ anchor: UnitPoint?) -> Self {
        var copy = self
        for role in ZTronScrollAnchorRole.allCases { copy.config.anchors[role] = anchor }
        return copy
    }

    /// `defaultScrollAnchor(_:for:)` for this view on iOS 15+.
    public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ZTronScrollAnchorRole) -> Self {
        var copy = self
        copy.config.anchors[role] = anchor
        return copy
    }
}

// MARK: Twin (S8-2b)

extension View {
    /// Environment twin of ``ZTronScrollView/defaultScrollAnchor(_:)`` (the member wins). On iOS 17+ it also applies
    /// SwiftUI's `defaultScrollAnchor(_:)`, so a native `ScrollView` below follows the same anchor.
    @ViewBuilder
    public func ztronDefaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        let overlaid = transformEnvironment(\.ztronScrollConfig) { config in
            for role in ZTronScrollAnchorRole.allCases { config.anchors[role] = anchor }
        }
        if #available(iOS 17, *) {
            overlaid.defaultScrollAnchor(anchor)
        } else {
            overlaid
        }
    }

    /// Environment twin of ``ZTronScrollView/defaultScrollAnchor(_:for:)``. SwiftUI's `(_:for:)` needs iOS 18; on iOS 17 the
    /// native half applies for `.initialOffset` only (the one role iOS 17 has).
    @ViewBuilder
    public func ztronDefaultScrollAnchor(_ anchor: UnitPoint?, for role: ZTronScrollAnchorRole) -> some View {
        let overlaid = transformEnvironment(\.ztronScrollConfig) { $0.anchors[role] = anchor }
        if #available(iOS 18, *) {
            overlaid.defaultScrollAnchor(anchor, for: role.native)
        } else if #available(iOS 17, *), role == .initialOffset {
            overlaid.defaultScrollAnchor(anchor)
        } else {
            overlaid
        }
    }
}

extension ScrollViewConfig {
    /// The anchor for `role`: this configuration's, else `fallback`'s.
    func anchor(_ role: ZTronScrollAnchorRole, else fallback: ScrollViewConfig) -> UnitPoint? {
        anchors[role] ?? fallback.anchors[role]
    }
}
