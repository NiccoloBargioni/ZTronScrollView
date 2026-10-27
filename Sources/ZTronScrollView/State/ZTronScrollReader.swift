import SwiftUI

/// Derived observation on every OS: `content` re-runs only when `transform(geometry)` changes, or when the caller's
/// body rebuilds the reader (new closures are always applied: no stale content, R7).
///
/// Inside a scaling header's `.ambientBlur` copy (``ZTronHeaderBackground/ambientBlur(radius:)``) a reader is COLD: it
/// shows the geometry taken at the copy's build and at every cold change (the metrics: a resize, a new resting height),
/// never per frame, so the copy never repeats the header's per-frame reader work (review d16).
public struct ZTronScrollReader<Value: Equatable, Content: View>: View {
    private let explicitState: ZTronScrollState?
    private let transform: (ZTronScrollGeometry) -> Value
    private let content: (Value) -> Content
    @Environment(\.ztronScrollState) private var environmentState
    @Environment(\.ztronColdReaders) private var cold
    @State private var current: Value?

    public init(_ state: ZTronScrollState? = nil, of transform: @escaping (ZTronScrollGeometry) -> Value,
                @ViewBuilder content: @escaping (Value) -> Content) {
        self.explicitState = state
        self.transform = transform
        self.content = content
    }

    private var resolved: ZTronScrollState { explicitState ?? environmentState ?? ZTronScrollState.orphan }

    public var body: some View {
        let state = resolved
        let first = transform(state.peekGeometry())
        return content(current ?? first)
            .background(ReaderProbe(state: state, transform: transform, cold: cold) { new in
                if (current ?? first) != new { current = new }
            })
    }
}

/// 0x0 leaf: reads hot values in its own body (tracked / relay-observed) and reports the derived value. `cold`: it wakes
/// on the metrics only and reports the geometry it then finds (an untracked read).
struct ReaderProbe<Value: Equatable>: View {
    let state: ZTronScrollState
    let transform: (ZTronScrollGeometry) -> Value
    var cold = false
    let update: (Value) -> Void
    @StateObject private var relay = ChannelRelay()

    var body: some View {
        let value: Value
        if cold {
            if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.metrics], of: storage) }
            _ = state.storage.metrics   // the only tracked read (17+)
            value = transform(state.peekGeometry())
        } else {
            if let channels = state.discoverChannels(transform), let storage = state.storage as? ChannelStorage {
                relay.subscribe(to: channels, of: storage)
            }
            value = transform(state.geometry)
        }
        return Color.clear.frame(width: 0, height: 0)
            .onChangeCompat(of: value, perform: update)
            .onAppear { update(value) }
    }
}

struct ScrollStateKey: EnvironmentKey {
    static let defaultValue: ZTronScrollState? = nil
}

/// Readers below are cold (the scaling header's `.ambientBlur` copy): see ``ZTronScrollReader``.
struct ColdReadersKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var ztronScrollState: ZTronScrollState? {
        get { self[ScrollStateKey.self] }
        set { self[ScrollStateKey.self] = newValue }
    }

    var ztronColdReaders: Bool {
        get { self[ColdReadersKey.self] }
        set { self[ColdReadersKey.self] = newValue }
    }
}
