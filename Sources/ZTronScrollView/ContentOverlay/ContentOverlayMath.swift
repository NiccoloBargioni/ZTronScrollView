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

    /// Negative or non-finite → 0, a caller's absolute length (`subject` names it): in DEBUG builds a changed value is
    /// reported once per subject, site and value (−0 is unchanged). In range, one extra comparison in DEBUG builds only.
    static func nonNegative(_ v: CGFloat, _ subject: StaticString, _ site: ZTronDiagnostics.Site) -> CGFloat {
        let n = nonNegative(v)
        #if DEBUG
        if n != v {   // NaN included (NaN != 0)
            ZTronDiagnostics.report(.absoluteLengthZeroed, subject, "is negative or not finite", bits: v, site: site,
                                    input: "\(v)", result: "\(n)")
        }
        #endif
        return n
    }

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
        case .relative(let p): return p.unitPoint   // clamped to 0...1 when it was built
        case .absolute: return nil
        }
    }

    /// `P`: the anchor's point in the unscaled content rect. `site` = the modifier call (DEBUG reports).
    static func anchorPoint(_ anchor: ZTronContentOverlayAnchor, content: CGSize,
                            at site: ZTronDiagnostics.CallSite = .unlocated) -> CGPoint {
        let c = sanitized(content)
        if case .absolute(let a) = anchor { return absolutePoint(a, at: site) }
        let u = unitPoint(anchor) ?? .topLeading
        return CGPoint(x: c.width * u.x, y: c.height * u.y)
    }

    /// An `.absolute` anchor's point, non-finite components → 0: in DEBUG builds each one is reported (`at layout`, with
    /// the modifier call's location) once per call and component value; the other component, healthy and possibly
    /// changing every frame, is in the message but not in the key. Finite: the same two checks `finite` makes.
    static func absolutePoint(_ a: CGPoint, at site: ZTronDiagnostics.CallSite = .unlocated) -> CGPoint {
        if a.x.isFinite && a.y.isFinite { return a }
        #if DEBUG
        if !a.x.isFinite {
            ZTronDiagnostics.report(.anchorNotFinite, "ZTronContentOverlayAnchor.absolute x", "is not finite", bits: a.x,
                                    site: site.site, input: "\(a.x) in .absolute(\(a))", result: "0.0")
        }
        if !a.y.isFinite {
            ZTronDiagnostics.report(.anchorNotFinite, "ZTronContentOverlayAnchor.absolute y", "is not finite", bits: a.y,
                                    site: site.site, input: "\(a.y) in .absolute(\(a))", result: "0.0")
        }
        #endif
        return CGPoint(x: finite(a.x), y: finite(a.y))
    }

    /// An overlay's `overlayAnchor`, non-finite components → 0: in DEBUG builds each one is reported (`at layout`, with
    /// the modifier call's location; the argument is stored, then resolved here) once per call and component value,
    /// keyed on that component only. Finite: two checks, nothing more.
    static func finiteOverlayAnchor(_ q: UnitPoint, at site: ZTronDiagnostics.CallSite = .unlocated) -> UnitPoint {
        if q.x.isFinite && q.y.isFinite { return q }
        #if DEBUG
        if !q.x.isFinite {
            ZTronDiagnostics.report(.overlayAnchorNotFinite, "scrollContentIntegralOverlay overlayAnchor.x", "is not finite",
                                    bits: q.x, site: site.site,
                                    input: "\(q.x) in UnitPoint(x: \(q.x), y: \(q.y))", result: "0.0")
        }
        if !q.y.isFinite {
            ZTronDiagnostics.report(.overlayAnchorNotFinite, "scrollContentIntegralOverlay overlayAnchor.y", "is not finite",
                                    bits: q.y, site: site.site,
                                    input: "\(q.y) in UnitPoint(x: \(q.x), y: \(q.y))", result: "0.0")
        }
        #endif
        return UnitPoint(x: finite(q.x), y: finite(q.y))
    }

    /// A usable aspect ratio (width / height), or `nil` (absent, zero, negative or non-finite; design M6b §1 "Degenerate
    /// inputs"). Pure: `ZTronContentOverlayLength.normalized`, which calls it when a size is built (so a size never
    /// holds an unusable ratio), reports an unusable one with the constructor's caller.
    static func aspect(_ ratio: CGFloat?) -> CGFloat? {
        guard let r = ratio, r.isFinite, r > 0 else { return nil }
        return r
    }

    /// `S`: the proposal `size` makes for a content of `content`. `site` = the modifier call (DEBUG reports).
    static func proposal(_ size: ZTronContentOverlaySize, content: CGSize,
                         at site: ZTronDiagnostics.CallSite = .unlocated) -> OverlayProposal {
        let c = sanitized(content)
        switch size.kind {
        case .fillMaxSize:
            return OverlayProposal(width: c.width, height: c.height)
        case .axes(let width, let height):
            // An aspect ratio sits opposite a filled axis (the constructors): width = H · r, height = W / r.
            return OverlayProposal(width: axisLength(width, sameAxis: c.width, axis: .horizontal, at: site) { c.height * $0 },
                                   height: axisLength(height, sameAxis: c.height, axis: .vertical, at: site) { c.width / $0 })
        }
    }

    /// One axis of a size: `nil` (unspecified) for `.ideal`; `sameAxis` = the content's length on that axis (what
    /// `.relative` scales; a filled axis is `.relative(.full)`); `fromRatio(r)` = the length an aspect ratio gives from
    /// the filled other axis; `axis` = this axis and `site` = the modifier call (DEBUG report). Defensive on values the
    /// normalizing constructors already exclude. A ratio whose length overflows counts as 0, never an infinite frame; in
    /// DEBUG builds that is reported once per call, ratio and axis (`at layout`), however many layout passes or content
    /// sizes overflow it.
    static func axisLength(_ length: ZTronContentOverlayLength, sameAxis: CGFloat, axis: Axis = .vertical,
                           at site: ZTronDiagnostics.CallSite = .unlocated,
                           fromRatio: (CGFloat) -> CGFloat) -> CGFloat? {
        switch length {
        case .ideal:
            return nil
        case .aspectRatio(let r):
            guard r.isFinite, r > 0 else { return nil }
            let v = fromRatio(r)
            guard v.isFinite else {
                #if DEBUG
                if axis == .vertical {
                    ZTronDiagnostics.report(.aspectRatioOverflow, "ZTronContentOverlaySize.fillMaxWidth(height: .aspectRatio) height",
                                            "overflows (W / r)", bits: r, site: site.site,
                                            input: ".fillMaxWidth(height: .aspectRatio(\(r)))", result: "0.0")
                } else {
                    ZTronDiagnostics.report(.aspectRatioOverflow, "ZTronContentOverlaySize.fillMaxHeight(width: .aspectRatio) width",
                                            "overflows (H · r)", bits: r, site: site.site,
                                            input: ".fillMaxHeight(width: .aspectRatio(\(r)))", result: "0.0")
                }
                #endif
                return 0
            }
            return nonNegative(v)
        case .absolute(let v):
            return nonNegative(v)
        case .relative(let k):
            return sameAxis * k.value
        }
    }

    /// `f`: `S` on the specified axes, the view's own size at `S` on the others (`measure` runs only if an axis is open).
    static func frameSize(_ proposal: OverlayProposal, measure: (OverlayProposal) -> CGSize) -> CGSize {
        if let w = proposal.width, let h = proposal.height { return CGSize(width: w, height: h) }
        let own = measure(proposal)
        return CGSize(width: proposal.width ?? nonNegative(own.width), height: proposal.height ?? nonNegative(own.height))
    }

    /// origin = `P − q · f` (a non-finite `q` component counts as 0, reported in DEBUG builds: `finiteOverlayAnchor`).
    static func origin(anchorPoint p: CGPoint, overlayAnchor q: UnitPoint, frame f: CGSize,
                       at site: ZTronDiagnostics.CallSite = .unlocated) -> CGPoint {
        let q = finiteOverlayAnchor(q, at: site)
        return CGPoint(x: p.x - q.x * f.width, y: p.y - q.y * f.height)
    }

    /// The overlay's frame in the unscaled content space. An overlay larger than the content keeps its negative origin.
    static func resolve(_ placement: ContentOverlayPlacement, content: CGSize,
                        measure: (OverlayProposal) -> CGSize) -> CGRect {
        let c = sanitized(content)
        if placement.size == .fillMaxSize { return CGRect(origin: .zero, size: c) }
        let site = placement.site
        let f = frameSize(proposal(placement.size, content: c, at: site), measure: measure)
        let o = origin(anchorPoint: anchorPoint(placement.anchor, content: c, at: site), overlayAnchor: placement.overlayAnchor,
                       frame: f, at: site)
        return CGRect(origin: o, size: f)
    }
}
