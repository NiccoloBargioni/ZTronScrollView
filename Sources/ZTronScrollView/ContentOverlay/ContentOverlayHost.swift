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

    /// Runs on a container body evaluation only (a parent re-render, a cold config change): never on motion, refresh,
    /// collapse or a content-size change (`contentOverlay.host.body`). The user's overlay bodies do not run with it
    /// unless their inputs changed (`contentOverlay.body`, counted by `ContentOverlayLeaf`).
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
                                .modifier(CounterScaleLeaf(state: state, anchor: d.counterScalePivot,
                                                           isActive: d.scaling == .counterScaled))
                                .layoutValue(key: ContentOverlayPlacementKey.self, value: d.placement)
                        }
                    }
                } else {
                    ContentOverlayReaderHost(state: state, decls: decls)
                }
            }
        }
        // The overlays are not content of this scroll view's twins: a `ZTronScrollView` drawn inside an overlay must not
        // draw the same twin overlays again (a twin holding a scroll view would nest without end). Only this subtree
        // loses them; the content, and the scroll views nested in it, keep them.
        .transformEnvironment(\.ztronScrollConfig) { $0.contentOverlays.removeAll() }
    }
}

// MARK: 16+: Layout

@available(iOS 16, *)
struct ContentOverlayPlacementKey: LayoutValueKey {
    static let defaultValue = ContentOverlayPlacement(anchor: .center, overlayAnchor: .topLeading, size: .fillMaxSize)
}

/// Takes the proposal (the content's size, from `.overlay`) and places each overlay at its resolved frame. Caches nothing
/// (a deviation from design M6b §2 / R3, which proposed a per-proposal cache): a rotation proposes a new content size
/// every frame, so such a cache would never hit while it matters, and measuring happens only on an axis the size leaves
/// open (`.ideal`, an `.ideal` free axis); without a cache nothing can go stale when a subview's ideal size changes.
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

/// The reader's closure (`contentOverlay.reader`) runs once per layout size of the content (every frame of an animated
/// reflow) and once per evaluation of this view (a container body evaluation hands it new `decls`, hence a new
/// closure); the overlays' bodies do not run with it (same views, no diff). Motion does not run it: the transform above
/// is a render-time effect, and a `GeometryReader` that reads only its size did not re-run its closure under it, nor
/// on the `.disabled` flips at motion start and end (measured, M6b L1: `geometryReaderUnderTransformClosureRuns` and
/// the motion / refresh tests, iOS 17.5 and 27.0 runtimes, both paths). This host ships on iOS 15 only, and the iOS 15
/// runtime itself is NOT measured (no iOS 15 simulator on this Mac); if its reader re-ran per motion frame, the
/// contingency is design §2's metrics-driven host on 15 only. Each overlay sits in the overlay of a content-sized
/// clear base, so an overlay larger than the content keeps its negative origin; its frame is `S`
/// (`frame(width:height:)`, a smaller view centred) with `fixedSize` on the unspecified axes, and its alignment guides
/// put `q · f` on `P` with the view's own dimensions, so no measurement pass and no state are involved.
struct ContentOverlayReaderHost: View {
    let state: ZTronScrollState
    let decls: [ContentOverlayDecl]

    var body: some View {
        GeometryReader { g in
            let content = g.size
            #if DEBUG
            let _ = ZTronRenderCounters.increment("contentOverlay.reader")
            #endif
            ZStack(alignment: .topLeading) {
                ForEach(decls, id: \.key) { d in
                    let fill = d.size == .fillMaxSize
                    let s = ContentOverlayMath.proposal(d.size, content: content, at: d.site)
                    let p = fill ? CGPoint.zero : ContentOverlayMath.anchorPoint(d.anchor, content: content, at: d.site)
                    let q = fill ? UnitPoint.topLeading : ContentOverlayMath.finiteOverlayAnchor(d.overlayAnchor, at: d.site)
                    // The clear base never takes a touch (the overlay above it does).
                    Color.clear.allowsHitTesting(false).overlay(alignment: .topLeading) {
                        d.view
                            .frame(width: s.width, height: s.height)
                            .fixedSize(horizontal: s.width == nil, vertical: s.height == nil)
                            .modifier(CounterScaleLeaf(state: state, anchor: d.counterScalePivot,
                                                       isActive: d.scaling == .counterScaled))
                            .alignmentGuide(.leading) { v in q.x * v.width - p.x }
                            .alignmentGuide(.top) { v in q.y * v.height - p.y }
                    }
                }
            }
        }
    }
}
