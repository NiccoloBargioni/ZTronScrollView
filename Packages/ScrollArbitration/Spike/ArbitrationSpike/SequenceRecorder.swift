import UIKit
import ScrollArbitration

/// One touch sequence as seen by both sides. Derived arbiter facts (`first`, `owner`, `decided`) are computed
/// from the page arbiter's log slice on demand.
struct SequenceRecord {
    var id: Int
    var page: Int
    var arbiterLogStart: Int
    var open = true
    var panStates: [String] = ["possible"]
    var pagerMoved = false
    var pageBefore: Int
    var pageAfter: Int
    var boxMoved = false
    var buttonTaps = 0
    var uikitStart: CGPoint?
    var swiftuiStart: CGPoint?
    var observerStarted = false
    var observerEnded = false
    var panStarted = false
    var panEnded = false
    var foreignNames: Set<String> = []
}

/// Fed by the pager (UIKit side), the stand-in pages (SwiftUI side) and the arbiters' logs.
@MainActor final class SequenceRecorder {
    private(set) var records: [SequenceRecord] = []
    var arbiters: [ReferenceScrollArbiter] = []
    var onChange: (() -> Void)?
    private var nextID = 1

    var latest: SequenceRecord? { records.last }

    func clear() { records.removeAll(); onChange?() }

    func begin(page: Int, uikitPoint: CGPoint, pageIndex: Int) {
        records.append(SequenceRecord(id: nextID, page: page, arbiterLogStart: arbiters[page].log.count,
                                      pageBefore: pageIndex, pageAfter: pageIndex, uikitStart: uikitPoint))
        nextID += 1
        onChange?()
    }

    func mutate(_ body: (inout SequenceRecord) -> Void) {
        guard !records.isEmpty else { return }
        body(&records[records.count - 1])
        onChange?()
    }

    func panState(_ name: String) {
        mutate { if $0.panStates.last != name { $0.panStates.append(name) }; if name == "began" { $0.pagerMoved = false } }
    }

    // MARK: derived

    private func owners(_ r: SequenceRecord) -> (first: String, owner: String, decided: Int, dt: String) {
        let log = arbiters[r.page].log
        guard r.arbiterLogStart <= log.count else { return ("none", "none", 0, "na") }
        var first = "none", owner = "none", decided = 0, dt = "na"
        for entry in log[r.arbiterLogStart...] {
            if case let .owner(_, askedBy, _, tr, _, _, _, _, didDecide, result) = entry {
                if first == "none" { first = askedBy == .container ? "container" : "participant" }
                if didDecide { decided += 1; dt = String(format: "%.0f,%.0f", tr.width, tr.height); owner = result == .container ? "container" : "participant" }
            }
        }
        return (first, owner, decided, dt)
    }

    func line(_ r: SequenceRecord) -> String {
        let o = owners(r)
        var delta = "na"
        if let a = r.uikitStart, let b = r.swiftuiStart { delta = String(format: "%.2f", hypot(a.x - b.x, a.y - b.y)) }
        let pEnd = r.observerEnded && (!r.panStarted || r.panEnded) ? 1 : 0
        let foreign = r.foreignNames.isEmpty ? "" : " fn=" + r.foreignNames.sorted().joined(separator: ",")
        return "seq=\(r.id) first=\(o.first) owner=\(o.owner) decided=\(o.decided) pan=\(r.panStates.joined(separator: ">")) "
            + "pagerMoved=\(r.pagerMoved ? 1 : 0) page=\(r.pageBefore)>\(r.pageAfter) box=\(r.boxMoved ? 1 : 0) "
            + "button=\(r.buttonTaps) delta=\(delta) pEnd=\(pEnd) dt=\(o.dt) foreign=\(r.foreignNames.isEmpty ? 0 : 1)\(foreign)"
    }

    // MARK: SwiftUI side

    func swiftuiStart(_ p: CGPoint, fromPan: Bool) {
        mutate { r in if r.swiftuiStart == nil || fromPan { r.swiftuiStart = p } }
    }
    func observerStarted() { mutate { $0.observerStarted = true } }
    func observerEnded() { mutate { $0.observerEnded = true } }
    func panStartedSwiftUI() { mutate { $0.panStarted = true } }
    func panEndedSwiftUI() { mutate { $0.panEnded = true } }
    func boxMoved() { mutate { $0.boxMoved = true } }
    func buttonTapped() { mutate { $0.buttonTaps += 1 } }
}
