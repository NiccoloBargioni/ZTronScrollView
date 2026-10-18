import SwiftUI

/// 0x0 leaf in the viewport's background (design §3). Ticks `state.step(to:)` while a motion runs; paused (zero idle
/// cost, SPEC S4.7) otherwise. Reads only the cold `isClockRunning` flag.
struct FrameClockDriver: View {
    let state: ZTronScrollState
    @StateObject private var relay = ChannelRelay()

    var body: some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.phase], of: storage) }
        return TimelineView(.animation(minimumInterval: nil, paused: !state.isClockRunning)) { ctx in
            Color.clear.frame(width: 0, height: 0)
                .onChangeCompat(of: ctx.date) { date in
                    #if DEBUG
                    ZTronRenderCounters.increment("clock.tick")
                    #endif
                    state.step(to: date)
                }
        }
    }
}
