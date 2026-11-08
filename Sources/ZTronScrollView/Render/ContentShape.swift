import SwiftUI
import ZTronScrollPhysics

/// D75: the content's shape, the inputs of its alignment padding other than the viewport, the insets and the zoom: its
/// unscaled size, its alignment and the header's lift alignment (`ContentAlignment`). The animatable data of
/// `ContentShapeShift`.
struct ContentShape: VectorArithmetic {
    var width: CGFloat = 0, height: CGFloat = 0
    var ax: CGFloat = 0, ay: CGFloat = 0
    var liftY: CGFloat = 0

    init(width: CGFloat = 0, height: CGFloat = 0, ax: CGFloat = 0, ay: CGFloat = 0, liftY: CGFloat = 0) {
        self.width = width; self.height = height; self.ax = ax; self.ay = ay; self.liftY = liftY
    }

    init(size: CGSize, alignment: ContentAlignment) {
        self.init(width: size.width, height: size.height, ax: alignment.content.x, ay: alignment.content.y,
                  liftY: alignment.liftY)
    }

    var size: CGSize { CGSize(width: max(0, width), height: max(0, height)) }
    var alignment: UnitPoint { UnitPoint(x: ax, y: ay) }

    static var zero: ContentShape { ContentShape() }
    static func + (l: Self, r: Self) -> Self {
        Self(width: l.width + r.width, height: l.height + r.height, ax: l.ax + r.ax, ay: l.ay + r.ay,
             liftY: l.liftY + r.liftY)
    }
    static func - (l: Self, r: Self) -> Self {
        Self(width: l.width - r.width, height: l.height - r.height, ax: l.ax - r.ax, ay: l.ay - r.ay,
             liftY: l.liftY - r.liftY)
    }
    mutating func scale(by rhs: Double) {
        let k = CGFloat(rhs)
        width *= k; height *= k; ax *= k; ay *= k; liftY *= k
    }
    var magnitudeSquared: Double {
        Double(width * width + height * height + ax * ax + ay * ay + liftY * liftY)
    }
}

/// D75 (design M8b-s8-d75 §2.2 item 2): the content's shape as an animatable attribute of its own, right outside
/// `ContentTransform` in `TransformHost`. `ContentTransform` draws the alignment padding from the COMMITTED shape (the
/// committed content size and the published alignment); this effect adds `pad(shape drawn) − pad(shape committed)`, so the
/// drawn padding is the one of the shape SwiftUI interpolates: a content-size or alignment change adopted in an animated
/// transaction (`ZTronScrollState.setContentSize`, `alignmentChanged()`) moves fitting content on the change's curve
/// instead of in one frame.
///
/// Why an attribute of its own and not a pair with `ContentTransform`'s `TransformVector`: the finger and the clock write
/// that vector unanimated every frame (a pull, a bounce, a hold release), and on 27.0 an unanimated write cancels the
/// in-flight animation of the attribute it lands on; the shape's inputs exclude the offset, so those writes never touch
/// this animation (rows inserted while a bounce or a hold release runs keep their curve). The zoom and the insets are
/// plain inputs (a pinch or an inset change re-evaluates it with its animatable data unchanged). Not pinned by a catch
/// (D79, C10): a content-size animation runs through a catch, as UIKit's content size changes do.
///
/// 0 while a resize draws (the resize's reflow is the commit's, D17) and whenever the drawn shape is the committed one, so
/// at rest it is the identity, bit for bit.
struct ContentShapeShift: GeometryEffect {
    /// The drawn (interpolated) shape.
    var shape: ContentShape
    /// The committed shape (what `ContentTransform` draws its padding from).
    let committed: ContentShape
    let scale: CGFloat
    let insets: EdgeInsets
    let commit: ResizeCommit

    var animatableData: ContentShape {
        get { shape }
        set { shape = newValue }
    }

    /// `ContentTransform.isPlainFrame` with this effect's (plain) insets: no resize in flight and `size` the committed
    /// viewport within a pixel, or the viewport not known yet.
    func isPlainFrame(size: CGSize) -> Bool {
        let cur = commit.current
        let t = ContentTransform.pixelTolerance
        return cur.viewport.width <= 0 || cur.viewport.height <= 0
            || (!commit.isOpen && abs(size.width - cur.viewport.width) <= t && abs(size.height - cur.viewport.height) <= t
                && abs(insets.top - cur.insets.top) <= t && abs(insets.leading - cur.insets.leading) <= t
                && abs(insets.bottom - cur.insets.bottom) <= t && abs(insets.trailing - cur.insets.trailing) <= t)
    }

    /// The alignment padding of `shape` minus that of the committed shape, at `size`.
    func delta(size: CGSize) -> CGPoint {
        guard shape != committed, isPlainFrame(size: size) else { return .zero }
        let cur = commit.current
        let v = cur.viewport.width <= 0 || cur.viewport.height <= 0 ? size : cur.viewport
        let a = ResizeMath.geometry(viewport: v, content: shape.size, insets: insets, alignment: shape.alignment)
            .alignmentPadding(at: scale)
        let b = ResizeMath.geometry(viewport: v, content: committed.size, insets: insets, alignment: committed.alignment)
            .alignmentPadding(at: scale)
        return CGPoint(x: a.x - b.x, y: a.y - b.y)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let d = delta(size: size)
        return ProjectionTransform(CGAffineTransform(translationX: d.x, y: d.y))
    }
}
