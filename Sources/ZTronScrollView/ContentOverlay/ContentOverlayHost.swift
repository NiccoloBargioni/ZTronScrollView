import SwiftUI

// The content-integral overlay host (design M6b §2). `ScrollContainer` applies it as the FIRST modifier on the content
// (`content.overlay(alignment: .topLeading) { ContentOverlayHost(…) }`), so it is laid out from the content's own size in
// the same layout pass, under the transform and inside both named content spaces. Placement is layout, not state: the
// host reads no metrics, no offset, no zoom and subscribes to no channel, so scrolling, zooming, refreshing and header
// collapse (render-time transforms above it) run neither its body nor `placeSubviews` nor any overlay body. A content
// size change (a reflow on rotation, a growing list) re-places the overlays by layout; SwiftUI animates such a reflow by
// interpolating view frames between the two layouts under the ambient transaction, so an overlay follows the content's
// drawn geometry with the content's own curve. No animation of its own.

struct ContentOverlayHost: View {
    let state: ZTronScrollState
    let decls: [ContentOverlayDecl]
    /// Created once per identity (`@StateObject`'s autoclosure): no allocation per container evaluation. Never publishes.
    @StateObject private var cache = ContentOverlayViewCache()

    var body: some View {
        // An `Equatable` overlay equal to the one shown keeps its `AnyView`: its body does not run again.
        let decls = cache.stabilized(self.decls)
        #if DEBUG
        ZTronRenderCounters.increment("contentOverlay.host.body")
        if !decls.isEmpty {   // the resolved order (twins first, then members), for tests
            ZTronRenderCounters.notes["contentOverlay.order"] = decls.map { "\($0.key.base)" }.joined(separator: ",")
        }
        #endif
        // Empty: nothing at all (no reader, no layout pass). The path is a `let` flag fixed at state creation (R6).
        return Group {
            if !decls.isEmpty {
                if state.usesLayoutProtocol, #available(iOS 16, *) {
                    ContentOverlayLayout {
                        ForEach(decls, id: \.key) { d in
                            d.view
                                // A view that takes less than its frame is centred in it: on an axis the proposal
                                // specifies, this frame adopts exactly the proposal (both bounds given); on an
                                // unspecified one it adopts the view's own size.
                                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                .modifier(CounterScaleLeaf(state: state, anchor: d.overlayAnchor,
                                                           isActive: d.scaling == .counterScaled))
                                .layoutValue(key: ContentOverlayPlacementKey.self, value: d.placement)
                        }
                    }
                } else {
                    ContentOverlayReaderHost(state: state, decls: decls)
                }
            }
        }
    }
}

// MARK: 16+: Layout

@available(iOS 16, *)
struct ContentOverlayPlacementKey: LayoutValueKey {
    static let defaultValue = ContentOverlayPlacement(anchor: .center, overlayAnchor: .topLeading, size: .fillMaxSize)
}

/// Takes the proposal (the content's size, from `.overlay`) and places each overlay at its resolved frame. Caches nothing:
/// every input is the proposal and the subviews, so nothing can go stale.
@available(iOS 16, *)
struct ContentOverlayLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        #if DEBUG
        if Thread.isMainThread { MainActor.assumeIsolated { ZTronRenderCounters.increment("contentOverlay.place") } }
        #endif
        for sub in subviews {
            let r = ContentOverlayMath.resolve(sub[ContentOverlayPlacementKey.self], content: bounds.size) { p in
                sub.sizeThatFits(ProposedViewSize(width: p.width, height: p.height))
            }
            sub.place(at: CGPoint(x: bounds.minX + r.minX, y: bounds.minY + r.minY), anchor: .topLeading,
                      proposal: ProposedViewSize(width: r.width, height: r.height))
        }
    }
}

// MARK: 15 (and forced fallbacks): GeometryReader + alignment guides

/// The reader's closure runs once per layout size of the content (a reflow), never on motion: the transform above it
/// is a render-time effect, which does not re-run a `GeometryReader` that reads only its size (measured, M6b step 0,
/// `ContentOverlayTests.geometryReaderUnderTransformClosureRuns`, iOS 17.5 and 27.0, both paths). Each overlay sits in
/// the overlay of a content-sized clear base, so an overlay larger than the content keeps its negative origin; its frame
/// is `S` (`frame(width:height:)`, a smaller view centred) with `fixedSize` on the unspecified axes, and its alignment
/// guides put `q · f` on `P` with the view's own dimensions, so no measurement pass and no state are involved.
struct ContentOverlayReaderHost: View {
    let state: ZTronScrollState
    let decls: [ContentOverlayDecl]

    var body: some View {
        GeometryReader { g in
            let content = g.size
            #if DEBUG
            let _ = ZTronRenderCounters.increment("contentOverlay.host.body")
            #endif
            ZStack(alignment: .topLeading) {
                ForEach(decls, id: \.key) { d in
                    let fill = d.size == .fillMaxSize
                    let s = ContentOverlayMath.proposal(d.size, content: content)
                    let p = fill ? CGPoint.zero : ContentOverlayMath.anchorPoint(d.anchor, content: content)
                    let q = fill ? UnitPoint.topLeading
                                 : UnitPoint(x: ContentOverlayMath.finite(d.overlayAnchor.x),
                                             y: ContentOverlayMath.finite(d.overlayAnchor.y))
                    // The clear base never takes a touch (the overlay above it does).
                    Color.clear.allowsHitTesting(false).overlay(alignment: .topLeading) {
                        d.view
                            .frame(width: s.width, height: s.height)
                            .fixedSize(horizontal: s.width == nil, vertical: s.height == nil)
                            .modifier(CounterScaleLeaf(state: state, anchor: d.overlayAnchor,
                                                       isActive: d.scaling == .counterScaled))
                            .alignmentGuide(.leading) { v in q.x * v.width - p.x }
                            .alignmentGuide(.top) { v in q.y * v.height - p.y }
                    }
                }
            }
        }
    }
}
