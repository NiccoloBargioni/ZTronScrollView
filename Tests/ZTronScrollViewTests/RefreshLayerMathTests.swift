import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// D80 (open item 27): on the path without layer groups (15–16, the forced fallbacks) a gap refresh indicator without a
/// layer group (a custom indicator, no scaling header: D65) is drawn in a slot BEHIND the content, every other indicator in
/// the front slot above the content and the header. Behind the content it needs no hiding: a system rotation that brings
/// its gap back cannot draw it over the content still sliding in, so D66 (hidden for 0.45 s after any resize that began
/// with nothing of it visible, an instant one included) is retired and an instant resize draws it at once, as 17+ do.
@MainActor
@Suite(.serialized)
struct RefreshLayerMathTests {
    // MARK: Pure

    /// Every kind × overlay × layer: exactly one slot draws each leaf, behind only for a gap indicator without a group.
    @Test func everyKindAndOverlayIsDrawnInExactlyOneSlot() {
        let behind: [(RefreshIndicatorGroup.Kind, Bool, Bool)] = [
            (.geometry, false, false), (.geometry, true, false),
            (.compositing, false, false), (.compositing, true, false),
            (.none, false, true), (.none, true, false),
        ]
        for (kind, overlay, isBehind) in behind {
            let b = RefreshLayerMath.draws(layer: .behind, kind: kind, overlay: overlay)
            let f = RefreshLayerMath.draws(layer: .front, kind: kind, overlay: overlay)
            #expect(b == isBehind, "\(kind) overlay \(overlay): behind \(b)")
            #expect(f == !isBehind, "\(kind) overlay \(overlay): front \(f)")
            #expect(b != f, "\(kind) overlay \(overlay): one slot")
        }
    }

    // MARK: Hosted

    /// A colour no other view of the host draws, and the content's.
    static let marker = (r: 0.13, g: 0.47, b: 0.71)
    static let content = (r: 0.0, g: 1.0, b: 0.0)

    nonisolated(unsafe) static var inits = 0
    final class Token: ObservableObject { init() { RefreshLayerMathTests.inits += 1 } }

    /// The custom indicator: a marker square with a `@StateObject` (counts the views SwiftUI creates).
    struct Marker: View {
        @StateObject private var token = Token()
        var body: some View {
            Color(red: RefreshLayerMathTests.marker.r, green: RefreshLayerMathTests.marker.g,
                  blue: RefreshLayerMathTests.marker.b)
                .frame(width: 20, height: 20)
        }
    }

    final class Model: ObservableObject {
        @Published var header = false
        @Published var builtIn = false
    }

    struct Host: View {
        @ObservedObject var model: Model
        let state: ZTronScrollState
        let counts: BodyCount
        var body: some View {
            // The same view type either way (`withScalingHeader` and `refresher` return `Self`): toggling keeps the identity.
            let view = ZTronScrollView(.vertical, state: state) { GreenContent(counts: counts) }
            let v = model.header ? view.withScalingHeader(size: .fixed(min: 0, max: 100)) { _ in Color.red } : view
            return model.builtIn
                ? v.refresher(style: .system) { try? await Task.sleep(nanoseconds: 1_000_000_000_000) }
                : v.refresher(refreshView: { _ in Marker() }) { try? await Task.sleep(nanoseconds: 1_000_000_000_000) }
        }
    }

    /// Pure green content that counts its body runs (S4).
    struct GreenContent: View {
        let counts: BodyCount
        var body: some View {
            counts.bodies += 1
            return Color(red: 0, green: 1, blue: 0).frame(height: 3000)
        }
    }

    /// The layers filled with colour `c`, in paint order (a layer, then its sublayers in order: a later one is drawn over an
    /// earlier one), with the part of their window frame their ancestors' clips let through and the product of their own
    /// and their ancestors' opacity.
    func painted(_ window: UIWindow, _ c: (r: Double, g: Double, b: Double))
        -> [(order: Int, frame: CGRect, visible: CGRect, opacity: Float)] {
        var out: [(Int, CGRect, CGRect, Float)] = []
        var order = 0
        let root = window.layer
        func visit(_ layer: CALayer, _ clip: CGRect, _ opacity: Float) {
            order += 1
            let o = opacity * layer.opacity
            var clip = clip
            if layer.masksToBounds { clip = clip.intersection(layer.convert(layer.bounds, to: root)) }
            if !layer.isHidden, let bg = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: bg).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - c.r) < 0.02, abs(g - c.g) < 0.02, abs(b - c.b) < 0.02 {
                    let f = layer.convert(layer.bounds, to: root)
                    out.append((order, f, f.intersection(clip), o * Float(a)))
                }
            }
            if !layer.isHidden { layer.sublayers?.forEach { visit($0, clip, o) } }
        }
        visit(root, .infinite, 1)
        return out
    }

    /// The marker drawn: a layer of it with some visible area at an opacity above one half.
    func drawn(_ window: UIWindow) -> [(order: Int, frame: CGRect, visible: CGRect, opacity: Float)] {
        painted(window, Self.marker).filter { !$0.visible.isNull && $0.visible.width * $0.visible.height > 1 && $0.opacity > 0.5 }
    }

    func signedPull(_ s: ZTronScrollState) -> CGFloat {
        let st = s.peek
        return RefreshMath.signedPull(edge: .top, offset: st.presentationOffset, zoom: st.presentationZoom, metrics: st.metrics,
                                      alignment: s.contentAlignment)
    }

    func hostWindow(_ path: OSPath, _ model: Model, _ s: ZTronScrollState, _ counts: BodyCount,
                    size: CGSize = CGSize(width: 390, height: 800)) -> UIWindow {
        withOSPath(path) {
            let w = UIWindow(frame: CGRect(origin: .zero, size: size))
            w.rootViewController = UIHostingController(rootView: Host(model: model, state: s, counts: counts).ignoresSafeArea())
            w.makeKeyAndVisible()
            return w
        }
    }

    /// The coordinator's one-shot timer on the run loop. GCD's main queue does not run inside a synchronous main-actor
    /// test's nested run loop (`pump`), so the retraction's heartbeat (`DispatchQueue.main.asyncAfter`) never fired there
    /// and a hold's boxes never ended (measured: `.retracting` at progress 0.6 for 4 s on both paths, at 6b00454 too).
    func runLoopTimers(_ s: ZTronScrollState) {
        s.refresh?.schedule = { delay, fire in
            Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { fire() } }
        }
    }

    /// The slot is latched with the group at the boxes' first frame (`RefreshGroupLatched`): a headerless custom gap
    /// indicator is drawn behind the content on the path without layer groups (in front on 17+), exactly once; installing
    /// a header or swapping the indicator during the hold keeps its slot (and the custom view's identity until the swap);
    /// the next hold latches again (under the header: grouped, in front).
    @Test(arguments: OSPath.allCases)
    func theSlotIsLatchedWithTheGroupWhileTheBoxesExist(path: OSPath) {
        #if DEBUG
        ZTronRenderCounters.reset()
        Self.inits = 0
        let s = makeState(path), model = Model(), counts = BodyCount()
        let w = hostWindow(path, model, s, counts)
        defer { unhost(w) }
        pump(0.4)
        #expect(s.refresh != nil, "\(path): the coordinator is wired")
        runLoopTimers(s)
        let behind = !s.usesGeometryGroup
        #expect(ZTronRenderCounters.notes["refresh.slot"] == nil, "\(path): no indicator box before the hold")
        s.beginRefreshing()
        pump(1.0)
        #expect(s.refresh?.states[.top]?.mode == .refreshing, "\(path): held")
        #expect(abs(signedPull(s) - 60) < 2, "\(path): at rest in the hold (\(signedPull(s)))")
        let slot = ZTronRenderCounters.notes["refresh.slot"]
        #expect(slot == (behind ? "behind" : "front"), "\(path): \(String(describing: slot))")
        let m = drawn(w)
        #expect(m.count == 1, "\(path): drawn once, by one slot (\(m.map(\.frame)))")
        let green = painted(w, Self.content).filter { $0.frame.height > 1000 }
        #expect(green.count == 1, "\(path): one content layer (\(green.map(\.frame)))")
        if let m = m.first, let g = green.first {
            // Paint order: behind the content (before it) without layer groups, over it on 17+.
            #expect(behind ? m.order < g.order : m.order > g.order, "\(path): marker \(m.order), content \(g.order)")
        }
        #expect(Self.inits == 1, "\(path): one indicator view (\(Self.inits))")

        // A header installed during the hold: the latched decision keeps the slot and the view.
        model.header = true
        pump(0.6)
        #expect(s.refresh?.states[.top]?.mode == .refreshing, "\(path): still held")
        #expect(ZTronRenderCounters.notes["refresh.slot"] == slot, "\(path) header: the slot stays")
        #expect(drawn(w).count == 1, "\(path) header: still drawn once (\(painted(w, Self.marker).map { ($0.frame, $0.visible, $0.opacity) }), pull \(signedPull(s)), base \(RefreshIndicatorMath.base(edge: .top, metrics: s.peek.metrics, overlay: false).0.top))")
        #expect(Self.inits == 1, "\(path) header: the same indicator view (\(Self.inits))")

        // The built-in indicator instead, during the hold: the slot stays (latched with the group); the marker is gone.
        model.builtIn = true
        pump(0.6)
        #expect(ZTronRenderCounters.notes["refresh.slot"] == slot, "\(path) built-in: the slot stays")
        #expect(painted(w, Self.marker).isEmpty, "\(path) built-in: the custom view is gone")

        // The hold ends and its retraction ends the boxes; the next hold latches again under the header: in front.
        s.endRefreshing()
        for _ in 0..<40 where s.refresh?.states[.top]?.mode != .notRefreshing || s.refresh?.retractions[.top] != nil
            || abs(signedPull(s)) > 0.5 { pump(0.1) }
        pump(0.3)
        let ended = "mode \(String(describing: s.refresh?.states[.top]?.mode)) drag \(String(describing: s.refresh?.states[.top]?.dragPosition)) retract \(String(describing: s.refresh?.retractions[.top])) pull \(signedPull(s)) probe \(String(describing: s.probe.pending))"
        #expect(s.refresh?.retractions[.top] == nil, "\(path): the retraction ended (\(ended))")
        ZTronRenderCounters.notes["refresh.slot"] = nil
        ZTronRenderCounters.notes["refresh.group"] = nil
        s.beginRefreshing()
        pump(1.0)
        #expect(ZTronRenderCounters.notes["refresh.slot"] == "front",
                "\(path): a new hold under the header draws in front (ended: \(ended); group \(String(describing: ZTronRenderCounters.notes["refresh.group"])))")
        s.endRefreshing()
        pump(0.8)
        #endif
    }

    /// Open item 27 (D80): an INSTANT resize that brings a scrolled-away hold's gap back on the screen draws the indicator at
    /// once, at its place, on both paths. D66 hid it on the path without layer groups for 0.45 s after any resize that
    /// began with nothing of it visible (it could not tell an instant resize from a system rotation). No content body runs
    /// across the resizes nor across a rotation's layout (both axes swapped and back, S4); each slot evaluates its leaf at
    /// most once per update.
    @Test(arguments: OSPath.allCases)
    func anInstantResizeDrawsTheGapIndicatorAtOnce(path: OSPath) {
        #if DEBUG
        ZTronRenderCounters.reset()
        Self.inits = 0
        let s = makeState(path), model = Model(), counts = BodyCount()
        let w = hostWindow(path, model, s, counts)
        defer { unhost(w) }
        pump(0.4)
        s.beginRefreshing()
        pump(1.0)
        #expect(abs(signedPull(s) - 60) < 2, "\(path): at rest in the hold (\(signedPull(s)))")
        #expect(drawn(w).count == 1, "\(path): drawn in its gap")
        let bodies = counts.bodies
        // An instant shrink (S7 keeps the visible centre: the content moves up, the gap leaves the viewport; the hold
        // stays): nothing of the indicator visible.
        w.frame = CGRect(x: 0, y: 0, width: 390, height: 320)
        pump(0.4)
        #expect(signedPull(s) < -20, "\(path): the gap is off the viewport (\(signedPull(s)))")
        #expect(drawn(w).isEmpty, "\(path): nothing of it drawn (\(drawn(w).map(\.visible)))")
        #expect(s.refresh?.states[.top]?.mode == .refreshing, "\(path): still held")
        // The instant resize back (S7 keeps the visible centre: the content moves down, the gap comes back).
        ZTronRenderCounters.reset()
        w.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        pump(0.1)
        let pull = signedPull(s)
        #expect(pull > 10, "\(path): the gap is back on the screen (\(pull))")
        let m = drawn(w)
        #expect(m.count == 1, "\(path): drawn at once after an instant resize (\(painted(w, Self.marker).map { ($0.visible, $0.opacity) }))")
        if let m = m.first {
            // At its place against the content's edge (the base plus the pull): 30 pt above it (`.default` in the gap).
            let base = RefreshIndicatorMath.base(edge: .top, metrics: s.peek.metrics, overlay: false).0.top
            #expect(abs((base + pull - m.frame.midY) - 30) < 1, "\(path): at its place (\(m.frame), base \(base), pull \(pull))")
        }
        #expect(counts.bodies == bodies, "\(path): no content body across the resizes (S4: \(counts.bodies - bodies))")
        let front = ZTronRenderCounters.value("refresh.leaf.front"), back = ZTronRenderCounters.value("refresh.leaf.behind")
        #expect(front > 0, "\(path): the leaf follows the resize (\(front))")
        #expect(s.usesGeometryGroup ? back == 0 : abs(front - back) <= 1,
                "\(path): one leaf per slot and update (front \(front), behind \(back))")

        // A rotation's layout (both axes swapped, landscape and back, each in one step): no content body (S4), and the
        // indicator drawn once at its place again.
        w.frame = CGRect(x: 0, y: 0, width: 800, height: 390)
        pump(0.3)
        w.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        pump(0.3)
        #expect(counts.bodies == bodies, "\(path): no content body across a rotation's layout (S4: \(counts.bodies - bodies))")
        #expect(s.refresh?.states[.top]?.mode == .refreshing, "\(path): still held after the rotation")
        let r = drawn(w), rp = signedPull(s)
        #expect(r.count == 1, "\(path): drawn once after the rotation (\(painted(w, Self.marker).map { ($0.visible, $0.opacity) }))")
        if let r = r.first {
            let base = RefreshIndicatorMath.base(edge: .top, metrics: s.peek.metrics, overlay: false).0.top
            #expect(abs((base + rp - r.frame.midY) - 30) < 1, "\(path): at its place after the rotation (\(r.frame), pull \(rp))")
        }
        s.endRefreshing()
        pump(0.8)
        #endif
    }
}
