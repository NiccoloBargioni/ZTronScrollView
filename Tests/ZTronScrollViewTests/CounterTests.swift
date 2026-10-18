import Testing
@testable import ZTronScrollView

@MainActor
@Suite(.serialized)
struct CounterTests {
    @Test func resetClears() {
        #if DEBUG
        ZTronRenderCounters.reset()
        ZTronRenderCounters.increment("a")
        ZTronRenderCounters.increment("a")
        #expect(ZTronRenderCounters.value("a") == 2)
        ZTronRenderCounters.reset()
        #expect(ZTronRenderCounters.value("a") == 0 && ZTronRenderCounters.snapshot.isEmpty)
        #endif
    }
}
