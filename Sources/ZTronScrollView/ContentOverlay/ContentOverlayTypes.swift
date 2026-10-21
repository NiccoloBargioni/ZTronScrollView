import SwiftUI

// Content-integral overlay (SPEC S11 amendment 2026-10-21 (user), design M6b §1–§3): a view laid out in the unscaled
// content space, under the transform, so it scrolls and zooms with the content like a marker drawn on a map. Placement
// rule, every case: the overlay's `overlayAnchor` point sits on the content point `anchor`; `size` is resolved against
// the content's size in the same layout pass that sizes the content (never from metrics, offset or zoom).

/// A point of the content, in the unscaled content space of a ``ZTronScrollView``: where a content-integral overlay's
/// `overlayAnchor` point is pinned (see ``ZTronScrollView/scrollContentIntegralOverlay(anchor:overlayAnchor:size:scaling:content:)``).
///
/// Each of the nine named cases draws like ``relative(_:)`` with the ``ZTronUnitPoint`` of the same name: `.center`
/// draws like `.relative(.center)`, the point at half the content's width and half its height. The two spellings are
/// different values, though: `==` compares the cases as written (`.center != .relative(.center)`), and an
/// ``absolute(_:)`` point compares as its `CGPoint` does. The point follows the content's size whenever it changes (a
/// reflow on rotation, a list that grows); ``absolute(_:)`` does not.
///
/// A relative anchor always lies on the content (its ``ZTronUnitPoint`` is clamped to `0...1`): to pin an overlay
/// outside the content, use ``absolute(_:)`` (unclamped, possibly negative), or keep the anchor on the content's edge
/// and move the overlay with `overlayAnchor`, which is a plain `UnitPoint` and not clamped (a callout whose tail point
/// lies outside its own frame is legitimate).
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
    /// A fraction of the content's size per axis: `(W · point.x, H · point.y)`, always a point of the content (the
    /// ``ZTronUnitPoint`` is clamped to `0...1` when it is built: `.relative(ZTronUnitPoint(x: 2, y: -1))` is the
    /// top-trailing corner). Before the unit types this case took a `UnitPoint`, whose values outside `0...1` named
    /// points outside the content: wrap it as `.relative(ZTronUnitPoint(p))`, or use ``absolute(_:)`` for such a point.
    case relative(ZTronUnitPoint)
    /// A fixed point in unscaled content points, independent of the content's size, and not clamped: the way to anchor
    /// an overlay outside the content. Non-finite components count as 0.
    case absolute(CGPoint)
}

/// The free axis of ``ZTronContentOverlaySize/fillMaxWidth(height:)`` (the overlay's height) or
/// ``ZTronContentOverlaySize/fillMaxHeight(width:)`` (its width), resolved against the content's size `W × H`.
///
/// Normalized when it becomes part of a ``ZTronContentOverlaySize``, so equal-rendering sizes compare equal: an
/// ``aspectRatio(_:)`` that is zero, negative or non-finite becomes ``ideal`` (DEBUG note `contentOverlay.badAspect`);
/// an ``absolute(_:)`` length that is negative or non-finite becomes 0; ``relative(_:)`` is clamped by its
/// ``ZTronUnitLength``, and a fraction of 0 is the length it draws, `.absolute(0)`. The lengths themselves compare as
/// written (`.relative(0) != .absolute(0)`); the sizes built from them compare by what they draw.
public enum ZTronContentOverlayLength: Equatable, Sendable {
    /// SwiftUI decides: the view's own length on that axis, measured with that axis unspecified and the filled axis at
    /// the content's length (wrapped text at width `W`).
    case ideal
    /// The overlay's width / height (SwiftUI's `aspectRatio` convention): `.fillMaxWidth(height: .aspectRatio(16 / 9))`
    /// is `W × 9W/16`, `.fillMaxHeight(width: .aspectRatio(0.5))` is `H/2 × H`. A ratio so extreme that `W / r` or
    /// `H · r` overflows `CGFloat` (a positive ratio near `.leastNonzeroMagnitude` or `.greatestFiniteMagnitude`) gives
    /// a length of 0 on that axis, never an infinite frame (DEBUG note `contentOverlay.badAspect`, written when the
    /// overflow happens in layout: whether it overflows depends on the content's size).
    case aspectRatio(CGFloat)
    /// A fixed length in unscaled content points (it scales with the zoom like the rest of the content).
    case absolute(CGFloat)
    /// A fraction of the content's length on the same axis, not of the overlay's filled one:
    /// `.fillMaxWidth(height: .relative(0.05))` is `W × 0.05 H`, `.fillMaxHeight(width: .relative(0.25))` is `0.25 W × H`.
    case relative(ZTronUnitLength)

    /// This length in canonical form, one axis of a ``ZTronContentOverlaySize`` (see the type's documentation): an
    /// unusable ratio is `.ideal`, an absolute length is finite and `≥ 0`, a relative fraction is `> 0` (0 is
    /// `.absolute(0)`, which draws the same).
    var normalized: Self {
        switch self {
        case .aspectRatio(let r): return ContentOverlayMath.aspect(r).map { .aspectRatio($0) } ?? .ideal
        case .absolute(let v): return .absolute(ContentOverlayMath.nonNegative(v))
        case .relative(let k): return k.value == 0 ? .absolute(0) : self
        case .ideal: return self
        }
    }
}

/// The size proposed to a content-integral overlay, resolved against the content's size `W × H` (unscaled content
/// points). The overlay's frame is this size on every axis it specifies and the view's own size on an axis it leaves
/// unspecified (``ideal``, ``ZTronContentOverlayLength/ideal``); a view that takes less than its frame is centred in it
/// (SwiftUI's `frame(width:height:)`).
///
/// Values are normalized when they are built, whatever the spelling, so two sizes that draw the same frame for every
/// content size compare equal and two that do not compare unequal. Within a spelling:
/// `.fillMaxWidth(0) == .fillMaxWidth() == .fillMaxWidth(height: .ideal)`,
/// `.fillMaxWidth(16 / 9) == .fillMaxWidth(height: .aspectRatio(16 / 9))`, negative or non-finite absolute lengths are
/// 0, and every relative fraction is a clamped unit type (``ZTronUnitLength``, ``ZTronUnitSize``). Across spellings: a
/// filled axis is the fraction 1 and a fraction of 0 is the length 0, so
/// `.fillMaxWidth(height: .relative(0.3)) == .relative(width: 1, height: 0.3)`,
/// `.fillMaxHeight(width: .relative(1)) == .relative(.full)` and `.relative(.zero) == .absolute(.zero)`.
/// ``fillMaxSize`` is none of these: it ignores the anchors, so `.fillMaxSize != .relative(.full)`.
///
/// Before the unit types this was an enum; its spellings `.fillMaxSize`, `.ideal`, `.fillMaxWidth()`,
/// `.fillMaxWidth(16 / 9)`, `.fillMaxHeight(_:)` and `.absolute(CGSize)` still compile and mean the same, except for an
/// aspect ratio so extreme that the free length overflows: once an infinite frame, now 0 on that axis
/// (``ZTronContentOverlayLength/aspectRatio(_:)``). `.relative(CGSize)` is now `.relative(ZTronUnitSize(size))`
/// (components clamped to `0...1`: `+infinity` is 1, no longer 0). A `switch` over the old cases no longer compiles:
/// compare with `==` instead.
public struct ZTronContentOverlaySize: Equatable, Sendable {
    /// The resolved shape in canonical form, built only by the normalizing constructors below, so that `==` is "draws
    /// the same frame for every content size": ``fillMaxSize``, or one ``ZTronContentOverlayLength/normalized`` length
    /// per axis. A filled axis is `.relative(.full)`; `.aspectRatio(r)` occurs only opposite a filled axis and reads
    /// from it (width `H · r`, height `W / r`).
    enum Kind: Equatable, Sendable {
        case fillMaxSize
        case axes(width: ZTronContentOverlayLength, height: ZTronContentOverlayLength)
    }

    let kind: Kind

    private init(_ kind: Kind) { self.kind = kind }

    /// The whole content rect (the default of `size:`): the overlay covers the content exactly, `anchor` and
    /// `overlayAnchor` are ignored, and a view that takes less is centred in it — SwiftUI's own `.overlay` applied to the
    /// content. A `.counterScaled` one scales about the content's centre.
    public static let fillMaxSize = ZTronContentOverlaySize(.fillMaxSize)

    /// The view's ideal size on both axes (`fixedSize()`): a small marker, a label at its natural size.
    public static let ideal = ZTronContentOverlaySize(.axes(width: .ideal, height: .ideal))

    /// Width = the content's width; height = width / `aspectRatio` (width over height, as SwiftUI's `aspectRatio`:
    /// `.fillMaxWidth(16 / 9)` is `W × 9W/16`; 0 if that overflows). `nil`, zero, negative or non-finite: the view's
    /// own height at width `W` (wrapped text).
    ///
    /// Sugar for ``fillMaxWidth(height:)``: `.fillMaxWidth(r)` is `.fillMaxWidth(height: .aspectRatio(r))` and
    /// `.fillMaxWidth()` is `.fillMaxWidth(height: .ideal)`, equal values.
    public static func fillMaxWidth(_ aspectRatio: CGFloat? = nil) -> Self {
        fillMaxWidth(height: aspectRatio.map { .aspectRatio($0) } ?? .ideal)
    }

    /// Width = the content's width `W`; the height per `height`: ``ZTronContentOverlayLength/ideal`` the view's own
    /// height at width `W`, ``ZTronContentOverlayLength/aspectRatio(_:)`` `W / r` (0 if that overflows),
    /// ``ZTronContentOverlayLength/absolute(_:)`` that many points, ``ZTronContentOverlayLength/relative(_:)`` that
    /// fraction of the content's height `H` (so `.fillMaxWidth(height: .relative(k))` is `.relative(width: 1, height: k)`).
    public static func fillMaxWidth(height: ZTronContentOverlayLength) -> Self {
        ZTronContentOverlaySize(.axes(width: .relative(.full), height: height.normalized))
    }

    /// Height = the content's height; width = height × `aspectRatio` (0 if that overflows). `nil`, zero, negative or
    /// non-finite: the view's own width at height `H`.
    ///
    /// Sugar for ``fillMaxHeight(width:)``: `.fillMaxHeight(r)` is `.fillMaxHeight(width: .aspectRatio(r))` and
    /// `.fillMaxHeight()` is `.fillMaxHeight(width: .ideal)`, equal values.
    public static func fillMaxHeight(_ aspectRatio: CGFloat? = nil) -> Self {
        fillMaxHeight(width: aspectRatio.map { .aspectRatio($0) } ?? .ideal)
    }

    /// Height = the content's height `H`; the width per `width`: ``ZTronContentOverlayLength/ideal`` the view's own
    /// width at height `H`, ``ZTronContentOverlayLength/aspectRatio(_:)`` `H · r` (0 if that overflows),
    /// ``ZTronContentOverlayLength/absolute(_:)`` that many points, ``ZTronContentOverlayLength/relative(_:)`` that
    /// fraction of the content's width `W` (so `.fillMaxHeight(width: .relative(k))` is `.relative(width: k, height: 1)`).
    public static func fillMaxHeight(width: ZTronContentOverlayLength) -> Self {
        ZTronContentOverlaySize(.axes(width: width.normalized, height: .relative(.full)))
    }

    /// A fraction of the content's size per axis: `(W · size.width, H · size.height)`, each fraction in `0...1`
    /// (``ZTronUnitSize`` clamps).
    public static func relative(_ size: ZTronUnitSize) -> Self {
        ZTronContentOverlaySize(.axes(width: ZTronContentOverlayLength.relative(ZTronUnitLength(size.width)).normalized,
                                      height: ZTronContentOverlayLength.relative(ZTronUnitLength(size.height)).normalized))
    }

    /// A fraction of the content's size per axis: `(W · width, H · height)`, each fraction in `0...1`
    /// (``ZTronUnitLength`` clamps; literals work: `.relative(width: 0.5, height: 0.2)`).
    public static func relative(width: ZTronUnitLength, height: ZTronUnitLength) -> Self {
        relative(ZTronUnitSize(width: width.value, height: height.value))
    }

    /// A fixed size in unscaled content points, independent of the content's size (only the origin follows it).
    /// Negative or non-finite components become 0.
    public static func absolute(_ size: CGSize) -> Self {
        ZTronContentOverlaySize(.axes(width: ZTronContentOverlayLength.absolute(size.width).normalized,
                                      height: ZTronContentOverlayLength.absolute(size.height).normalized))
    }
}

/// How a content-integral overlay draws under zoom.
public enum ZTronContentOverlayScaling: Equatable, Sendable {
    /// The overlay is part of the content: it scales with the zoom (the default).
    case withContent
    /// The overlay keeps a constant on-screen size (``SwiftUI/View/ztronScrollCounterScaled(anchor:)``): its frame is
    /// still resolved in the content space and its `overlayAnchor` point stays on the content point `anchor`, but it is
    /// drawn scaled by `1 / zoomScale` around that point. With ``ZTronContentOverlaySize/fillMaxSize`` (anchors
    /// ignored) it scales about the content's centre. During a rotation at the fitting scale the content's drawn scale is
    /// resolved frame by frame while the committed zoom holds its value, so a counter-scaled overlay may differ slightly
    /// in size mid-rotation; it lands exact.
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
    /// Set when the user's view is `Equatable`: the host keeps the previous erased view while the new value is `==` to it.
    var equality: ContentOverlayEquality? = nil

    /// One call's declaration: the user's `view` wrapped once (`wrap`), with its `==` when it is `Equatable`.
    @MainActor
    init<V: View>(key: AnyHashable, anchor: ZTronContentOverlayAnchor, overlayAnchor: UnitPoint,
                  size: ZTronContentOverlaySize, scaling: ZTronContentOverlayScaling, content view: V) {
        self.key = key
        self.anchor = anchor
        self.overlayAnchor = overlayAnchor
        self.size = size
        self.scaling = scaling
        self.view = Self.wrap(view)
        self.equality = ContentOverlayEquality.make(view)
    }

    /// What layout needs (the view excluded).
    var placement: ContentOverlayPlacement {
        ContentOverlayPlacement(anchor: anchor, overlayAnchor: overlayAnchor, size: size)
    }

    /// The point a `.counterScaled` overlay scales about, in its own frame: `overlayAnchor` (the point pinned on the
    /// content), or the centre for `.fillMaxSize`, whose anchors are ignored (a view that takes less is centred).
    var counterScalePivot: UnitPoint {
        size == .fillMaxSize ? .center : overlayAnchor
    }

    /// The user's view in one unary leaf: several views in the builder stack like SwiftUI's `.overlay` content (an
    /// implicit `ZStack`), so each call is exactly one overlay.
    @MainActor
    static func wrap<V: View>(_ view: V) -> AnyView {
        AnyView(ContentOverlayLeaf(content: view))
    }
}

/// The erased overlay's root (DEBUG counter `contentOverlay.body`). Its only input is the user's view, so SwiftUI
/// evaluates it exactly when it would evaluate that view again (a changed input) and never otherwise: not on motion,
/// refresh or collapse, not on a content-size change (layout re-places it), not on a container evaluation that hands
/// it an equal view. The counter therefore reads "the user's overlay body ran".
struct ContentOverlayLeaf<V: View>: View {
    let content: V

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("contentOverlay.body")
        #endif
        return ZStack { content }
    }
}

/// The `==` of an `Equatable` overlay, type-erased. `EquatableView` alone does not gate a body inside `AnyView`: measured
/// in M6b L1, an `AnyView(EquatableView(v))` rebuilt with an equal value re-ran `v`'s body on a parent re-evaluation on
/// iOS 17.5 and 27.0 (on 27.0 even a bare `EquatableView` did), so the host compares the values itself and hands SwiftUI
/// the very same `AnyView` when they are equal (`ContentOverlayViewCache`), which SwiftUI does not diff at all. Detected
/// at the call (`make`), so the public API is the single SPEC S11 overload per name: a `Text`, an `Image` or a `Color`
/// (all `Equatable`) takes this path too.
struct ContentOverlayEquality {
    let value: Any
    let isEqual: (Any) -> Bool

    init<V: Equatable>(_ value: V) {
        self.value = value
        self.isEqual = { ($0 as? V) == value }
    }

    /// The `==` of `view` when its type is `Equatable`, else `nil`.
    static func make<V>(_ view: V) -> ContentOverlayEquality? {
        guard let equatable = view as? any Equatable else { return nil }
        return opened(equatable)
    }

    private static func opened<E: Equatable>(_ value: E) -> ContentOverlayEquality { ContentOverlayEquality(value) }
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
