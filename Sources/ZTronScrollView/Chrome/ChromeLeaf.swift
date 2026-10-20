import SwiftUI
import ZTronScrollPhysics

// The one way a chrome element reads hot values (design M8-chrome §1, SPEC S4.3): a leaf in the viewport overlay that
// re-renders only when a channel it DECLARES changes, on both storage paths. The container's body and the content never
// see these reads, so scrolling, zooming and flashing run no content body (tier 0).

/// The channels a ``ChromeLeaf`` wakes on. The fallback path's four observation channels (SPEC S4.5); `.offset` and
/// `.zoom` carry the presentation values (what is drawn), `.metrics` the cold layout facts, `.phase` the interaction
/// phase and flags.
struct ChannelSet: OptionSet, Sendable {
    let rawValue: Int
    static let offset = ChannelSet(rawValue: 1 << 0)
    static let zoom = ChannelSet(rawValue: 1 << 1)
    static let phase = ChannelSet(rawValue: 1 << 2)
    static let metrics = ChannelSet(rawValue: 1 << 3)
    static let all: ChannelSet = [.offset, .zoom, .phase, .metrics]

    var stateChannels: Set<StateChannel> {
        var channels = Set<StateChannel>()
        if contains(.offset) { channels.insert(.offset) }
        if contains(.zoom) { channels.insert(.zoom) }
        if contains(.phase) { channels.insert(.phase) }
        if contains(.metrics) { channels.insert(.metrics) }
        return channels
    }
}

/// What a leaf sees: one consistent read of the state. The fields of a channel the leaf did not declare are current at
/// the time of the read but do not wake the leaf when they change (a snapshot, never tracked).
struct ChromeSample: Equatable {
    /// Presentation offset in scaled viewport points (UIKit `contentOffset`).
    var offset: CGPoint
    var zoom: CGFloat
    var phase: ZTronScrollPhase
    var metrics: ScrollMetrics
    /// Signed distance outside the scrollable bounds per axis, in viewport points: negative before the start edge,
    /// positive past the end edge, 0 inside (the rubber band's stretch). Derived from `offset`, `zoom` and `metrics`.
    var overshoot: CGPoint

    /// `offset` minus its clamp into the bounds of `metrics` at `zoom` (`AxisBounds.overscroll(of:)` per axis).
    static func overshoot(offset: CGPoint, zoom: CGFloat, metrics m: ScrollMetrics) -> CGPoint {
        let i = m.adjustedContentInset
        let x = AxisGeometry(viewportLength: m.viewportSize.width, unscaledContentLength: m.contentSize.width,
                             insets: AxisInsets(start: i.leading, end: i.trailing))
        let y = AxisGeometry(viewportLength: m.viewportSize.height, unscaledContentLength: m.contentSize.height,
                             insets: AxisInsets(start: i.top, end: i.bottom))
        return CGPoint(x: x.bounds(at: zoom).overscroll(of: offset.x), y: y.bounds(at: zoom).overscroll(of: offset.y))
    }
}

extension ZTronScrollState {
    /// A sample with TRACKED reads for the declared `channels` (Observation access on 17+, the relay's channels on 15–16)
    /// and untracked reads for the others, so a body that calls this wakes on the declared channels only.
    func chromeSample(_ channels: ChannelSet) -> ChromeSample {
        let live = storage
        // The snapshot is only taken for a field the leaf did not declare: a leaf on every channel reads nothing twice.
        func read<T>(_ channel: ChannelSet, _ tracked: () -> T, _ snapshot: (StorageSnapshot) -> T) -> T {
            channels.contains(channel) ? tracked() : snapshot(live.snapshot())
        }
        let offset = read(.offset, { live.presentationOffset }, { $0.presentationOffset })
        let zoom = read(.zoom, { live.presentationZoom }, { $0.presentationZoom })
        let phase = read(.phase, { live.phase }, { $0.phase })
        let metrics = read(.metrics, { live.metrics }, { $0.metrics })
        return ChromeSample(offset: offset, zoom: zoom, phase: phase, metrics: metrics,
                            overshoot: ChromeSample.overshoot(offset: offset, zoom: zoom, metrics: metrics))
    }
}

/// A leaf that renders `body(sample)` and re-evaluates only when a declared channel is written. Place it in the viewport
/// overlay (chrome) or a `background`; never wrap the content in it. The closure runs inside the leaf's own body, so
/// the hot reads belong to this scope alone.
struct ChromeLeaf<Content: View>: View {
    let state: ZTronScrollState
    let channels: ChannelSet
    let content: (ChromeSample) -> Content
    @StateObject private var relay = ChannelRelay()

    init(_ state: ZTronScrollState, channels: ChannelSet, @ViewBuilder body: @escaping (ChromeSample) -> Content) {
        self.state = state
        self.channels = channels
        self.content = body
    }

    var body: some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: channels.stateChannels, of: storage) }
        #if DEBUG
        ZTronRenderCounters.increment("chromeLeaf.body")
        #endif
        return content(state.chromeSample(channels))
    }
}
