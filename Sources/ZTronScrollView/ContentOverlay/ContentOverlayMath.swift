import SwiftUI

/// A proposal with optional axes (`nil` = unspecified: the view's own size on that axis). `ProposedViewSize` is 16+.
struct OverlayProposal: Equatable, Sendable {
    var width: CGFloat?
    var height: CGFloat?
}

/// The pure placement rule of a content-integral overlay (design M6b §1), shared by both hosts.
///
/// `W × H` = the content's size; `P` = the anchor's content point; `q` = `overlayAnchor`; `S` = the proposal of `size`;
/// `f` = the frame (`S` on the specified axes, the view's own size at `S` on the others);
/// origin = `P − (q.x · f.width, q.y · f.height)`. `.fillMaxSize` is the content rect, whatever the anchors.
enum ContentOverlayMath {
    /// Non-finite → 0.
    static func finite(_ v: CGFloat) -> CGFloat { v.isFinite ? v : 0 }
    /// Negative or non-finite → 0.
    static func nonNegative(_ v: CGFloat) -> CGFloat { v.isFinite ? max(0, v) : 0 }

    static func sanitized(_ content: CGSize) -> CGSize {
        CGSize(width: nonNegative(content.width), height: nonNegative(content.height))
    }

    /// The `UnitPoint` a named or relative anchor stands for; `nil` for `.absolute`.
    static func unitPoint(_ anchor: ZTronContentOverlayAnchor) -> UnitPoint? {
        switch anchor {
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        case .relative(let p): return UnitPoint(x: finite(p.x), y: finite(p.y))
        case .absolute: return nil
        }
    }

    /// `P`: the anchor's point in the unscaled content rect.
    static func anchorPoint(_ anchor: ZTronContentOverlayAnchor, content: CGSize) -> CGPoint {
        let c = sanitized(content)
        if case .absolute(let a) = anchor { return CGPoint(x: finite(a.x), y: finite(a.y)) }
        let u = unitPoint(anchor) ?? .topLeading
        return CGPoint(x: c.width * u.x, y: c.height * u.y)
    }

    /// A usable aspect ratio (width / height), or `nil` (absent, zero, negative or non-finite).
    static func aspect(_ ratio: CGFloat?) -> CGFloat? {
        guard let r = ratio, r.isFinite, r > 0 else { return nil }
        return r
    }

    /// `S`: the proposal `size` makes for a content of `content`.
    static func proposal(_ size: ZTronContentOverlaySize, content: CGSize) -> OverlayProposal {
        let c = sanitized(content)
        switch size {
        case .fillMaxSize:
            return OverlayProposal(width: c.width, height: c.height)
        case .fillMaxWidth(let ratio):
            if let r = aspect(ratio) { return OverlayProposal(width: c.width, height: c.width / r) }
            return OverlayProposal(width: c.width, height: nil)
        case .fillMaxHeight(let ratio):
            if let r = aspect(ratio) { return OverlayProposal(width: c.height * r, height: c.height) }
            return OverlayProposal(width: nil, height: c.height)
        case .relative(let k):
            return OverlayProposal(width: c.width * nonNegative(k.width), height: c.height * nonNegative(k.height))
        case .absolute(let s):
            return OverlayProposal(width: nonNegative(s.width), height: nonNegative(s.height))
        case .ideal:
            return OverlayProposal(width: nil, height: nil)
        }
    }

    /// `f`: `S` on the specified axes, the view's own size at `S` on the others (`measure` runs only if an axis is open).
    static func frameSize(_ proposal: OverlayProposal, measure: (OverlayProposal) -> CGSize) -> CGSize {
        if let w = proposal.width, let h = proposal.height { return CGSize(width: w, height: h) }
        let own = measure(proposal)
        return CGSize(width: proposal.width ?? nonNegative(own.width), height: proposal.height ?? nonNegative(own.height))
    }

    /// origin = `P − q · f`.
    static func origin(anchorPoint p: CGPoint, overlayAnchor q: UnitPoint, frame f: CGSize) -> CGPoint {
        CGPoint(x: p.x - finite(q.x) * f.width, y: p.y - finite(q.y) * f.height)
    }

    /// The overlay's frame in the unscaled content space. An overlay larger than the content keeps its negative origin.
    static func resolve(_ placement: ContentOverlayPlacement, content: CGSize,
                        measure: (OverlayProposal) -> CGSize) -> CGRect {
        let c = sanitized(content)
        if case .fillMaxSize = placement.size { return CGRect(origin: .zero, size: c) }
        let f = frameSize(proposal(placement.size, content: c), measure: measure)
        let o = origin(anchorPoint: anchorPoint(placement.anchor, content: c), overlayAnchor: placement.overlayAnchor, frame: f)
        return CGRect(origin: o, size: f)
    }
}
