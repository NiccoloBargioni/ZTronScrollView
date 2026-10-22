import SwiftUI
import UIKit
import ZTronScrollView
import ScrollArbitration

/// `-ZTronScreen mixedProbe -ZTronMixedVariant <name>` (DBG-s8, docs/progress/DBG-s8.md): what, on iOS 26+, stops a drag that starts on a view inside SwiftUI's own
/// vertical `ScrollView` from scrolling the page. Same page as `MixedTopologyScreen`, one 100 pt target (`mixed.carousel`) between two native bands; the target is a
/// plain colour with ONE gesture variant (no ZTron code), a ZTronScrollView or a native `ScrollView`. Driven by `MixedProbeUITests` (a measurement harness, not a
/// contract). Variants: `plain`; `dragN-sim` (simultaneous `DragGesture(minimumDistance: N)`), `gestureN`, `highN`, `globalN`, `drag10-gesture|high|sim-named|sim-none|sim-sub|
/// sim-gest`, `drag0-sim`, `drag10-selfdisable`, `spatial-sim`, `magnify-sim`, `tap-sim`, `tap2-sim`, `ontap`, `longpress-sim`, `button`, `contentshape`, `drag10+magnify`;
/// `anisoS-sim` / `anisoNS-sim` / `anisoFS-sim` (attempts at a per-axis DragGesture, they do not work); `uikit-pan` / `uikit-pan-axis` (Apple's UIKit workaround, outside
/// SPEC S2); `zt-h` / `zt-h-dis` (the library's carousel, also disabled); `native-h` (a native horizontal ScrollView). The Info readout carries `in=` / `out=`: the iOS 17
/// `.scrollView(axis:)` coordinate spaces seen from inside / outside the page (`S` any, `V` vertical, `H` horizontal; `GeometryProxy.bounds(of:)` is nil without one).
struct MixedProbeScreen: View {
    static var variant: String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-ZTronMixedVariant"), i + 1 < a.count { return a[i + 1] }
        return "plain"
    }

    @State private var carousel = ZTronScrollState()
    @State private var info = ""
    @State private var selfOn = true
    private let hits = ProbeHits()

    /// `anisoS-sim` / `anisoS-M-sim`: stretch factor S (default minimum distance 10).
    private static var aniso: (CGFloat, CGFloat)? {
        let v = variant
        guard v.hasPrefix("aniso"), !v.hasPrefix("anisoN"), !v.hasPrefix("anisoF"), v.hasSuffix("-sim") else { return nil }
        let parts = v.dropFirst(5).dropLast(4).split(separator: "-").compactMap { Int($0) }
        guard let s = parts.first else { return nil }
        return (CGFloat(s), CGFloat(parts.count > 1 ? parts[1] : 10))
    }

    private static var anisoNamed: (CGFloat, CGFloat)? {
        let v = variant
        guard v.hasPrefix("anisoN"), v.hasSuffix("-sim"), let s = Int(v.dropFirst(6).dropLast(4)) else { return nil }
        return (CGFloat(s), 10)
    }

    private static var anisoFrame: (CGFloat, CGFloat)? {
        let v = variant
        guard v.hasPrefix("anisoF"), v.hasSuffix("-sim"), let s = Int(v.dropFirst(6).dropLast(4)) else { return nil }
        return (CGFloat(s), 10)
    }

    /// `gestureN` / `highN` / `globalN`: `DragGesture(minimumDistance: N)` as `.gesture` / `.highPriorityGesture` / simultaneous in the global space.
    private static var dragKind: (String, CGFloat)? {
        for k in ["gesture", "high", "global"] where variant.hasPrefix(k) {
            if let n = Int(variant.dropFirst(k.count)) { return (k, CGFloat(n)) }
        }
        return nil
    }

    /// `dragN-sim`: a plain simultaneous `DragGesture(minimumDistance: N)`.
    private static var dragMin: CGFloat? {
        let v = variant
        guard v.hasPrefix("drag"), v.hasSuffix("-sim"), let n = Int(v.dropFirst(4).dropLast(4)) else { return nil }
        return CGFloat(n)
    }

    var body: some View {
        VStack(spacing: 4) {
            Button("Info") { info = "v=\(Self.variant) n=\(hits.n) cx=\(Int(carousel.contentOffset.x.rounded())) \(hits.notes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))" }
                .accessibilityIdentifier("Info")
            Text(info).font(.caption2).accessibilityIdentifier("mixedInfo").accessibilityValue(info)
            ScrollSpaceProbe(label: "out", hits: hits).frame(height: 1)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ScrollSpaceProbe(label: "in", hits: hits).frame(height: 1)
                    Color.red.frame(height: 120)
                    target.frame(height: 100).accessibilityIdentifier("mixed.carousel")
                    Color.green.frame(height: 120)
                    Color.orange.frame(height: 900)
                }
            }
            .border(Color.gray)
        }
        .padding(8)
        .background(ProbeInstaller())
    }

    private var base: some View {
        Color.blue.opacity(0.3).overlay(Text(Self.variant).font(.caption))
    }

    private func drag(_ distance: CGFloat) -> DragGesture {
        DragGesture(minimumDistance: distance)
    }

    @ViewBuilder private var target: some View {
        let h = hits
        let n = scrollArbitrationGestureName
        if let m = Self.dragMin {
            base.simultaneousGesture(drag(m).onChanged { _ in h.n += 1 })
        } else if let (s, m) = Self.anisoNamed {
            // Same, but the gesture measures in a NAMED space owned by the stretched wrapper.
            base.scaleEffect(x: 1, y: 1 / s, anchor: .topLeading)
                .simultaneousGesture(DragGesture(minimumDistance: m, coordinateSpace: .named("ztron.aniso")).onChanged { _ in h.n += 1 })
                .coordinateSpace(name: "ztron.aniso")
                .scaleEffect(x: 1, y: s, anchor: .topLeading)
        } else if let (s, m) = Self.anisoFrame {
            // The stretch is real layout instead of an effect: a frame 1/s tall scaled up by s (the content is a child of the scaled view).
            base.frame(height: 100 / s)
                .simultaneousGesture(drag(m).onChanged { _ in h.n += 1 })
                .scaleEffect(x: 1, y: s, anchor: .topLeading)
        } else if let (s, m) = Self.aniso {
            // A per-axis attach: the gesture host is stretched by `s` along y on screen (its content counter-scaled), so the gesture's local
            // y is `s` times smaller than the finger travel: a vertical drag needs `m * s` pt to be recognized, a horizontal one `m`.
            base.scaleEffect(x: 1, y: 1 / s, anchor: .topLeading)
                .simultaneousGesture(drag(m).onChanged { _ in h.n += 1 })
                .scaleEffect(x: 1, y: s, anchor: .topLeading)
        } else if let (kind, m) = Self.dragKind {
            switch kind {
            case "gesture": base.gesture(drag(m).onChanged { _ in h.n += 1 })
            case "high": base.highPriorityGesture(drag(m).onChanged { _ in h.n += 1 })
            default: base.simultaneousGesture(DragGesture(minimumDistance: m, coordinateSpace: .global).onChanged { _ in h.n += 1 })
            }
        } else {
        switch Self.variant {
        case "plain": base
        // A plain SwiftUI drag, every attach and shape the library uses.
        case "drag10-sim": base.simultaneousGesture(drag(10).onChanged { _ in h.n += 1 })
        case "drag10-gesture": base.gesture(drag(10).onChanged { _ in h.n += 1 })
        case "drag10-high": base.highPriorityGesture(drag(10).onChanged { _ in h.n += 1 })
        case "drag10-sim-named": named(drag(10), n)
        case "drag0-sim": base.simultaneousGesture(drag(0).onChanged { _ in h.n += 1 })
        case "drag0-sim-named": named(drag(0), n)
        case "drag10-sim-none": base.simultaneousGesture(drag(10).onChanged { _ in h.n += 1 }, including: .none)
        case "drag10-sim-sub": base.simultaneousGesture(drag(10).onChanged { _ in h.n += 1 }, including: .subviews)
        case "drag10-sim-gest": base.simultaneousGesture(drag(10).onChanged { _ in h.n += 1 }, including: .gesture)
        case "drag10-sim-off": base.simultaneousGesture(drag(10).onChanged { _ in h.n += 1 }, including: .all)
        case "drag10-selfdisable":
            base.simultaneousGesture(drag(10).onChanged { _ in h.n += 1; selfOn = false }, including: selfOn ? .all : .subviews)
        case "spatial-sim": spatial
        case "drag10-global": base.simultaneousGesture(DragGesture(minimumDistance: 10, coordinateSpace: .global).onChanged { _ in h.n += 1 })
        case "drag100-sim": base.simultaneousGesture(drag(100).onChanged { _ in h.n += 1 })
        case "magnify-sim": magnify
        case "tap-sim": base.simultaneousGesture(TapGesture().onEnded { h.n += 1 })
        case "tap2-sim": base.simultaneousGesture(TapGesture(count: 2).onEnded { h.n += 1 })
        case "ontap": base.onTapGesture { h.n += 1 }
        case "longpress-sim": base.simultaneousGesture(LongPressGesture().onEnded { _ in h.n += 1 })
        case "drag10+magnify": dragAndMagnify
        case "uikit-pan": uikitPan(axisAware: false)
        case "uikit-pan-axis": uikitPan(axisAware: true)
        case "button": Button(action: { h.n += 1 }) { base }.buttonStyle(.plain)
        case "contentshape": base.contentShape(Rectangle()).simultaneousGesture(drag(10).onChanged { _ in h.n += 1 })
        // The library, as shipped (its own DEBUG `-ZTronPanGestureMode` argument picks the attach).
        case "zt-h": carouselView
        case "zt-h-dis": carouselView.ztronScrollDisabled(true)
        // SwiftUI's own horizontal scroll view.
        case "native-h":
            ScrollView(.horizontal) {
                HStack(spacing: 8) { ForEach(0..<20, id: \.self) { Text("Card \($0)").frame(width: 120, height: 100).background(Color.blue.opacity(0.3)) } }
            }
        default: base
        }
        }
    }

    private var carouselView: some View {
        ZTronScrollView(.horizontal, state: carousel) {
            HStack(spacing: 8) {
                ForEach(0..<20, id: \.self) { i in
                    Text("Card \(i)").frame(width: 120, height: 100).background(Color.blue.opacity(0.3))
                }
            }
        }
    }

    @ViewBuilder private func named(_ g: DragGesture, _ name: String) -> some View {
        let h = hits
        if #available(iOS 18, *) { base.simultaneousGesture(g.onChanged { _ in h.n += 1 }, name: name) } else { base }
    }

    /// Apple's suggested workaround for FB18199844 (a UIKit recognizer whose delegate allows simultaneous recognition), as a pan; `axisAware`
    /// also declines (`gestureRecognizerShouldBegin`) a drag that is not horizontal-dominant. Outside SPEC S2 (UIKit): measured for the user's decision.
    @ViewBuilder private func uikitPan(axisAware: Bool) -> some View {
        let h = hits
        if #available(iOS 18, *) {
            base.gesture(ProbeUIKitPan(counter: h, axisAware: axisAware))
        } else { base }
    }

    @ViewBuilder private var spatial: some View {
        let h = hits
        if #available(iOS 18, *) { base.simultaneousGesture(SpatialEventGesture().onChanged { _ in h.n += 1 }) } else { base }
    }

    @ViewBuilder private var magnify: some View {
        let h = hits
        if #available(iOS 17, *) {
            base.simultaneousGesture(MagnifyGesture().onChanged { _ in h.n += 1 })
        } else {
            base.simultaneousGesture(MagnificationGesture().onChanged { _ in h.n += 1 })
        }
    }

    @ViewBuilder private var dragAndMagnify: some View {
        let h = hits
        if #available(iOS 17, *) {
            base.simultaneousGesture(drag(10).onChanged { _ in h.n += 1 }).simultaneousGesture(MagnifyGesture().onChanged { _ in h.n += 1 })
        } else {
            base.simultaneousGesture(drag(10).onChanged { _ in h.n += 1 }).simultaneousGesture(MagnificationGesture().onChanged { _ in h.n += 1 })
        }
    }
}

@available(iOS 18.0, *)
struct ProbeUIKitPan: UIGestureRecognizerRepresentable {
    let counter: ProbeHits
    let axisAware: Bool

    func makeCoordinator(converter: CoordinateSpaceConverter) -> ProbePanDelegate { ProbePanDelegate(axisAware: axisAware) }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        g.delegate = context.coordinator
        return g
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        if recognizer.state == .changed || recognizer.state == .began { counter.n += 1 }
    }
}

final class ProbePanDelegate: NSObject, UIGestureRecognizerDelegate {
    let axisAware: Bool
    init(axisAware: Bool) { self.axisAware = axisAware }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard axisAware, let p = g as? UIPanGestureRecognizer else { return true }
        let v = p.velocity(in: p.view)
        return abs(v.x) > abs(v.y)
    }
}

/// iOS 17 `.scrollView` coordinate spaces: is there an enclosing scroll view, and on which axes? (`bounds(of:)` is nil without one.)
struct ScrollSpaceProbe: View {
    let label: String
    let hits: ProbeHits

    var body: some View {
        if #available(iOS 17, *) {
            GeometryReader { proxy in
                let any = proxy.bounds(of: .scrollView) != nil
                let v = proxy.bounds(of: .scrollView(axis: .vertical)) != nil
                let h = proxy.bounds(of: .scrollView(axis: .horizontal)) != nil
                Color.clear.onAppear { hits.notes[label] = "\(any ? "S" : "-")\(v ? "V" : "-")\(h ? "H" : "-")" }
            }
        } else {
            Color.clear
        }
    }
}

/// Gesture-callback counter that SwiftUI does not observe (changing @State would re-render the page under the finger).
final class ProbeHits { var n = 0; var notes: [String: String] = [:] }
