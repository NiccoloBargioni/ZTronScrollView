import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import ZTronScrollView
import ScrollArbitration

// UIKITPAN-s1 (spike U1, docs/design/UIKIT-pan.md §4). Demo only, never the library: the UIKit path the design proposes,
// rebuilt from demo types so its UIKit behaviour can be measured before U2/U3 build it. A copy of the passive D31 observer,
// one axis-aware `UIPanGestureRecognizer` per probe view (delegate variant V), the library's own pinch and double-tap types,
// and a demo scroller whose offset the probe pan drives (snap on `.ended` and on decline; body re-runs are fine here).
// Launch args: `-ZTronProbeV on|off|axis|ctl` (default axis; ctl = off + wait for UIControl recognizers), `-ZTronProbeRoute window` (the 15–17 window route on 18+ too),
// `-ZTronProbeResetAfter N` (reset the pan after N `.changed`, as the second-finger rule does), `-ZTronProbeEnvEnabled`
// (the shell's `\.isEnabled` read). Every reading goes to `ProbeHub` (counters `uikitpan.*`, per-frame channel ranges).

enum ProbeArgs {
    private static var args: [String] { ProcessInfo.processInfo.arguments }
    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static func flag(_ f: String) -> Bool { args.contains(f) }
    static var v: String { value("-ZTronProbeV") ?? "axis" }
    static var windowRoute: Bool {
        if value("-ZTronProbeRoute") == "window" { return true }
        if #available(iOS 18, *) { return false }
        return true
    }
    static var resetAfter: Int? { value("-ZTronProbeResetAfter").flatMap(Int.init) }
    static var envEnabled: Bool { flag("-ZTronProbeEnvEnabled") }
    /// Window route: `desc` = the design's `anchor.isDescendant(of: touch.view)` only; `root` (default) also accepts a hit view
    /// under the same view-controller root view as the anchor (measured: on 17.5 the hit view can be a sibling platform view).
    static var receiveRule: String { value("-ZTronProbeReceive") ?? "root" }
    /// `-ZTronProbeBoundary <h>[,<v>]`: a one-axis view accepts a drag within `h` (horizontal views) / `v` (vertical views) degrees
    /// of its axis (the design's rule is 45°, dominant axis); measured against UIKit's own nested scroll views (Q3e / Q3f).
    static var boundary: (h: Double, v: Double)? {
        guard let s = value("-ZTronProbeBoundary") else { return nil }
        let p = s.split(separator: ",").compactMap { Double($0) }
        guard let h = p.first else { return nil }
        return (h, p.count > 1 ? p[1] : h)
    }
}

@MainActor func probeCount(_ key: String) {
    #if DEBUG
    ZTronRenderCounters.increment(key)
    #endif
}

// MARK: - model: what the probe pan moves

/// A demo scroller: `content = viewport × factor`, offset clamped to the content (no rubber band), optional paging on x.
@MainActor
final class ProbeModel: ObservableObject {
    let name: String
    let axes: Axis.Set
    let paging: Bool
    @Published var off: CGPoint = .zero
    @Published var factor: CGSize
    var viewport: CGSize = .zero
    var start: CGPoint = .zero
    /// The offset `reset` restores, as a fraction of the movable range (0.5 = the middle).
    var home = CGPoint.zero

    init(name: String, axes: Axis.Set, paging: Bool, factor: CGSize) {
        self.name = name; self.axes = axes; self.paging = paging; self.factor = factor
    }

    var content: CGSize { CGSize(width: viewport.width * factor.width, height: viewport.height * factor.height) }
    var maxOff: CGPoint { CGPoint(x: max(0, content.width - viewport.width), y: max(0, content.height - viewport.height)) }
    var page: Int { viewport.width > 0 ? Int((off.x / viewport.width).rounded()) : 0 }

    /// The axis rule's "can move on": declared axis and scrollable bounds (the probe has no bounce or refresher inputs).
    func canMove(_ axis: Axis) -> Bool {
        axis == .horizontal ? axes.contains(.horizontal) && maxOff.x > 0.5 : axes.contains(.vertical) && maxOff.y > 0.5
    }

    /// Can the content follow a finger translation `t` along its dominant axis (not pinned at the edge it pushes against)?
    func canFollow(_ t: CGPoint) -> Bool {
        if abs(t.x) >= abs(t.y) {
            guard canMove(.horizontal) else { return false }
            return t.x < 0 ? off.x < maxOff.x - 0.5 : off.x > 0.5
        }
        guard canMove(.vertical) else { return false }
        return t.y < 0 ? off.y < maxOff.y - 0.5 : off.y > 0.5
    }

    func drag(_ t: CGPoint) {
        var o = off
        if canMove(.horizontal) { o.x = min(max(0, start.x - t.x), maxOff.x) }
        if canMove(.vertical) { o.y = min(max(0, start.y - t.y), maxOff.y) }
        if o != off { off = o }
    }

    /// Paging snap (velocity projected 0.15 s, at most one page from the start); plain scrollers stay.
    func settle(velocity: CGPoint) {
        guard paging, viewport.width > 0 else { return }
        let w = viewport.width
        let from = (start.x / w).rounded()
        let projected = ((off.x - velocity.x * 0.15) / w).rounded()
        let target = min(max(projected, from - 1), from + 1)
        let x = min(max(0, target * w), maxOff.x)
        if x != off.x { off.x = x }
    }

    func reset() {
        off = CGPoint(x: (maxOff.x * home.x).rounded(), y: (maxOff.y * home.y).rounded())
        start = off
    }
}

// MARK: - hub: sequences, counters, per-frame channels

@MainActor
final class ProbeHub {
    static let shared = ProbeHub()

    private(set) var models: [String: ProbeModel] = [:]
    private var drivers: [String: ProbePanDriver] = [:]
    weak var pageScroll: UIScrollView?
    weak var nativeScroll: UIScrollView?
    private weak var observer: ProbeObserver?

    // Sequence state (the observer's touch-down starts one, the last lift ends it).
    private(set) var touches = 0
    var maxTouches = 0
    var secondFinger = false
    /// Arbiter emulation (D28 rule 5): the inner view that claimed this sequence, if any.
    var owner: String?
    private var lift: [String] = []
    /// Taps on the readout are sequences too: only a sequence with motion (or a second touch) writes `lift` / `maxT`.
    private var moved = 0
    private var firstShouldBegin: String?
    private var beganAt: String?
    /// Window location of the sequence's first touch (Q5: finger travel at the first `shouldBegin` and at `.began`).
    var downAt: CGPoint?
    var notes: [String: String] = [:]

    // Per-frame channels: current value, range, and frames in which the page and some target both moved.
    private var cur: [String: CGFloat] = [:]
    private var lo: [String: CGFloat] = [:]
    private var hi: [String: CGFloat] = [:]
    private var last: [String: CGFloat] = [:]
    private var bothPT = 0

    func model(_ name: String, axes: Axis.Set, paging: Bool = false, factor: CGSize, home: CGPoint = .zero) -> ProbeModel {
        if let m = models[name] { return m }
        let m = ProbeModel(name: name, axes: axes, paging: paging, factor: factor)
        m.home = home
        models[name] = m
        return m
    }

    func driver(_ name: String, model: ProbeModel, detectedAxis: Axis? = nil) -> ProbePanDriver {
        if let d = drivers[name] { return d }
        let d = ProbePanDriver(name: name, model: model, detectedAxis: detectedAxis)
        drivers[name] = d
        return d
    }

    func driverNamed(_ name: String) -> ProbePanDriver? { drivers[name] }

    func installObserver(on window: UIWindow?) {
        guard let window else { return }
        if let o = observer, o.view === window { return }
        observer?.view?.removeGestureRecognizer(observer!)
        let o = ProbeObserver()
        window.addGestureRecognizer(o)
        observer = o
        probeCount("probe.obs.installed")
    }

    // Observer callbacks.
    func touchDown(count: Int) {
        if touches == 0 {
            maxTouches = 0; secondFinger = false; owner = nil; lift = []; moved = 0
            firstShouldBegin = nil; beganAt = nil
            for d in drivers.values { d.sequenceBegan() }
        }
        touches = count
        maxTouches = max(maxTouches, count)
        if count >= 2, !secondFinger {
            secondFinger = true
            probeCount("uikitpan.secondFinger")
            for d in drivers.values { d.resetForSecondFinger() }
        }
    }

    func touchMoved() { moved += 1 }

    func touchUp(remaining: Int) {
        touches = remaining
        if remaining == 0, moved > 2 || maxTouches > 1 {
            lift.append("obs")
            notes["lift"] = lift.joined(separator: "<")
            notes["maxT"] = "\(maxTouches)"
        }
    }

    func panLifted(_ name: String) {
        lift.append("pan:\(name)")
        notes["lift"] = lift.joined(separator: "<")
    }

    /// Q5: the first `shouldBegin` of a sequence (translation and velocity lengths) and the translation at `.began`.
    func noteShouldBegin(_ t: CGPoint, _ v: CGPoint, source: String, at loc: CGPoint) {
        guard firstShouldBegin == nil else { return }
        if let d = downAt { notes["fsbD"] = String(format: "%.1f", hypot(loc.x - d.x, loc.y - d.y)) }
        firstShouldBegin = String(format: "%.1f", hypot(t.x, t.y))
        notes["fsb"] = firstShouldBegin
        notes["fsbV"] = String(format: "%.0f", hypot(v.x, v.y))
        notes["fsbSrc"] = source
        notes["fsbXY"] = String(format: "%.1f,%.1f", t.x, t.y)
    }

    func noteBegan(_ t: CGPoint, at loc: CGPoint) {
        guard beganAt == nil else { return }
        if let d = downAt { notes["btD"] = String(format: "%.1f", hypot(loc.x - d.x, loc.y - d.y)) }
        beganAt = String(format: "%.1f", hypot(t.x, t.y))
        notes["bt"] = beganAt
    }

    private var others = Set<String>()
    func noteOther(_ g: UIGestureRecognizer) {
        let n = String(String(describing: type(of: g)).prefix(28)) + (g.view.map { "@" + String(String(describing: type(of: $0)).prefix(18)) } ?? "")
        if others.insert(n).inserted { notes["others"] = others.sorted().joined(separator: ",") }
    }

    // Channels.
    private func sample(_ key: String, _ value: CGFloat) -> Bool {
        cur[key] = value
        lo[key] = min(lo[key] ?? value, value)
        hi[key] = max(hi[key] ?? value, value)
        defer { last[key] = value }
        guard let l = last[key] else { return false }
        return abs(value - l) > 0.5
    }

    func tick() {
        var pageMoved = false, targetMoved = false
        if let p = pageScroll { pageMoved = sample("page.y", p.contentOffset.y) }
        if let n = nativeScroll {
            if sample("native.x", n.contentOffset.x) { targetMoved = true }
            if sample("native.y", n.contentOffset.y) { targetMoved = true }
        }
        for (name, m) in models {
            if sample("\(name).x", m.off.x) { targetMoved = true }
            if sample("\(name).y", m.off.y) { targetMoved = true }
        }
        if pageMoved && targetMoved { bothPT += 1 }
    }

    func resetReadings() {
        lo = [:]; hi = [:]; last = [:]; cur = [:]; bothPT = 0; notes = [:]; others = []
        firstShouldBegin = nil; beganAt = nil; lift = []
        #if DEBUG
        ZTronRenderCounters.reset()
        #endif
    }

    func resetPositions() {
        for m in models.values { m.reset() }
    }

    var summary: String {
        func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
        var s = "os=\(UIDevice.current.systemVersion) v=\(ProbeArgs.v) route=\(ProbeArgs.windowRoute ? "window" : "repr") bothPT=\(bothPT)"
        for k in cur.keys.sorted() {
            s += " \(k)=\(f(cur[k] ?? 0)) \(k).span=\(f((hi[k] ?? 0) - (lo[k] ?? 0)))"
        }
        for (name, m) in models.sorted(by: { $0.key < $1.key }) where m.paging { s += " \(name).page=\(m.page)" }
        for k in notes.keys.sorted() { s += " \(k)=\(notes[k] ?? "")" }
        #if DEBUG
        let c = ZTronRenderCounters.snapshot
        for k in c.keys.sorted() where k.hasPrefix("uikitpan.") || k.hasPrefix("probe.") || k.hasPrefix("ctl.") || k == "button.fired" {
            s += " c.\(k)=\(c[k] ?? 0)"
        }
        #endif
        return s
    }
}

// MARK: - the passive observer (copy of the library's D31 `UIKitTouchObserverRecognizer`)

/// Never recognizes, never cancels, delays or prevents; installed on the window; reports touch counts to the hub.
@MainActor
final class ProbeObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var active = Set<ObjectIdentifier>()

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
        allowedTouchTypes = [UITouch.TouchType.direct, .pencil].map { NSNumber(value: $0.rawValue) }
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if active.isEmpty { ProbeHub.shared.downAt = touches.first?.location(in: nil) }
        for t in touches { active.insert(ObjectIdentifier(t)) }
        probeCount("probe.obs.began")
        ProbeHub.shared.touchDown(count: active.count)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        probeCount("probe.obs.moved")
        ProbeHub.shared.touchMoved()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        lifted(touches, "probe.obs.ended")
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        lifted(touches, "probe.obs.cancelled")
    }

    private func lifted(_ touches: Set<UITouch>, _ key: String) {
        for t in touches { active.remove(ObjectIdentifier(t)) }
        probeCount(key)
        ProbeHub.shared.touchUp(remaining: active.count)
    }

    override func reset() {
        super.reset()
        if !active.isEmpty { active = []; ProbeHub.shared.touchUp(remaining: 0) }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
}

// MARK: - the probe pan: delegate (axis rule, variant V) and action

@MainActor
final class ProbePanDriver: NSObject, UIGestureRecognizerDelegate {
    let name: String
    let model: ProbeModel
    /// The detected native scroller's axis (N: the page's vertical axis); nil = none (V axis then answers like V on).
    let detectedAxis: Axis?
    weak var recognizer: UIPanGestureRecognizer?
    /// Window route only: the zero-size view at the viewport's top-leading corner.
    weak var anchor: UIView?
    var envEnabled = true
    private var sequenceAxis: Axis?
    private var active = false
    private var moves = true
    private var changes = 0
    private var resetting = false
    private var resetPending = false
    /// Inner views (the zoomer) claim the sequence when they can follow the drag; outer views then hold still.
    var isInner = false

    init(name: String, model: ProbeModel, detectedAxis: Axis?) {
        self.name = name; self.model = model; self.detectedAxis = detectedAxis
        super.init()
    }

    func configure(_ g: UIPanGestureRecognizer) {
        g.maximumNumberOfTouches = 1
        g.cancelsTouchesInView = false
        g.delaysTouchesBegan = false
        g.delaysTouchesEnded = false
        g.allowedTouchTypes = [UITouch.TouchType.direct, .pencil].map { NSNumber(value: $0.rawValue) }
        g.name = scrollArbitrationGestureName
        g.delegate = self
        recognizer = g
        probeCount("uikitpan.made")
    }

    func sequenceBegan() { sequenceAxis = nil; changes = 0 }

    private func count(_ k: String) { probeCount("uikitpan.\(k)"); probeCount("uikitpan.\(name).\(k)") }

    /// Dominant axis: translation when ≥ 8 pt, else velocity; 45° boundary; a tie is nil (the caller sends it to the other axis).
    private func axis(of p: UIPanGestureRecognizer) -> (Axis?, String) {
        let t = p.translation(in: p.view), v = p.velocity(in: p.view)
        let useT = hypot(t.x, t.y) >= 8
        let s = useT ? t : v
        let a: Axis? = abs(s.x) > abs(s.y) ? .horizontal : abs(s.y) > abs(s.x) ? .vertical : nil
        return (a, useT ? "t" : "v")
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let p = g as? UIPanGestureRecognizer else { return false }
        let (a, src) = axis(of: p)
        ProbeHub.shared.noteShouldBegin(p.translation(in: p.view), p.velocity(in: p.view), source: src, at: p.location(in: nil))
        count(src == "t" ? "decide.trans" : "decide.vel")
        let ok: Bool
        if ProbeHub.shared.secondFinger || !envEnabled {
            ok = false
        } else if let b = ProbeArgs.boundary, model.canMove(.horizontal) != model.canMove(.vertical) {
            let s = src == "t" ? p.translation(in: p.view) : p.velocity(in: p.view)
            let fromAxis = model.canMove(.horizontal) ? atan2(abs(s.y), abs(s.x)) : atan2(abs(s.x), abs(s.y))
            ok = fromAxis * 180 / .pi <= (model.canMove(.horizontal) ? b.h : b.v)
            count(ok ? "boundary.in" : "boundary.out")
        } else if let a {
            ok = model.canMove(a)
            count(a == .horizontal ? "axis.h" : "axis.v")
        } else {
            ok = model.canMove(.horizontal) && model.canMove(.vertical)
            count("axis.tie")
        }
        sequenceAxis = a
        count(ok ? "shouldBegin.yes" : "shouldBegin.no")
        if !ok {
            count("declined")
            model.settle(velocity: .zero)
        }
        return ok
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        if other.name == scrollArbitrationGestureName { return true }
        ProbeHub.shared.noteOther(other)
        count("simul.ask")
        switch ProbeArgs.v {
        case "on": return true
        case "off", "ctl": return false
        default:
            guard let d = detectedAxis, let p = g as? UIPanGestureRecognizer else { return true }
            let a = sequenceAxis ?? axis(of: p).0
            let takes = a == d && model.canMove(d)
            if takes { count("simul.axisNo") }
            return !takes
        }
    }

    /// V `ctl` (Q7): V off, the pan waits for a recognizer on a `UIControl` (UISlider's own pan on 26+) to fail, and it never
    /// receives a touch whose hit view is a UISlider / UISwitch (`shouldReceive`).
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        guard ProbeArgs.v == "ctl", other.view is UIControl else { return false }
        count("requireFailure.control")
        return true
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }

    /// Window route: the touch began inside the viewport rect and UIKit's hit view contains the anchor (`desc`, the design's
    /// rule) or shares the anchor's view-controller root view (`root`). Both answers are counted; `-ZTronProbeReceive` picks.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // V `ctl`: a drag that starts on a control whose value follows the finger stays the control's (17.5's UISlider has no recognizer
        // to wait for).
        if ProbeArgs.v == "ctl", touch.view is UISlider || touch.view is UISwitch {
            count("receive.control")
            return false
        }
        guard let anchor else { return true }
        guard CGRect(origin: .zero, size: model.viewport).contains(touch.location(in: anchor)) else {
            count("receive.noRect")
            return false
        }
        let tv = touch.view
        let desc = tv.map { anchor.isDescendant(of: $0) } ?? false
        let root = tv.map { Self.controllerRoot(of: anchor) === Self.controllerRoot(of: $0) } ?? false
        count(desc ? "receive.desc.yes" : "receive.desc.no")
        count(root ? "receive.root.yes" : "receive.root.no")
        ProbeHub.shared.notes["tv.\(name)"] = tv.map { String(String(describing: type(of: $0)).prefix(30)) } ?? "nil"
        let ok = ProbeArgs.receiveRule == "desc" ? desc : desc || root
        count(ok ? "receive.yes" : "receive.no")
        return ok
    }

    /// The root view of the nearest view controller above `v` (its hosting controller's view, a sheet's, a navigation controller's).
    static func controllerRoot(of v: UIView) -> UIView {
        var c = v
        while !(c.next is UIViewController), let s = c.superview { c = s }
        return c
    }

    func action(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: g.view)
        let hub = ProbeHub.shared
        switch g.state {
        case .began:
            count("began")
            active = true; changes = 0
            hub.noteBegan(t, at: g.location(in: nil))
            model.start = model.off
            if isInner {
                moves = model.canFollow(t)
                if moves { hub.owner = name }
            } else {
                moves = hub.owner == nil
            }
            if moves { model.drag(t) }
        case .changed:
            count("changed")
            changes += 1
            if !isInner, moves, hub.owner != nil, hub.owner != name {
                moves = false
                model.off = model.start
            }
            if moves { model.drag(t) }
            if let n = ProbeArgs.resetAfter, changes == n { hub.secondFinger = true; resetForSecondFinger() }
        case .ended:
            count("ended")
            active = false
            hub.panLifted(name)
            if moves { model.settle(velocity: g.velocity(in: g.view)) }
        case .cancelled:
            count("cancelled")
            if resetting { count("cancelled.sync") } else if resetPending { count("cancelled.async") }
            resetPending = false
            active = false
            if moves { model.settle(velocity: .zero) }
        default:
            break
        }
    }

    /// Second finger (design §2): an active pan ends exactly once, then the recognizer is reset (isEnabled off and on).
    func resetForSecondFinger() {
        guard let g = recognizer else { return }
        if active {
            count("secondFinger.end")
            active = false
            model.settle(velocity: .zero)
        }
        count("reset")
        count("reset.state\(g.state.rawValue)")
        resetting = true
        resetPending = true
        g.isEnabled = false
        g.isEnabled = true
        resetting = false
        DispatchQueue.main.async { [weak self] in self?.resetPending = false }
    }
}

// MARK: - install routes

/// 18+: SwiftUI hit-tests the recognizer (the DBG-s8 shape, `.gesture(_:)` on the viewport).
@available(iOS 18.0, *)
struct ProbePanRepresentable: UIGestureRecognizerRepresentable {
    let driver: ProbePanDriver

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let g = UIPanGestureRecognizer()
        driver.configure(g)
        return g
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        driver.action(recognizer)
    }
}

/// Zero-size anchor: installs the window observer, and on the window route the pan (on the window, like D31).
struct ProbeAnchor: UIViewRepresentable {
    let windowDriver: ProbePanDriver?

    func makeUIView(context: Context) -> ProbeAnchorView {
        let v = ProbeAnchorView()
        v.isUserInteractionEnabled = false
        if let d = windowDriver {
            let g = UIPanGestureRecognizer(target: v, action: #selector(ProbeAnchorView.fire(_:)))
            d.configure(g)
            d.anchor = v
            v.driver = d
            v.pan = g
        }
        return v
    }

    func updateUIView(_ view: ProbeAnchorView, context: Context) {}

    static func dismantleUIView(_ view: ProbeAnchorView, coordinator: ()) {
        if let g = view.pan { g.view?.removeGestureRecognizer(g) }
    }
}

final class ProbeAnchorView: UIView {
    var driver: ProbePanDriver?
    var pan: UIPanGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        ProbeHub.shared.installObserver(on: window)
        if let g = pan, g.view !== window {
            g.view?.removeGestureRecognizer(g)
            window?.addGestureRecognizer(g)
        }
    }

    @objc func fire(_ g: UIPanGestureRecognizer) { driver?.action(g) }
}

/// Finds the nearest enclosing `UIScrollView` (the native page, or a native baseline target) for the per-frame sampler.
struct ProbeScrollFinder: UIViewRepresentable {
    let page: Bool
    func makeUIView(context: Context) -> FinderView { let v = FinderView(); v.page = page; v.isUserInteractionEnabled = false; return v }
    func updateUIView(_ view: FinderView, context: Context) {}

    final class FinderView: UIView {
        var page = true
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var cur = superview
            while let c = cur, !(c is UIScrollView) { cur = c.superview }
            guard let sv = cur as? UIScrollView else { return }
            if page { ProbeHub.shared.pageScroll = sv } else { ProbeHub.shared.nativeScroll = sv }
        }
    }
}

/// Calls `ProbeHub.tick()` once per display frame.
struct ProbeTicker: UIViewRepresentable {
    func makeUIView(context: Context) -> TickView { TickView() }
    func updateUIView(_ view: TickView, context: Context) {}

    final class TickView: UIView {
        private var link: CADisplayLink?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate(); link = nil
            guard window != nil else { return }
            let l = CADisplayLink(target: self, selector: #selector(tick))
            l.add(to: .main, forMode: .common)
            link = l
        }
        @objc private func tick() { ProbeHub.shared.tick() }
    }
}

// MARK: - the probe stack on a view

/// The UIKit path's gestures on a viewport: the probe pan (route by OS), the passive observer, and the library's own pinch
/// and double-tap types, attached the way `PinchGestureAttach` attaches them.
struct ProbeStack: ViewModifier {
    let driver: ProbePanDriver
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let window = ProbeArgs.windowRoute
        if ProbeArgs.envEnabled {
            driver.envEnabled = isEnabled
            driver.recognizer?.isEnabled = isEnabled
        }
        return content
            .modifier(ProbePinchTap())
            .modifier(ProbePanAttach(driver: driver, window: window))
            .background(alignment: .topLeading) { ProbeAnchor(windowDriver: window ? driver : nil).frame(width: 0, height: 0) }
    }
}

private struct ProbePanAttach: ViewModifier {
    let driver: ProbePanDriver
    let window: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *), !window {
            content.gesture(ProbePanRepresentable(driver: driver))
        } else {
            content
        }
    }
}

private struct ProbePinchTap: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            let n = scrollArbitrationGestureName
            content
                .simultaneousGesture(MagnifyGesture().onChanged { _ in probeCount("probe.pinch") }, name: n, isEnabled: true)
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { _ in probeCount("probe.doubleTap") }, name: n, isEnabled: true)
        } else if #available(iOS 17, *) {
            content
                .simultaneousGesture(MagnifyGesture().onChanged { _ in probeCount("probe.pinch") })
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { _ in probeCount("probe.doubleTap") })
        } else if #available(iOS 16, *) {
            content
                .simultaneousGesture(MagnificationGesture().onChanged { _ in probeCount("probe.pinch") })
                .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { _ in probeCount("probe.doubleTap") })
        } else {
            content
                .simultaneousGesture(MagnificationGesture().onChanged { _ in probeCount("probe.pinch") })
                .simultaneousGesture(TapGesture(count: 2).onEnded { probeCount("probe.doubleTap") })
        }
    }
}

/// A probe view: content laid out at `viewport × factor`, drawn at `-offset`, clipped, with the probe stack.
struct ProbeScroller<Content: View>: View {
    @ObservedObject var model: ProbeModel
    let driver: ProbePanDriver
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        GeometryReader { g in
            content(g.size)
                .frame(width: g.size.width * model.factor.width, height: g.size.height * model.factor.height, alignment: .topLeading)
                .offset(x: -model.off.x, y: -model.off.y)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                .onAppear { model.viewport = g.size; model.reset() }
                .onChange(of: g.size) { s in
                    let page = model.page
                    model.viewport = s
                    if model.paging { model.off.x = min(CGFloat(page) * s.width, model.maxOff.x) }
                }
        }
        .clipped()
        .contentShape(Rectangle())
        .modifier(ProbeStack(driver: driver))
    }
}

/// Info / Reset readout for the probe screens (`probe.info` → `probe.text`, `probe.reset`).
struct ProbeReadout: View {
    var extra: () -> String = { "" }
    var onReset: () -> Void = {}
    @State private var text = ""

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 16) {
                Button("Info") { text = ProbeHub.shared.summary + " " + extra() }.accessibilityIdentifier("probe.info")
                Button("Reset") {
                    ProbeHub.shared.resetPositions()
                    onReset()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ProbeHub.shared.resetReadings() }
                }.accessibilityIdentifier("probe.reset")
            }
            .font(.footnote)
            Text(text).font(.system(size: 7)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("probe.text").accessibilityValue(text)
        }
        .padding(.horizontal, 8)
    }
}
