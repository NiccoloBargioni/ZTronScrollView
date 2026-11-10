import SwiftUI

/// 0x0 leaf in the viewport's background (design §3). Ticks `state.step(to:)` while a motion runs; paused (zero idle
/// cost, SPEC S4.7) otherwise. Reads only the cold `isClockRunning` flag.
struct FrameClockDriver: View {
    let state: ZTronScrollState
    @StateObject private var relay = ChannelRelay()
    /// `FirstUseWarm`: one tick at appear (a no-op `step`: the clock flag is off), so the first motion does not
    /// pay the timeline's first schedule change and first tick.
    @State private var warmTick = true
    #if DEBUG
    @State private var lastTick = LastTick()
    #endif

    var body: some View {
        if let storage = state.storage as? ChannelStorage { relay.subscribe(to: [.phase], of: storage) }
        let warmTick = warmTick
        return TimelineView(.animation(minimumInterval: nil, paused: !state.isClockRunning && !warmTick)) { ctx in
            Color.clear.frame(width: 0, height: 0)
                .onChangeCompat(of: ctx.date) { date in
                    if warmTick {                        // the warm tick itself is not a clock tick (counters)
                        self.warmTick = false
                        if !state.isClockRunning { return }
                    }
                    #if DEBUG
                    ZTronRenderCounters.increment("clock.tick")
                    if date.timeIntervalSince(lastTick.date) <= 0.001 { ZTronRenderCounters.increment("clock.dupTick") }
                    lastTick.date = date
                    #endif
                    state.step(to: date)
                }
        }
    }
}

#if DEBUG
/// Date of the previous tick (DEBUG `clock.dupTick`: a tick not at least 1 ms after the previous one).
final class LastTick { var date = Date.distantPast }
#endif
