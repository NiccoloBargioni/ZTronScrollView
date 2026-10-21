import SwiftUI

// Content-integral overlay (SPEC S11 amendment 2026-10-21 (user), design M6b §1–§3): a view laid out in the unscaled
// content space, under the transform, so it scrolls and zooms with the content like a marker drawn on a map. Placement
// rule, every case: the overlay's `overlayAnchor` point sits on the content point `anchor`; `size` is resolved against
// the content's size in the same layout pass that sizes the content (never from metrics, offset or zoom).

/// A point of the content, in the unscaled content space of a ``ZTronScrollView``: where a content-integral overlay's
/// `overlayAnchor` point is pinned (see ``ZTronScrollView/scrollContentIntegralOverlay(anchor:overlayAnchor:size:scaling:content:)``).
///
/// The nine named cases are sugar for ``relative(_:)`` with the `UnitPoint` of the same name: `.center` is
/// `.relative(.center)`, the point at half the content's width and half its height. The point follows the content's
/// size whenever it changes (a reflow on rotation, a list that grows); ``absolute(_:)`` does not.
public enum ZTronContentOverlayAnchor: Equatable, Sendable {
    /// The content's top-leading corner, `(0, 0)`.
    case topLeading
    /// The middle of the content's top edge, `(W / 2, 0)`.
    case top
    /// The content's top-trailing corner, `(W, 0)`.
    case topTrailing
    /// The middle of the content's leading edge, `(0, H / 2)`.
    case leading
    /// The content's centre, `(W / 2, H / 2)`.
    case center
    /// The middle of the content's trailing edge, `(W, H / 2)`.
    case trailing
    /// The content's bottom-leading corner, `(0, H)`.
    case bottomLeading
    /// The middle of the content's bottom edge, `(W / 2, H)`.
    case bottom
    /// The content's bottom-trailing corner, `(W, H)`.
    case bottomTrailing
    /// A fraction of the content's size per axis: `(W · point.x, H · point.y)`. Values outside `0...1` name points
    /// outside the content.
    case relative(UnitPoint)
    /// A fixed point in unscaled content points, independent of the content's size. Non-finite components count as 0.
    case absolute(CGPoint)
}

/// The size proposed to a content-integral overlay, resolved against the content's size `W × H` (unscaled content
/// points). The overlay's frame is this size on every axis it specifies and the view's own size on an axis it leaves
/// unspecified; a view that takes less than its frame is centred in it (SwiftUI's `frame(width:height:)`).
public enum ZTronContentOverlaySize: Equatable, Sendable {
    /// The whole content rect (the default): the overlay covers the content exactly, `anchor` and `overlayAnchor` are
    /// ignored, and a view that takes less is centred in it — SwiftUI's own `.overlay` applied to the content.
    case fillMaxSize
    /// Width = the content's width; height = width / `aspectRatio` (width over height, as SwiftUI's `aspectRatio`:
    /// `.fillMaxWidth(16 / 9)` is `W × 9W/16`). `nil`, zero, negative or non-finite: the view's own height at width `W`
    /// (wrapped text).
    case fillMaxWidth(_ aspectRatio: CGFloat? = nil)
    /// Height = the content's height; width = height × `aspectRatio`. `nil`, zero, negative or non-finite: the view's
    /// own width at height `H`.
    case fillMaxHeight(_ aspectRatio: CGFloat? = nil)
    /// A fraction of the content's size per axis: `(W · size.width, H · size.height)`. Negative or non-finite
    /// components count as 0.
    case relative(CGSize)
    /// A fixed size in unscaled content points, independent of the content's size (only the origin follows it).
    /// Negative or non-finite components count as 0.
    case absolute(CGSize)
    /// The view's ideal size (`fixedSize()`): a small marker, a label at its natural size.
    case ideal
}

/// How a content-integral overlay draws under zoom.
public enum ZTronContentOverlayScaling: Equatable, Sendable {
    /// The overlay is part of the content: it scales with the zoom (the default).
    case withContent
    /// The overlay keeps a constant on-screen size: its frame is still resolved in the content space and its
    /// `overlayAnchor` point stays on the content point `anchor`, but it is drawn scaled by `1 / zoomScale` around that
    /// point. During a rotation at the fitting scale the content's drawn scale is resolved frame by frame while the
    /// committed zoom holds its value, so a counter-scaled overlay may differ slightly in size mid-rotation; it lands exact.
    case counterScaled
}

/// One `scrollContentIntegralOverlay` call (member) or `ztronScrollContentIntegralOverlay` twin, as the container
/// resolves them: twins first (outermost first), then the members in call order. `key` is the overlay's identity: a
/// member's position (`"member.<index>"`), a twin's `@State` token.
struct ContentOverlayDecl {
    var key: AnyHashable
    var anchor: ZTronContentOverlayAnchor
    var overlayAnchor: UnitPoint
    var size: ZTronContentOverlaySize
    var scaling: ZTronContentOverlayScaling
    var view: AnyView
    /// Set by the `Equatable` overloads: the host keeps the previous erased view while the new value is `==` to it.
    var equality: ContentOverlayEquality? = nil

    /// What layout needs (the view excluded).
    var placement: ContentOverlayPlacement {
        ContentOverlayPlacement(anchor: anchor, overlayAnchor: overlayAnchor, size: size)
    }

    /// The user's view in one unary container: several views in the builder stack like SwiftUI's `.overlay` content
    /// (an implicit `ZStack`), so each call is exactly one overlay.
    static func wrap<V: View>(_ view: V) -> AnyView {
        AnyView(ZStack { view })
    }
}

/// The `==` of an `Equatable` overlay, type-erased. `EquatableView` alone does not gate a body inside `AnyView`: measured
/// in M6b L1, an `AnyView(EquatableView(v))` rebuilt with an equal value re-ran `v`'s body on a parent re-evaluation on
/// iOS 17.5 and 27.0 (on 27.0 even a bare `EquatableView` did), so the host compares the values itself and hands SwiftUI
/// the very same `AnyView` when they are equal (`ContentOverlayViewCache`), which SwiftUI does not diff at all.
struct ContentOverlayEquality {
    let value: Any
    let isEqual: (Any) -> Bool

    init<V: Equatable>(_ value: V) {
        self.value = value
        self.isEqual = { ($0 as? V) == value }
    }
}

/// The host's memory of the `Equatable` overlays it drew: per key, the value and the erased view shown for it.
@MainActor
final class ContentOverlayViewCache: ObservableObject {
    private var entries: [AnyHashable: (value: Any, view: AnyView)] = [:]

    /// `decls` with every `Equatable` overlay whose value is `==` to the one shown under the same key carrying the
    /// previous `AnyView` (and value, as `EquatableView` keeps the old value). Entries of vanished keys are dropped.
    func stabilized(_ decls: [ContentOverlayDecl]) -> [ContentOverlayDecl] {
        var next: [AnyHashable: (value: Any, view: AnyView)] = [:]
        let out = decls.map { decl -> ContentOverlayDecl in
            guard let equality = decl.equality else { return decl }
            var d = decl
            if let kept = entries[d.key], equality.isEqual(kept.value) {
                d.view = kept.view
                next[d.key] = kept
            } else {
                next[d.key] = (equality.value, d.view)
            }
            return d
        }
        entries = next
        return out
    }
}

/// The layout inputs of one overlay.
struct ContentOverlayPlacement: Equatable, Sendable {
    var anchor: ZTronContentOverlayAnchor
    var overlayAnchor: UnitPoint
    var size: ZTronContentOverlaySize
}
