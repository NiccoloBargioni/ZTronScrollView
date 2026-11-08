import SwiftUI
import Testing
import ZTronScrollPhysics
@testable import ZTronScrollView

/// C-F2 (M8b-s8 fixer): a resize that opens while a D75 content-size or `fittingContent:` animation is in flight keeps the
/// shape's remaining `pad(drawn) − pad(committed)` (`ContentShapeShift.delta` on the presented geometry) and lands it on
/// the shape's curve; the drawn translation (`ContentTransform` + `ContentShapeShift`) has no step at the resize's first
/// frame, the shift is 0 once the shape reached the committed one, and the lift's shift (`HeaderLiftShift`'s difference)
/// follows the same rule.
@MainActor
@Suite(.serialized)
struct ContentShapeResizeTests {
    static let center = ContentAlignment(content: .center, liftY: 0)

    static func drawnTY(commit: ResizeCommit, drawn: ContentShape, committed: ContentShape, size: CGSize) -> CGFloat {
        let t = ContentTransform(offset: .zero, scale: 1, insets: commit.current.insets, commit: commit, limits: ZoomLimits(),
                                 alignment: committed.alignment, paging: [], probe: nil)
        let s = ContentShapeShift(shape: drawn, committed: committed, scale: 1, insets: commit.current.insets, commit: commit)
        return t.effectValue(size: size).m32 + s.effectValue(size: size).m32
    }

    static func setup(newViewport: CGSize, newContent: CGSize)
        -> (closed: ResizeCommit, open: ResizeCommit, committed: ContentShape, vp: CGSize) {
        let vp = CGSize(width: 400, height: 800)
        let committed = ContentShape(size: CGSize(width: 400, height: 600), alignment: center)
        var closed = ResizeCommit()
        closed.current = .init(viewport: vp, contentSize: committed.size, insets: EdgeInsets())
        closed.previous = closed.current
        var open = ResizeCommit()
        open.previous = closed.current
        open.current = .init(viewport: newViewport, contentSize: newContent, insets: EdgeInsets())
        open.focus = .center
        open.isOpen = true
        open.intent = ResizeMath.intent(offset: .zero, scale: 1, in: closed.current, header: 0, focus: .center,
                                        alignment: committed.alignment)
        return (closed, open, committed, vp)
    }

    @Test(arguments: [(CGSize(width: 800, height: 400), CGSize(width: 800, height: 600)),
                      (CGSize(width: 300, height: 800), CGSize(width: 300, height: 600)),
                      (CGSize(width: 400, height: 700), CGSize(width: 400, height: 600))])
    func aResizeOpeningMidShapeAnimationKeepsTheShapesRemainder(viewport: CGSize, content: CGSize) {
        let r = Self.setup(newViewport: viewport, newContent: content)
        // The shape mid-way through 200 -> 600 rows.
        let drawn = ContentShape(size: CGSize(width: 400, height: 400), alignment: Self.center)
        let before = Self.drawnTY(commit: r.closed, drawn: drawn, committed: r.committed, size: r.vp)
        let first = Self.drawnTY(commit: r.open, drawn: drawn, committed: r.committed, size: r.vp)
        #expect(abs(first - before) <= 1, "one-frame step \(first - before) pt at the resize's first frame (\(viewport))")
        // Through the resize, the shape converging on the committed one: the shape's extra (drawn minus the resize's own
        // drawing) moves in steps of its own curve, never one frame, and is 0 once the shape is the committed one.
        var lastExtra = first - Self.drawnTY(commit: r.open, drawn: r.committed, committed: r.committed, size: r.vp)
        var worst: CGFloat = 0
        for i in 1...30 {
            let f = CGFloat(i) / 30
            let size = CGSize(width: r.vp.width + (viewport.width - r.vp.width) * f,
                              height: r.vp.height + (viewport.height - r.vp.height) * f)
            let s = ContentShape(size: CGSize(width: 400, height: 400 + 200 * min(1, f * 1.5)), alignment: Self.center)
            let extra = Self.drawnTY(commit: r.open, drawn: s, committed: r.committed, size: size)
                - Self.drawnTY(commit: r.open, drawn: r.committed, committed: r.committed, size: size)
            worst = max(worst, abs(extra - lastExtra))
            if f * 1.5 >= 1 { #expect(abs(extra) < 1e-6, "the shape at the committed one: the resize's own drawing (\(f))") }
            lastExtra = extra
        }
        #expect(abs(lastExtra) < 1e-6)
        #expect(worst <= 20, "the shape's remainder is spread over its curve, never one frame: worst step \(worst)")
    }

    @Test func atRestAndWithoutAShapeAnimationTheShiftIsTheIdentity() {
        let r = Self.setup(newViewport: CGSize(width: 800, height: 400), newContent: CGSize(width: 800, height: 600))
        let s = ContentShapeShift(shape: r.committed, committed: r.committed, scale: 1, insets: EdgeInsets(), commit: r.open)
        for w: CGFloat in [400, 500, 800] {
            #expect(s.delta(size: CGSize(width: w, height: 1200 - w)) == .zero)
        }
        let c = ContentShapeShift(shape: r.committed, committed: r.committed, scale: 1, insets: EdgeInsets(), commit: r.closed)
        #expect(c.delta(size: r.vp) == .zero)
    }

    @Test func theLiftsShiftKeepsTheRemainderToo() {
        let r = Self.setup(newViewport: CGSize(width: 800, height: 400), newContent: CGSize(width: 800, height: 600))
        let a = ContentAlignment(content: .center, liftY: 0.5)
        let committed = ContentShape(size: r.committed.size, alignment: a).lift
        let drawn = ContentShape(size: CGSize(width: 400, height: 400), alignment: a).lift
        let closed = ContentShapeShift(shape: drawn, committed: committed, scale: 1, insets: EdgeInsets(), commit: r.closed)
        let open = ContentShapeShift(shape: drawn, committed: committed, scale: 1, insets: EdgeInsets(), commit: r.open)
        let d0 = closed.delta(size: r.vp).y, d1 = open.delta(size: r.vp).y
        #expect(d0 != 0 && abs(d1 - d0) <= 1, "the lift's shape remainder at the resize's first frame: \(d0) -> \(d1)")
    }
}
