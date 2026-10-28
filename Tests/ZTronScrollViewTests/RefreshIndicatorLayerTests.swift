import SwiftUI
import Testing
import UIKit
@testable import ZTronScrollView

/// Open item 18 (D65 review): a refresh hold under an uncapped 16:9 `.preserve` `.openGap` header taller than the viewport
/// (landscape, R 491 pt over 402) puts the gap, and the indicator in it, below the screen. The indicator was placed in the
/// viewport's frame with no layer of its own, so SwiftUI drew no layer for it there: in a system rotation Core Animation had
/// nothing to interpolate, the indicator vanished on the way out and, on the way back, appeared at once at its final place,
/// over the header that was still shrinking (seam lab, 27.0 / 17.5 / forced: 5-6 of 32-34 rotation frames drawn). The
/// indicator box is now its own layer group, laid out at the gap (`RefreshPlacementEffect`), so it keeps its layer below
/// the screen and rotates with the header and the content. `.stretch` the same: its overlay
/// indicator's placement was nil there (the clip from a base below the screen to the viewport's edge was empty). Checked
/// on the hosted layer tree, both OS paths (17+ `geometryGroup()`, 15–16 `compositingGroup()`).
@MainActor
@Suite(.serialized)
struct RefreshIndicatorLayerTests {
    /// A colour no other view of the host draws.
    static let marker = (r: 0.11, g: 0.22, b: 0.33)

    struct Host: View {
        let state: ZTronScrollState
        let behavior: ZTronHeaderScalingBehavior
        var body: some View {
            ZTronScrollView(.vertical, state: state) { Color.green.frame(height: 3000) }
                .withScalingHeader(size: .aspectRatio(16.0 / 9.0, min: 64), scalingBehavior: behavior) { _ in Color.red }
                .refresher(refreshView: { _ in
                    Color(red: RefreshIndicatorLayerTests.marker.r, green: RefreshIndicatorLayerTests.marker.g,
                          blue: RefreshIndicatorLayerTests.marker.b)
                        .frame(width: 20, height: 20)
                }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
        }
    }

    /// The window frames of the layers filled with the marker colour; `presented`: as drawn now (the presentation tree,
    /// where Core Animation interpolates), else the model values.
    func markerFrames(in window: UIWindow, presented: Bool = false) -> [CGRect] {
        var out: [CGRect] = []
        let root = presented ? (window.layer.presentation() ?? window.layer) : window.layer
        func visit(_ layer: CALayer) {
            if let c = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - Self.marker.r) < 0.02, abs(g - Self.marker.g) < 0.02, abs(b - Self.marker.b) < 0.02 {
                    out.append(layer.convert(layer.bounds, to: root))
                }
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root)
        return out
    }

    /// Hosts the view in a `size` window, begins refreshing and returns the marker's layer frames with the indicator's
    /// place (`[base, base + 60]` in the window: the `.openGap` gap `[aci.top − hold, aci.top]`, the `.stretch` band's
    /// `[top0 + R, … + 60]`) and the resting header height.
    func hold(path: OSPath, size: CGSize, behavior: ZTronHeaderScalingBehavior = .preserve)
        -> (frames: [CGRect], gap: ClosedRange<CGFloat>, resting: CGFloat, height: CGFloat) {
        let s = makeState(path)
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(origin: .zero, size: size))
            w.rootViewController = UIHostingController(rootView: Host(state: s, behavior: behavior))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        s.beginRefreshing()
        pump(0.5)
        let m = s.peek.metrics
        let base = RefreshIndicatorMath.base(edge: .top, metrics: m, overlay: false).0.top
        return (markerFrames(in: w), base...(base + 60), m.header?.resting ?? .nan, size.height)
    }

    func expectLayerInPlace(path: OSPath, behavior: ZTronHeaderScalingBehavior) {
        let label = "\(path) \(behavior)"
        // Portrait: the gap (band) is on the screen.
        let p = hold(path: path, size: CGSize(width: 402, height: 874), behavior: behavior)
        #expect(p.frames.count == 1, "\(label) portrait: marker layers \(p.frames)")
        if let f = p.frames.first {
            #expect(p.gap.contains(f.midY) && p.gap.upperBound < p.height, "\(label) portrait: marker \(f) place \(p.gap)")
            #expect(abs(f.midX - 201) < 0.5, "\(label) portrait: marker \(f)")
        }
        // Landscape: R 491 pt over a 402 pt viewport, the indicator's place below the screen; it keeps its layer there.
        let l = hold(path: path, size: CGSize(width: 874, height: 402), behavior: behavior)
        #expect(l.resting > l.height, "\(label) landscape: R \(l.resting)")
        #expect(l.gap.lowerBound > l.height, "\(label) landscape: place \(l.gap) below the screen")
        #expect(l.frames.count == 1, "\(label) landscape: marker layers \(l.frames)")
        if let f = l.frames.first {
            #expect(l.gap.contains(f.midY), "\(label) landscape: marker \(f) place \(l.gap)")
            #expect(abs(f.midX - 437) < 0.5, "\(label) landscape: marker \(f)")
        }
    }

    /// `.preserve` `.openGap` (the default): the gap below the still header.
    @Test(arguments: OSPath.allCases)
    func theOpenGapHoldIndicatorKeepsItsLayerInItsGap(path: OSPath) {
        expectLayerInPlace(path: path, behavior: .preserve)
    }

    /// `.stretch`: the indicator floats over the band the hold stretches (overlay placement, its base `top0 + R`).
    @Test(arguments: OSPath.allCases)
    func theStretchHoldIndicatorKeepsItsLayerOverItsBand(path: OSPath) {
        expectLayerInPlace(path: path, behavior: .stretch)
    }

    final class Width: ObservableObject { @Published var narrow = false }

    struct ResizeHost: View {
        let state: ZTronScrollState
        @ObservedObject var width: Width
        var body: some View {
            Host(state: state, behavior: .preserve).frame(width: width.narrow ? 241 : 402)
        }
    }

    /// The box stays laid out, so a `withAnimation` width change during the hold (R 226 → 136 pt, the gap moves up 90 pt
    /// with the header) draws the indicator part way at mid animation (as drawn: the presentation tree). Placed by a
    /// render-time translation instead (an intermediate fix, animatable or not), it landed at its new place in the first
    /// frame while the header shrank (seam lab, 17.5: 88 pt above the gap, over the header; here `mid == end`).
    @Test(arguments: OSPath.allCases)
    func anAnimatedResizeMovesTheIndicatorWithTheGap(path: OSPath) {
        let s = makeState(path), width = Width()
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: ResizeHost(state: s, width: width))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        var n = 0
        while s.peek.metrics.header == nil, n < 30 { pump(0.1); n += 1 }
        s.beginRefreshing()
        pump(0.5)
        let start = markerFrames(in: w).first?.midY ?? .nan
        withAnimation(.linear(duration: 1.2)) { width.narrow = true }
        pump(0.5)
        let mid = markerFrames(in: w, presented: true).first?.midY ?? .nan
        pump(1.2)
        let end = markerFrames(in: w).first?.midY ?? .nan
        #expect(start - end > 80, "\(path): the gap moves up with R (\(start) -> \(end))")
        #expect(mid < start - 10 && mid > end + 10, "\(path): part way at mid animation: \(start) -> \(mid) -> \(end)")
    }

    // MARK: Final check of D65: the 15–16 indicator group only under a header

    final class HeaderToggle: ObservableObject { @Published var on = false }

    struct BlendHost: View {
        @ObservedObject var header: HeaderToggle
        let state: ZTronScrollState
        var body: some View {
            let view = ZTronScrollView(.vertical, state: state) { Color.green.frame(height: 3000) }
            // The same view type either way (`withScalingHeader` returns `Self`): toggling keeps the identity.
            (header.on ? view.withScalingHeader(size: .fixed(min: 0, max: 100)) { _ in Color.red } : view)
                .refresher(refreshView: { _ in Color.white.frame(width: 20, height: 20).blendMode(.difference) }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
        }
    }

    /// The 15–16 group (`compositingGroup()`) composites a custom indicator alone: its blend modes no longer reach what is
    /// behind it (forced lane, no header: a `.difference` white probe stayed white where 17+ and fb1fe59 blend it,
    /// `RefreshUITests.testACustomIndicatorsBlendModeReachesWhatIsBehindIt`). Open item 18 needs the group only under a
    /// scaling header, so 15–16 group the box only there, latched at the box's first frame: installing or removing the
    /// header during the hold keeps the indicator's identity. (A logic-test host has no render server, so this checks the
    /// latched branch; the header case's layers are checked above.)
    @Test(arguments: OSPath.allCases, [false, true])
    func theFifteenIndicatorGroupIsOnlyUnderAHeader(path: OSPath, headerFirst: Bool) {
        #if DEBUG
        ZTronRenderCounters.reset()
        let s = makeState(path), header = HeaderToggle()
        header.on = headerFirst
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: BlendHost(header: header, state: s))
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        pump(0.4)
        #expect(ZTronRenderCounters.notes["refresh.group"] == nil, "\(path): no indicator box before the hold")
        s.beginRefreshing()
        pump(0.5)
        let first = ZTronRenderCounters.notes["refresh.group"]
        header.on.toggle()   // install / remove the header during the hold
        pump(0.5)
        let after = ZTronRenderCounters.notes["refresh.group"]
        #expect(s.refresh?.states[.top]?.mode == .refreshing, "\(path): still held")
        if path == .preferred {
            #expect(first == nil && after == nil, "17+: geometryGroup, no latch (\(String(describing: first)))")
        } else {
            #expect(first == (headerFirst ? "compositing" : "none"), "\(path) header first \(headerFirst): \(String(describing: first))")
            #expect(after == first, "\(path): the latch never re-decides during the hold (\(String(describing: after)))")
        }
        #endif
    }

    // MARK: Open item 19: a headerless hold whose gap leaves the viewport

    /// Each marker layer's window frame and the part of it its ancestors' clips let through (`masksToBounds` layers): what
    /// it can draw.
    func markerVisibility(in window: UIWindow) -> [(frame: CGRect, visible: CGRect)] {
        var out: [(CGRect, CGRect)] = []
        let root = window.layer
        func visit(_ layer: CALayer, _ clip: CGRect) {
            var clip = clip
            if layer.masksToBounds { clip = clip.intersection(layer.convert(layer.bounds, to: root)) }
            if let c = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - Self.marker.r) < 0.02, abs(g - Self.marker.g) < 0.02, abs(b - Self.marker.b) < 0.02 {
                    let f = layer.convert(layer.bounds, to: root)
                    out.append((f, f.intersection(clip)))
                }
            }
            layer.sublayers?.forEach { visit($0, clip) }
        }
        visit(root, .infinite)
        return out
    }

    /// The window frames of every layer of the window.
    func layerFrames(in window: UIWindow) -> [CGRect] {
        var out: [CGRect] = []
        func visit(_ layer: CALayer) {
            out.append(layer.convert(layer.bounds, to: window.layer))
            layer.sublayers?.forEach(visit)
        }
        visit(window.layer)
        return out
    }

    /// `marker*`: a marker-coloured custom view placed with that style (`.default` is what `refresher(refreshView:)` uses);
    /// `builtIn*`: the built-in indicator (found by its box's layer).
    enum Look: String, CaseIterable, Sendable { case markerSystem, markerDefault, builtInSystem, builtInDefault }

    /// Open item 19: without a header, a hold whose gap leaves the viewport (S7 in a rotation scrolls it away; here the
    /// content scrolled 400 pt past the base) took the indicator out of the tree (its placement was nil), so a rotation
    /// back had no layer to interpolate and drew it at once at its final place, over the content still sliding in (seam
    /// lab, 14 frames). The indicator keeps its layer group (the box) on the content's edge, the indicator rigid with the
    /// content where the hold rests it (30 pt before the edge: `.default` glued to it, `.system` at H/2), and draws
    /// nothing there (`region` starts at the base); at rest it draws whole in its gap, part way in its part of the gap.
    /// Every edge, both styles, a custom and the built-in indicator, both OS paths. 15–16 keep a custom indicator without
    /// a header ungrouped (its blend modes, final check of D65): its box has no layer off the viewport (open item 20; D66 hides it
    /// in a rotation that brings the gap back instead, `RefreshResizeReveal`).
    @Test(arguments: OSPath.allCases, Look.allCases)
    func aHeaderlessHoldScrolledAwayKeepsItsIndicatorOnTheContentsEdge(path: OSPath, look: Look) {
        let marker = look == .markerSystem || look == .markerDefault
        let style: ZTronRefreshStyle = look == .markerSystem || look == .builtInSystem ? .system : .default
        for edge in [Edge.top, .bottom, .leading, .trailing] {
            let vertical = edge == .top || edge == .bottom
            let viewport = CGSize(width: 390, height: 800)
            let content = vertical ? CGSize(width: 390, height: 3000) : CGSize(width: 3000, height: 800)
            let rig = RefreshRig(path, configs: [edge: ZTronRefreshConfiguration()], axes: vertical ? .vertical : .horizontal,
                                 viewport: viewport, content: content)
            var spec = RefresherSpec(style: style, overlay: false, configuration: ZTronRefreshConfiguration(), action: { _ in })
            if marker {
                spec.indicator = { _ in
                    AnyView(Color(red: Self.marker.r, green: Self.marker.g, blue: Self.marker.b).frame(width: 20, height: 20))
                }
            }
            let host = RefreshIndicatorsHost(coordinator: rig.refresh, state: rig.state, specs: [edge: spec])
            let w = withOSPath(path) {
                let w = UIWindow(frame: CGRect(origin: .zero, size: viewport))
                w.rootViewController = UIHostingController(rootView: host.ignoresSafeArea())
                w.makeKeyAndVisible()
                return w
            }
            defer { unhost(w) }
            let along = vertical ? viewport.height : viewport.width
            let end = vertical ? content.height - viewport.height : content.width - viewport.width
            if edge == .bottom { rig.state.setContentOffset(CGPoint(x: 0, y: end), animated: false) }
            if edge == .trailing { rig.state.setContentOffset(CGPoint(x: end, y: 0), animated: false) }
            pump(0.2)
            rig.refresh.begin(edge, runAction: false)
            for _ in 0..<40 { rig.tick(); pump(0.016) }
            pump(0.3)
            let label = "\(path) \(look) \(edge)"
            /// The signed pull now and the placement the leaf computes from it.
            func now() -> (pull: CGFloat, placement: RefreshPlacement?) {
                let st = rig.state.peek
                let s = RefreshMath.signedPull(edge: edge, offset: st.presentationOffset, zoom: 1, metrics: st.metrics,
                                               alignment: rig.state.contentAlignment)
                let (base, _) = RefreshIndicatorMath.base(edge: edge, metrics: st.metrics, overlay: false)
                return (s, RefreshIndicatorMath.placement(edge: edge, style: style, overlay: false, refreshing: true,
                                                          dragPosition: 1, pull: s, length: 60, viewport: viewport, base: base,
                                                          hold: 60))
            }
            /// The marker's centre along the pull axis, outward from the content's edge (+30: the hold's rest place).
            func outward(_ f: CGRect, pull s: CGFloat) -> CGFloat {
                switch edge {
                case .top: return s - f.midY
                case .leading: return s - f.midX
                case .bottom: return f.midY - (along - s)
                case .trailing: return f.midX - (along - s)
                }
            }
            /// The content's edge in window coordinates along the pull axis (the base is 0: no safe area, no header).
            func contentEdge(_ s: CGFloat) -> CGFloat { edge == .top || edge == .leading ? s : along - s }
            /// The built-in indicator: a layer at the box's frame (its group) and a smaller one inside it (the indicator).
            /// A marker view is found by its colour instead (SwiftUI draws its box without a layer of that frame).
            func boxLayer(_ box: CGRect) -> Bool {
                let frames = layerFrames(in: w)
                return frames.contains { abs($0.minX - box.minX) < 0.5 && abs($0.minY - box.minY) < 0.5
                    && abs($0.width - box.width) < 0.5 && abs($0.height - box.height) < 0.5 }
                    && frames.contains { box.insetBy(dx: -0.5, dy: -0.5).contains($0) && $0.width * $0.height > 0
                        && $0.width * $0.height < box.width * box.height * 0.5 }
            }
            let rest = now()
            #expect(abs(rest.pull - 60) < 0.5, "\(label): held at rest (pull \(rest.pull))")
            if !marker, let box = rest.placement?.box {
                #expect(boxLayer(box), "\(label) rest: the box's layer \(box)")
            }
            if marker {
                let m = markerVisibility(in: w)
                #expect(m.count == 1, "\(label) rest: marker layers \(m.map(\.frame))")
                if let m = m.first {
                    #expect(abs(outward(m.frame, pull: 60) - 30) < 0.5, "\(label) rest: \(m.frame)")
                    #expect(m.visible == m.frame, "\(label) rest: drawn whole in its gap (\(m.visible))")
                }
            }
            // Scroll the content 400 pt past the base: the gap is off the viewport.
            let away: CGPoint
            switch edge {
            case .top: away = CGPoint(x: 0, y: 400)
            case .bottom: away = CGPoint(x: 0, y: end - 400)
            case .leading: away = CGPoint(x: 400, y: 0)
            case .trailing: away = CGPoint(x: end - 400, y: 0)
            }
            rig.state.setContentOffset(away, animated: false)
            pump(0.2)
            let gone = now()
            #expect(abs(gone.pull + 400) < 0.5, "\(label): content edge 400 pt past the base (\(gone.pull))")
            #expect(rig.refreshState(edge).mode == .refreshing, "\(label): still held")
            guard let placement = gone.placement else {
                Issue.record("\(label) away: no placement")
                continue
            }
            let farEdge: CGFloat
            switch edge {
            case .top: farEdge = placement.box.maxY
            case .leading: farEdge = placement.box.maxX
            case .bottom: farEdge = placement.box.minY
            case .trailing: farEdge = placement.box.minX
            }
            #expect(abs(farEdge - contentEdge(gone.pull)) < 0.01, "\(label) away: the box ends on the content's edge")
            let ungrouped = path == .forcedFallback && marker
            withKnownIssue("open item 20 / D66: 15–16 keep a headerless custom indicator ungrouped (blend modes), no layer off the screen") {
                if !marker {
                    #expect(boxLayer(placement.box), "\(label) away: the box keeps its layers off the viewport \(placement.box)")
                } else {
                    let m = markerVisibility(in: w)
                    #expect(m.count == 1, "\(label) away: the indicator keeps its layer (\(m.map(\.frame)))")
                    if let m = m.first {
                        #expect(abs(outward(m.frame, pull: gone.pull) - 30) < 0.5, "\(label) away: rigid on the content's edge \(m.frame)")
                        #expect(m.visible.isNull || m.visible.width * m.visible.height == 0, "\(label) away: draws nothing (\(m.visible))")
                    }
                }
            } when: { ungrouped }
            // Scrolled back to 20 pt into the hold (pull 40): drawn in the gap only, never past the content's edge.
            let part: CGPoint
            switch edge {
            case .top: part = CGPoint(x: 0, y: -40)
            case .bottom: part = CGPoint(x: 0, y: end + 40)
            case .leading: part = CGPoint(x: -40, y: 0)
            case .trailing: part = CGPoint(x: end + 40, y: 0)
            }
            rig.state.setContentOffset(part, animated: false)
            pump(0.2)
            if marker {
                if let m = markerVisibility(in: w).first {
                    let edgeAt = along - 40
                    switch edge {
                    case .top: #expect(m.visible.maxY <= 40.01 && m.visible.minY >= -0.01, "\(label) part: \(m.visible)")
                    case .leading: #expect(m.visible.maxX <= 40.01 && m.visible.minX >= -0.01, "\(label) part: \(m.visible)")
                    case .bottom: #expect(m.visible.minY >= edgeAt - 0.01 && m.visible.maxY <= along + 0.01, "\(label) part: \(m.visible)")
                    case .trailing: #expect(m.visible.minX >= edgeAt - 0.01 && m.visible.maxX <= along + 0.01, "\(label) part: \(m.visible)")
                    }
                    #expect(!m.visible.isNull && m.visible.width * m.visible.height > 0, "\(label) part: drawn in the gap")
                } else {
                    Issue.record("\(label) part: no marker layer")
                }
            }
        }
    }

    // MARK: Open item 21: an animated resize during a hold

    /// A colour for the content's first 100 pt (its top edge), the rest green.
    static let edgeColor = (r: 0.9, g: 0.4, b: 0.1)

    final class Size: ObservableObject { @Published var short = false; @Published var narrow = false }

    struct ResizeHoldHost: View {
        let state: ZTronScrollState
        @ObservedObject var size: Size
        var body: some View {
            VStack(spacing: 0) {
                ZTronScrollView(.vertical, state: state) {
                    VStack(spacing: 0) {
                        Color(red: RefreshIndicatorLayerTests.edgeColor.r, green: RefreshIndicatorLayerTests.edgeColor.g,
                              blue: RefreshIndicatorLayerTests.edgeColor.b).frame(height: 100)
                        Color.green.frame(height: 2900)
                    }
                }
                .refresher(refreshView: { _ in
                    Color(red: RefreshIndicatorLayerTests.marker.r, green: RefreshIndicatorLayerTests.marker.g,
                          blue: RefreshIndicatorLayerTests.marker.b)
                        .frame(width: 20, height: 20)
                }) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000_000)
                }
                .frame(width: size.narrow ? 241 : 402, height: size.short ? 874 * 0.4 : 874)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// As drawn now (the presentation tree): the first layer filled with `color`, and its part inside its ancestors' clips.
    func presented(_ color: (r: Double, g: Double, b: Double), in window: UIWindow) -> (frame: CGRect, visible: CGRect)? {
        let root = window.layer.presentation() ?? window.layer
        var found: (CGRect, CGRect)?
        func visit(_ layer: CALayer, _ clip: CGRect) {
            guard found == nil else { return }
            var clip = clip
            if layer.masksToBounds { clip = clip.intersection(layer.convert(layer.bounds, to: root)) }
            if let c = layer.backgroundColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if UIColor(cgColor: c).getRed(&r, green: &g, blue: &b, alpha: &a), a > 0.5,
                   abs(r - color.r) < 0.02, abs(g - color.g) < 0.02, abs(b - color.b) < 0.02 {
                    let f = layer.convert(layer.bounds, to: root)
                    found = (f, f.intersection(clip))
                    return
                }
            }
            layer.sublayers?.forEach { visit($0, clip) }
        }
        visit(root, .infinite)
        return found
    }

    /// Open item 21: a headerless hold, the scroll view's height animated to 0.4 (top-pinned) and back, or its width to
    /// 241 pt and back. S7 keeps the visible centre, so the content's top edge slides up past the base (the gap leaves the
    /// viewport) and back. The box moved with the base only: it sat at the committed pull, so the marker vanished at once
    /// on the way out and, on the way back, was drawn at its final place while the content still covered the gap (seam
    /// lab: 57 frames over the content). Sampled as drawn every 0.05 s: never past the content's edge, and where its
    /// resting place is on the screen, there (30 pt before the edge, the hold's rest). Before the fix (27.0): 11 of 28
    /// samples over the content, the first one missing; 17.5 and forced alike.
    @Test(arguments: OSPath.allCases, [false, true])
    func anAnimatedResizeDuringAHoldKeepsTheIndicatorOnTheContentsEdge(path: OSPath, width: Bool) {
        let s = makeState(path), size = Size()
        let w = withOSPath(path) {
            let w = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            w.rootViewController = UIHostingController(rootView: ResizeHoldHost(state: s, size: size).ignoresSafeArea())
            w.makeKeyAndVisible()
            return w
        }
        defer { unhost(w) }
        pump(0.3)
        s.beginRefreshing()
        pump(0.8)
        let label = "\(path) \(width ? "width" : "height")"
        var judged = 0, inPlace = 0, over: [String] = [], off: [String] = []
        func sample(_ tag: String) {
            guard let edge = presented(Self.edgeColor, in: w)?.frame.minY else { return }
            guard let m = presented(Self.marker, in: w) else { return }
            let drawn = !m.visible.isNull && m.visible.height > 0.5
            if drawn, m.visible.maxY > edge + 0.5 { over.append("\(tag) \(m.visible.maxY) > \(edge)") }
            // The resting place [edge - 40, edge - 20] entirely on the screen (the base is 0 here).
            if edge - 40 >= 0.5 {
                judged += 1
                if drawn, abs(m.frame.midY - (edge - 30)) <= 1, m.visible.height > 19.5 { inPlace += 1 } else {
                    off.append("\(tag) marker \(m.frame.midY) visible \(m.visible.height) edge \(edge)")
                }
            }
        }
        for (k, flag) in [true, false].enumerated() {
            withAnimation(.linear(duration: 1.2)) {
                if width { size.narrow = flag } else { size.short = flag }
            }
            for i in 0..<28 { pump(0.05); sample("\(k).\(i)") }
            pump(0.5)
        }
        #expect(s.refresh?.states[.top]?.mode == .refreshing, "\(label): still held")
        #expect(over.isEmpty, "\(label): drawn over the content \(over)")
        #expect(judged >= 3 && inPlace == judged, "\(label): \(inPlace) / \(judged) in place \(off)")
        print("I21 \(label) judged=\(judged) inPlace=\(inPlace) over=\(over.count) off=\(off)")
    }
}
