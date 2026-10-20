import SwiftUI
import ZTronScrollView

/// One sequence-numbered log (outside any view body): `d` = the delegate, `m` = the `onZTronScroll…` delegate modifiers,
/// `p` = phase changes, `g` = a geometry observer, `v` = target visibility, `n` = the native ScrollView twin (iOS 18+).
/// A run of `didScroll` / `didZoom` of one tag is logged once, so a drag stays readable.
@MainActor
final class EventLog {
    private(set) var entries: [String] = []
    private var last: [String: String] = [:]
    private var sequence = 0

    func add(_ tag: String, _ name: String) {
        if name == "didScroll" || name == "didZoom", last[tag] == name { return }
        last[tag] = name
        sequence += 1
        entries.append("\(sequence) \(tag):\(name)")
    }
    func reset() { entries = []; last = [:]; sequence = 0 }
    var text: String { entries.joined(separator: " | ") }
}

@MainActor
final class EventDelegate: ZTronScrollViewDelegate {
    let log: EventLog
    init(_ log: EventLog) { self.log = log }
    func scrollViewDidScroll(_ s: ZTronScrollState) { log.add("d", "didScroll") }
    func scrollViewDidZoom(_ s: ZTronScrollState) { log.add("d", "didZoom") }
    func scrollViewWillBeginDragging(_ s: ZTronScrollState) { log.add("d", "willBeginDragging") }
    func scrollViewWillEndDragging(_ s: ZTronScrollState, withVelocity v: CGPoint, targetContentOffset: inout CGPoint) {
        log.add("d", "willEndDragging")
    }
    func scrollViewDidEndDragging(_ s: ZTronScrollState, willDecelerate d: Bool) { log.add("d", "didEndDragging(\(d))") }
    func scrollViewWillBeginDecelerating(_ s: ZTronScrollState) { log.add("d", "willBeginDecelerating") }
    func scrollViewDidEndDecelerating(_ s: ZTronScrollState) { log.add("d", "didEndDecelerating") }
    func scrollViewDidEndScrollingAnimation(_ s: ZTronScrollState) { log.add("d", "didEndScrollingAnimation") }
    func scrollViewWillBeginZooming(_ s: ZTronScrollState) { log.add("d", "willBeginZooming") }
    func scrollViewDidEndZooming(_ s: ZTronScrollState, atScale scale: CGFloat) { log.add("d", "didEndZooming") }
    func scrollViewShouldScrollToTop(_ s: ZTronScrollState) -> Bool { log.add("d", "shouldScrollToTop"); return true }
    func scrollViewDidScrollToTop(_ s: ZTronScrollState) { log.add("d", "didScrollToTop") }
    func scrollViewDidChangeAdjustedContentInset(_ s: ZTronScrollState) { log.add("d", "didChangeAdjustedContentInset") }
}

private struct EventRows: View {
    let ids: Bool
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<40, id: \.self) { i in
                if ids {
                    Text("Row \(i)").frame(maxWidth: .infinity, minHeight: 44).background(i.isMultiple(of: 2) ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                        .ztronScrollID(i)
                } else {
                    Text("Row \(i)").frame(maxWidth: .infinity, minHeight: 44).background(i.isMultiple(of: 2) ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                }
            }
        }
    }
}

@available(iOS 18, *)
private struct NativeTwin: View {
    let log: EventLog
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<40, id: \.self) { i in
                    Text("Row \(i)").frame(maxWidth: .infinity, minHeight: 44).background(i.isMultiple(of: 2) ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                }
            }
        }
        .onScrollPhaseChange { old, new in log.add("n", "\(old)>\(new)") }
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 0 }) { _, new in log.add("n", "g:offsetPositive=\(new)") }
    }
}

/// M7 session 2 / M8-8: the delegate, the 13 delegate modifiers, the phase / geometry / target-visibility observers in ONE log, with
/// a native `ScrollView` (iOS 18+) next to it for the order comparison. `Snapshot` publishes the logs as accessibility values.
struct EventLogScreen: View {
    @State private var state = ZTronScrollState()
    @State private var log = EventLog()
    @State private var nativeLog = EventLog()
    @State private var delegate: EventDelegate?
    @State private var logText = ""
    @State private var nativeText = ""

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Button("Reset") { reset() }.accessibilityIdentifier("Reset")
                Button("Snapshot") { logText = log.text; nativeText = nativeLog.text }.accessibilityIdentifier("Snapshot")
                Button("Top") { state.scrollToTop(animated: true) }.accessibilityIdentifier("Top")
            }
            ZTronScrollView(.vertical, state: state) { EventRows(ids: true) }
                .onZTronScrollDidScroll { _ in log.add("m", "didScroll") }
                .onZTronScrollDidZoom { _ in log.add("m", "didZoom") }
                .onZTronScrollWillBeginDragging { _ in log.add("m", "willBeginDragging") }
                .onZTronScrollWillEndDragging { _, _, _ in log.add("m", "willEndDragging") }
                .onZTronScrollDidEndDragging { _, d in log.add("m", "didEndDragging(\(d))") }
                .onZTronScrollWillBeginDecelerating { _ in log.add("m", "willBeginDecelerating") }
                .onZTronScrollDidEndDecelerating { _ in log.add("m", "didEndDecelerating") }
                .onZTronScrollDidEndScrollingAnimation { _ in log.add("m", "didEndScrollingAnimation") }
                .onZTronScrollWillBeginZooming { _ in log.add("m", "willBeginZooming") }
                .onZTronScrollDidEndZooming { _, _ in log.add("m", "didEndZooming") }
                .onZTronScrollShouldScrollToTop { _ in log.add("m", "shouldScrollToTop"); return true }
                .onZTronScrollDidScrollToTop { _ in log.add("m", "didScrollToTop") }
                .onZTronScrollDidChangeAdjustedContentInset { _ in log.add("m", "didChangeAdjustedContentInset") }
                .onScrollPhaseChange { old, new in log.add("p", "\(old)>\(new)") }
                .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 0 }) { _, new in log.add("g", "offsetPositive=\(new)") }
                .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.5) { ids in
                    log.add("v", "\(ids.first ?? -1)...\(ids.last ?? -1)")
                }
                .frame(height: 220)
                .border(Color.gray)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("zscroller")
            if #available(iOS 18, *) {
                NativeTwin(log: nativeLog)
                    .frame(height: 220)
                    .border(Color.gray)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("nscroller")
            }
            Text(logText).font(.system(size: 8)).lineLimit(6).accessibilityIdentifier("eventLog").accessibilityValue(logText)
            Text(nativeText).font(.system(size: 8)).lineLimit(3).accessibilityIdentifier("nativeLog").accessibilityValue(nativeText)
        }
        .padding(8)
        .onAppear {
            let d = EventDelegate(log)
            delegate = d
            state.delegate = d
        }
    }

    private func reset() {
        state.stopScrollingAndZooming()
        state.setContentOffset(.zero, animated: false)
        log.reset()
        nativeLog.reset()
        logText = ""
        nativeText = ""
    }
}
