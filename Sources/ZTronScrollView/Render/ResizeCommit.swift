import SwiftUI

/// What the transform effect needs to map the animated viewport `size` to an offset/scale (design M5 section 2). Cold;
/// lives in `ScrollMetrics`, so a commit publishes on `.metrics` once.
struct ResizeCommit: Equatable, Sendable {
    struct Snapshot: Equatable, Sendable {
        var viewport: CGSize = .zero
        var contentSize: CGSize = .zero
        var insets: EdgeInsets = EdgeInsets()
        /// The scaling header's resize geometry in this snapshot (M8b-3; `nil` without a header driven by the vertical
        /// offset): what keeps its collapse progress across the resize (SPEC S7).
        var header: HeaderResize?
    }
    struct Paging: Equatable, Sendable {
        var x: Int?
        var y: Int?
    }
    /// The geometry the committed target values are expressed in.
    var current = Snapshot()
    /// The geometry the transition started from (== `current` unless the viewport size changed).
    var previous = Snapshot()
    /// Scaling-header height at commit (unobscured center only).
    var header: CGFloat = 0
    /// What the resize preserves (D17, ZTronMapKit geometry): the normalized centre of the zoomed content and the scale.
    /// Sticky across consecutive resizes (`ZTronScrollState.resizeIntent`); nil once the commit is closed.
    var intent: ResizeIntent?
    /// Page kept current when paging is enabled.
    var pagingIndex = Paging()
    /// The point of the unobscured rect that is preserved (center unless `defaultScrollAnchor(for: .sizeChanges)`).
    var focus = UnitPoint.center
    /// `stepFallback` and `outer` (M8b-s6), rare: behind one immutable reference, nil unless one is set, so the commit's
    /// inline value (copied into the transform effect on every evaluation and compared by SwiftUI) keeps the layout it had
    /// before them plus one pointer, with no new padding. Stored inline, they nearly doubled it and put 7 padding bytes
    /// after `isOpen`; with that layout the content overlay's `Layout` was placed on every frame of a pinch after a
    /// rotation round trip (27.0 preferred under load: 51–67 placements, bound 2; ContentOverlayUITests). Inferred
    /// mechanism: SwiftUI's byte compare of a value whose comparison layout is not ready yet (D43).
    private var tracks: Tracks?
    /// True from the commit until `closeResize()`; the effect clamps while open.
    var isOpen = false

    /// A safe-area step committed before it is drawn (`ZTronScrollState.stepDrawn`): at exactly `size`, the drawn size of
    /// the frame that still lacks the step, the track before the step is drawn (`ResizeMath.track`).
    var stepFallback: StepFallback? {
        get { tracks?.stepFallback }
        set { tracks = Tracks.make(stepFallback: newValue, outer: outer) }
    }
    /// The track of the transition this commit retargeted while it was still drawn in motion (a second `withAnimation`
    /// while the first runs; nil otherwise). SwiftUI composes the two animations additively, so the drawn size first keeps
    /// moving on the old track, past this commit's snapshot: a size drawn outside this commit's own span (`t < 0` or
    /// `t > 1`) is continued from the nearer end along this track's slope (`ResizeMath.presented`), never along this
    /// commit's chord, whose slope has no bound when the new target is near the drawn size.
    var outer: Segment? {
        get { tracks?.outer }
        set { tracks = Tracks.make(stepFallback: stepFallback, outer: newValue) }
    }

    /// A (previous, current) pair of snapshots: a track the drawn size moves along.
    struct Segment: Equatable, Sendable {
        var previous: Snapshot
        var current: Snapshot
    }

    struct StepFallback: Equatable, Sendable {
        var size: CGSize
        var previous: Snapshot
        var current: Snapshot
        /// The open commit's `outer` before the step.
        var outer: Segment?
    }

    /// Immutable: a write makes a new one (never mutated in place behind a value SwiftUI holds). Equal by contents.
    final class Tracks: Equatable, Sendable {
        let stepFallback: StepFallback?
        let outer: Segment?

        private init(stepFallback: StepFallback?, outer: Segment?) {
            self.stepFallback = stepFallback
            self.outer = outer
        }

        static func make(stepFallback: StepFallback?, outer: Segment?) -> Tracks? {
            stepFallback == nil && outer == nil ? nil : Tracks(stepFallback: stepFallback, outer: outer)
        }

        static func == (a: Tracks, b: Tracks) -> Bool {
            a === b || (a.stepFallback == b.stepFallback && a.outer == b.outer)
        }
    }
}
