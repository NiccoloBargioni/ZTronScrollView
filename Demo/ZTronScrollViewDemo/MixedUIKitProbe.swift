import SwiftUI
import UIKit

/// DBG-s8 diagnostics (not for the library; UIKit lives in the demo app only): logs, per touch, the gesture recognizers that receive it, the chain of
/// scroll views above the hit view, the state of their pan recognizers every frame, and (KVO) every state / enabled change of the recognizers of the touch
/// with the call stack that made it, to a host file. Enabled by `-ZTronProbe <tag> -ZTronProbeDir <dir>` (the file is `<dir>/probe-<tag>.log`; the simulator
/// writes to host paths), so nothing runs in a normal launch. `MixedProbeUITests` passes both (`ZS_PROBE=1`).
enum MixedProbeLog {
    private static func argument(_ name: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: name), i + 1 < a.count { return a[i + 1] }
        return nil
    }
    static let tag: String? = argument("-ZTronProbe")
    static let dir = argument("-ZTronProbeDir") ?? NSTemporaryDirectory()
    static let t0 = CACurrentMediaTime()
    static func log(_ s: String) {
        guard let tag else { return }
        let line = String(format: "%8.3f %@\n", CACurrentMediaTime() - t0, s)
        let path = "\(dir)/probe-\(tag).log"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
        }
    }
}

struct ProbeInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeAnchor { ProbeAnchor() }
    func updateUIView(_ v: ProbeAnchor, context: Context) {}
}

final class ProbeAnchor: UIView {
    private var logger: ProbeTouchLogger?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard MixedProbeLog.tag != nil, let w = window, logger == nil else { return }
        let l = ProbeTouchLogger(target: nil, action: nil)
        w.addGestureRecognizer(l)
        logger = l
        MixedProbeLog.log("probe installed os=\(UIDevice.current.systemVersion) args=\(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
    }
}

private func short(_ g: UIGestureRecognizer) -> String {
    let n = String(describing: type(of: g))
    let v = g.view.map { String(String(describing: type(of: $0)).prefix(30)) } ?? "nil"
    let d = g.delegate.map { String(String(describing: type(of: $0)).prefix(34)) } ?? "nil"
    return "\(n)[st=\(g.state.rawValue) en=\(g.isEnabled ? 1 : 0) cancels=\(g.cancelsTouchesInView ? 1 : 0) on=\(v) del=\(d)\(g.name.map { " name=\($0)" } ?? "")]"
}

private func scrollViews(from v: UIView?) -> [UIScrollView] {
    var out: [UIScrollView] = []
    var cur = v
    while let c = cur { if let s = c as? UIScrollView { out.append(s) }; cur = c.superview }
    return out
}

/// Sees every touch of the window without interfering (never begins, never cancels, recognizes simultaneously with everything).
final class ProbeTouchLogger: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var link: CADisplayLink?
    private weak var hit: UIView?
    private var last = ""
    private var moves = 0
    private let kvo = ProbeKVO()
    private var watched: [(NSObject, [String])] = []

    private func watch(_ t: UITouch) {
        unwatch()
        for g in t.gestureRecognizers ?? [] where !(g is ProbeTouchLogger) { add(g, ["state", "enabled"]) }
        for sv in scrollViews(from: t.view) { add(sv, ["scrollEnabled"]); add(sv.panGestureRecognizer, ["state", "enabled"]) }
    }

    private func add(_ o: NSObject, _ keys: [String]) {
        if watched.contains(where: { $0.0 === o }) { return }
        for k in keys { o.addObserver(kvo, forKeyPath: k, options: [.old, .new], context: nil) }
        watched.append((o, keys))
    }

    private func unwatch() {
        for (o, keys) in watched { for k in keys { o.removeObserver(kvo, forKeyPath: k) } }
        watched = []
    }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false; delegate = self
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy o: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf o: UIGestureRecognizer) -> Bool { false }

    private func dump(_ t: UITouch, _ p: String) {
        let l = t.location(in: view)
        let hitName = t.view.map { String(describing: type(of: $0)) } ?? "nil"
        let grs = (t.gestureRecognizers ?? []).filter { !($0 is ProbeTouchLogger) }.map(short).joined(separator: "; ")
        MixedProbeLog.log("TOUCH \(p) (\(Int(l.x)),\(Int(l.y))) hit=\(hitName) grs=[\(grs)]")
    }

    private func chain(_ t: UITouch) {
        var cur = t.view
        var depth = 0
        while let c = cur, depth < 40 {
            let grs = (c.gestureRecognizers ?? []).map(short).joined(separator: "; ")
            let extra = (c as? UIScrollView).map { " [scroll enabled=\($0.isScrollEnabled) off=\(Int($0.contentOffset.y)) panDel=\($0.panGestureRecognizer.delegate.map { String(describing: type(of: $0)) } ?? "nil")]" } ?? ""
            if !grs.isEmpty || !extra.isEmpty { MixedProbeLog.log("  CHAIN \(depth) \(type(of: c))\(extra) grs=[\(grs)]") }
            cur = c.superview; depth += 1
        }
    }

    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent) {
        super.touchesBegan(t, with: e)
        guard let t = t.first else { return }
        moves = 0; last = ""; hit = t.view
        chain(t); dump(t, "began"); watch(t)
        if link == nil { let l = CADisplayLink(target: self, selector: #selector(tick)); l.add(to: .main, forMode: .common); link = l }
    }

    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent) {
        super.touchesMoved(t, with: e)
        guard let t = t.first else { return }
        moves += 1
        if moves <= 3 || moves % 10 == 0 { dump(t, "moved#\(moves)") }
    }

    override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent) { super.touchesEnded(t, with: e); finish(t, "ended") }
    override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent) { super.touchesCancelled(t, with: e); finish(t, "cancelled") }

    private func finish(_ t: Set<UITouch>, _ p: String) {
        if let t = t.first { dump(t, p) }
        tick()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.tick(); self?.link?.invalidate(); self?.link = nil; self?.unwatch() }
    }

    /// Per frame: the pan recognizers of the scroll views above the hit view, logged when something changes.
    @objc private func tick() {
        guard let h = hit else { return }
        let s = scrollViews(from: h).map { sv in
            "\(type(of: sv)) pan=\(sv.panGestureRecognizer.state.rawValue) en=\(sv.panGestureRecognizer.isEnabled ? 1 : 0) off=\(Int(sv.contentOffset.x)),\(Int(sv.contentOffset.y)) drag=\(sv.isDragging ? 1 : 0) track=\(sv.isTracking ? 1 : 0)"
        }.joined(separator: " | ")
        if s != last { last = s; MixedProbeLog.log("SCROLL \(s)") }
    }
}

@_silgen_name("swift_demangle")
private func _demangle(_ name: UnsafePointer<CChar>?, _ length: UInt, _ out: UnsafeMutablePointer<CChar>?, _ outLen: UnsafeMutablePointer<UInt>?, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?

private func demangled(_ s: String) -> String {
    guard s.hasPrefix("$s") || s.hasPrefix("_$s") else { return s }
    return s.withCString { p in
        guard let r = _demangle(p, UInt(strlen(p)), nil, nil, 0) else { return s }
        defer { free(r) }
        return String(cString: r)
    }
}

/// "3   UIKitCore   0x000000010a2b3c4d -[UIGestureRecognizer setState:] + 123" -> "UIKitCore -[UIGestureRecognizer setState:]"
private func condensed(_ frames: [String], skip: Int, take: Int) -> String {
    frames.dropFirst(skip).prefix(take).map { line -> String in
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count > 3 else { return line }
        let module = parts[1]
        var sym = parts[3...].joined(separator: " ")
        if let r = sym.range(of: " + ", options: .backwards) { sym = String(sym[..<r.lowerBound]) }
        let d = String(demangled(sym).prefix(110))
        return "\(module):\(d)"
    }.joined(separator: " <- ")
}

/// KVO on recognizer state / enabled and scroll view scrollEnabled; logs the old/new value and WHO set it (call stack).
final class ProbeKVO: NSObject {
    static let stackKeys: Set<String> = ["state", "enabled", "scrollEnabled"]

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath else { return }
        let old = change?[.oldKey].map { "\($0)" } ?? "-", new = change?[.newKey].map { "\($0)" } ?? "-"
        guard old != new else { return }
        let who: String
        if let g = object as? UIGestureRecognizer { who = String(String(describing: type(of: g)).prefix(34)) + (g.view.map { "@" + String(String(describing: type(of: $0)).prefix(20)) } ?? "") }
        else if let o = object { who = String(describing: type(of: o)) } else { who = "?" }
        var s = "KVO \(who).\(keyPath) \(old)->\(new)"
        if Self.stackKeys.contains(keyPath) { s += "\n      stack: " + condensed(Thread.callStackSymbols, skip: 2, take: 14) }
        MixedProbeLog.log(s)
    }
}
