import Combine
import Foundation
import Observation
import SwiftUI
import Testing
@testable import ZTronScrollView

/// Counts real change signals from a storage, whichever path it uses.
@MainActor
final class SignalCounter {
    private var fired = 0
    private var needsArm = false
    /// Signals seen so far; re-arms Observation tracking lazily (never inside the willSet callback).
    var count: Int { if needsArm { needsArm = false; arm() }; return fired }
    private var cancellables: [AnyCancellable] = []
    private let read: (@MainActor () -> Void)?

    /// Observation path: `read` runs under `withObservationTracking`, re-armed after each signal.
    init(observation read: @escaping @MainActor () -> Void) {
        self.read = read
        arm()
    }

    private func arm() {
        guard #available(iOS 17, *), let read else { return }
        withObservationTracking({ read() }, onChange: { [weak self] in
            MainActor.assumeIsolated { self?.fired += 1; self?.needsArm = true }
        })
    }

    /// Channel path.
    init(publisher: ObservableObjectPublisher) {
        read = nil
        publisher.sink { [unowned self] in fired += 1 }.store(in: &cancellables)
    }
}

final class Fired: @unchecked Sendable { var n = 0 }

@MainActor
func makeState(_ path: OSPath) -> ZTronScrollState {
    withOSPath(path) { ZTronScrollState() }
}

/// Settles the main run loop so queued `Task { @MainActor }` hops and SwiftUI updates run.
@MainActor
func pump(_ seconds: TimeInterval = 0.05) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
@Suite(.serialized)
struct StateStorageTests {
    @Test(arguments: OSPath.allCases) func storageKindFollowsAvailability(path: OSPath) {
        let state = makeState(path)
        if path == .forcedFallback && ZTronAvailability.isForcingSupported {
            #expect(state.storage is ChannelStorage)
            #expect(!state.usesLayoutProtocol && !state.usesNamedCoordinateSpace && !state.usesGeometryChange)
        } else if RunningOS.isAtLeast((17, 0)) {
            #expect(state.storage is ChannelStorage == false)
        } else {
            #expect(state.storage is ChannelStorage)
        }
    }

    @Test func stateIsNotObservableObject() {
        let state = ZTronScrollState()
        #expect((state as Any) as? any ObservableObject == nil)
    }

    /// A counter watching one hot or cold property of either storage.
    private func watch(_ state: ZTronScrollState, channel: StateChannel,
                       read: @escaping @MainActor (ZTronScrollState) -> Void) -> SignalCounter {
        if let channels = state.storage as? ChannelStorage {
            return SignalCounter(publisher: channels.publisher(for: channel))
        }
        return SignalCounter(observation: { read(state) })
    }

    @Test(arguments: OSPath.allCases) func unchangedWriteDoesNotPublish(path: OSPath) async {
        let state = makeState(path)
        let c = watch(state, channel: .offset) { _ = $0.contentOffset }
        state.track(offset: .zero, zoom: 1)
        pump()
        #expect(c.count == 0)
        state.track(offset: CGPoint(x: 1, y: 2), zoom: 1)
        pump()
        #expect(c.count == 1)
    }

    @Test(arguments: OSPath.allCases) func oneNotificationPerChannelPerBatch(path: OSPath) {
        let state = makeState(path)
        let c = watch(state, channel: .offset) { _ = $0.contentOffset }
        state.batch {
            state.storage.targetOffset = CGPoint(x: 1, y: 0)
            state.storage.presentationOffset = CGPoint(x: 1, y: 0)
            state.storage.presentationOffset = CGPoint(x: 2, y: 0)
            state.storage.targetOffset = CGPoint(x: 3, y: 0)
        }
        pump()
        #expect(c.count == 1)
    }

    @Test(arguments: OSPath.allCases) func hotWriteLeavesColdChannelsSilent(path: OSPath) {
        let state = makeState(path)
        let zoom = watch(state, channel: .zoom) { _ = $0.zoomScale }
        let phase = watch(state, channel: .phase) { _ = $0.phase; _ = $0.isScrollAnimating }
        let metrics = watch(state, channel: .metrics) { _ = $0.geometry.containerSize }
        state.track(offset: CGPoint(x: 5, y: 5), zoom: 1)
        pump()
        #expect(zoom.count == 0 && phase.count == 0 && metrics.count == 0)
        state.setPhase(.tracking)
        pump()
        #expect(phase.count == 1 && zoom.count == 0)
    }

    @Test func publicReadsIdenticalOnBothPaths() {
        func script(_ s: ZTronScrollState) -> [String] {
            var t = 100.0
            s.now = { t }
            s.setMetrics(ScrollMetrics(viewportSize: CGSize(width: 100, height: 200), contentSize: CGSize(width: 300, height: 900)))
            s.setContentOffset(CGPoint(x: 10, y: 20), animated: false)
            s.setZoomScale(2, animated: false)
            s.setContentOffset(CGPoint(x: 50, y: 400), animated: true)
            t += 0.2
            s.step(to: Date(timeIntervalSinceReferenceDate: t))
            let g = s.geometry
            return ["\(s.contentOffset)", "\(s.zoomScale)", "\(s.phase)", "\(s.isScrollAnimating)",
                    "\(g.visibleRect)", "\(g.contentSize)", "\(g.containerSize)"]
        }
        let a = script(makeState(.preferred)), b = script(makeState(.forcedFallback))
        #expect(a == b)
    }

    @Test func peekIsUntracked() {
        guard #available(iOS 17, *), RunningOS.isAtLeast((17, 0)) else { return }
        let state = makeState(.preferred)
        let fired = Fired()
        withObservationTracking {
            _ = state.peek
            _ = state.peekGeometry().contentOffset
            _ = state.peekGeometry().visibleRect
        } onChange: { fired.n += 1 }
        state.track(offset: CGPoint(x: 9, y: 9), zoom: 2)
        state.setPhase(.animating)
        #expect(fired.n == 0)
    }

    @Test func trackedReadIsTracked() {
        guard #available(iOS 17, *), RunningOS.isAtLeast((17, 0)) else { return }
        let state = makeState(.preferred)
        let fired = Fired()
        withObservationTracking { _ = state.zoomScale } onChange: { fired.n += 1 }
        state.track(offset: CGPoint(x: 9, y: 9), zoom: 1)
        #expect(fired.n == 0)
        state.track(offset: CGPoint(x: 9, y: 9), zoom: 3)
        #expect(fired.n == 1)
    }

    @Test func channelDiscoveryMatchesAccessedProperties() {
        let state = makeState(.forcedFallback)
        guard state.storage is ChannelStorage else { return }
        #expect(state.discoverChannels { $0.zoomScale } == [.zoom])
        #expect(state.discoverChannels { $0.contentOffset.y } == [.offset])
        #expect(state.discoverChannels { $0.visibleRect } == [.offset, .zoom, .metrics])
        #expect(state.discoverChannels { _ in 1 } == [])
    }

    @Test func observationPathHasNoDiscovery() {
        #expect(makeState(.preferred).storage is ChannelStorage || makeState(.preferred).discoverChannels({ $0.zoomScale }) == nil)
    }
}
