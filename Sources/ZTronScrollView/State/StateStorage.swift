import SwiftUI
import Combine
import Observation

/// Every value, untracked (the `peek` view of a storage).
struct StorageSnapshot: Equatable {
    var targetOffset: CGPoint = .zero
    var targetZoom: CGFloat = 1
    var presentationOffset: CGPoint = .zero
    var presentationZoom: CGFloat = 1
    var metrics = ScrollMetrics()
    var phase: ZTronScrollPhase = .idle
    var isScrollAnimating = false
    var isZoomAnimating = false
    var isClockRunning = false
}

/// Hot values: `target*`/`presentation*`. Cold values: metrics, phase, flags, clock (SPEC S4.5).
/// Setters are `!=`-guarded; tracked getters register with the observation system; `snapshot()` never does.
@MainActor
protocol StateStorage: AnyObject {
    var targetOffset: CGPoint { get set }
    var targetZoom: CGFloat { get set }
    var presentationOffset: CGPoint { get set }
    var presentationZoom: CGFloat { get set }
    var metrics: ScrollMetrics { get set }
    var phase: ZTronScrollPhase { get set }
    var isScrollAnimating: Bool { get set }
    var isZoomAnimating: Bool { get set }
    var isClockRunning: Bool { get set }
    func snapshot() -> StorageSnapshot
    /// Batches nest; at most one publish per channel (fallback) per outermost batch.
    func beginBatch()
    func endBatch()
}

/// Batch bookkeeping shared by both storages: decides whether a dirty write must publish.
@MainActor
final class BatchGate {
    private(set) var depth = 0
    private var dirty = Set<Int>()

    func begin() { depth += 1 }
    func end() {
        depth = max(0, depth - 1)
        if depth == 0 { dirty.removeAll() }
    }
    /// `true` for a write outside a batch and for the first write of `key` inside one.
    func shouldPublish(_ key: Int) -> Bool {
        depth == 0 || dirty.insert(key).inserted
    }
}

// MARK: - Observation path (iOS 17+)

/// Hand-written registrar instead of `@Observable` (R2): hot values stay separate stored properties and `snapshot()`
/// reads the backing fields without tracking.
@available(iOS 17, *)
@MainActor
final class ObservationStorage: StateStorage, Observable {
    private let registrar = ObservationRegistrar()
    private let gate = BatchGate()
    private var v = StorageSnapshot()


    var targetOffset: CGPoint {
        get { registrar.access(self, keyPath: \.targetOffset); return v.targetOffset }
        set {
            guard newValue != v.targetOffset else { return }
            registrar.withMutation(of: self, keyPath: \.targetOffset) { v.targetOffset = newValue }
        }
    }
    var targetZoom: CGFloat {
        get { registrar.access(self, keyPath: \.targetZoom); return v.targetZoom }
        set {
            guard newValue != v.targetZoom else { return }
            registrar.withMutation(of: self, keyPath: \.targetZoom) { v.targetZoom = newValue }
        }
    }
    var presentationOffset: CGPoint {
        get { registrar.access(self, keyPath: \.presentationOffset); return v.presentationOffset }
        set {
            guard newValue != v.presentationOffset else { return }
            registrar.withMutation(of: self, keyPath: \.presentationOffset) { v.presentationOffset = newValue }
        }
    }
    var presentationZoom: CGFloat {
        get { registrar.access(self, keyPath: \.presentationZoom); return v.presentationZoom }
        set {
            guard newValue != v.presentationZoom else { return }
            registrar.withMutation(of: self, keyPath: \.presentationZoom) { v.presentationZoom = newValue }
        }
    }
    var metrics: ScrollMetrics {
        get { registrar.access(self, keyPath: \.metrics); return v.metrics }
        set {
            guard newValue != v.metrics else { return }
            registrar.withMutation(of: self, keyPath: \.metrics) { v.metrics = newValue }
        }
    }
    var phase: ZTronScrollPhase {
        get { registrar.access(self, keyPath: \.phase); return v.phase }
        set {
            guard newValue != v.phase else { return }
            registrar.withMutation(of: self, keyPath: \.phase) { v.phase = newValue }
        }
    }
    var isScrollAnimating: Bool {
        get { registrar.access(self, keyPath: \.isScrollAnimating); return v.isScrollAnimating }
        set {
            guard newValue != v.isScrollAnimating else { return }
            registrar.withMutation(of: self, keyPath: \.isScrollAnimating) { v.isScrollAnimating = newValue }
        }
    }
    var isZoomAnimating: Bool {
        get { registrar.access(self, keyPath: \.isZoomAnimating); return v.isZoomAnimating }
        set {
            guard newValue != v.isZoomAnimating else { return }
            registrar.withMutation(of: self, keyPath: \.isZoomAnimating) { v.isZoomAnimating = newValue }
        }
    }
    var isClockRunning: Bool {
        get { registrar.access(self, keyPath: \.isClockRunning); return v.isClockRunning }
        set {
            guard newValue != v.isClockRunning else { return }
            registrar.withMutation(of: self, keyPath: \.isClockRunning) { v.isClockRunning = newValue }
        }
    }

    func snapshot() -> StorageSnapshot { v }
    // Observation observers are one-shot per property, so a batch needs no extra coalescing.
    func beginBatch() { gate.begin() }
    func endBatch() { gate.end() }
}

// MARK: - Channel path (iOS 15-16, or forced)

final class OffsetChannel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var target = CGPoint.zero
    var presentation = CGPoint.zero
}
final class ZoomChannel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var target: CGFloat = 1
    var presentation: CGFloat = 1
}
final class MetricsChannel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var value = ScrollMetrics()
}
final class PhaseChannel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var phase = ZTronScrollPhase.idle
    var isScrollAnimating = false
    var isZoomAnimating = false
    var isClockRunning = false
}

/// Collects the channels touched by tracked reads (reader channel discovery on the fallback path).
@MainActor
final class ChannelRecorder {
    private(set) var touched = Set<StateChannel>()
    func touch(_ c: StateChannel) { touched.insert(c) }
}

@MainActor
final class ChannelStorage: StateStorage {
    let offsetChannel = OffsetChannel()
    let zoomChannel = ZoomChannel()
    let metricsChannel = MetricsChannel()
    let phaseChannel = PhaseChannel()
    /// Non-nil only while a reader discovers its channels.
    var recorder: ChannelRecorder?
    private let gate = BatchGate()

    func publisher(for channel: StateChannel) -> ObservableObjectPublisher {
        switch channel {
        case .offset: return offsetChannel.objectWillChange
        case .zoom: return zoomChannel.objectWillChange
        case .metrics: return metricsChannel.objectWillChange
        case .phase: return phaseChannel.objectWillChange
        }
    }

    /// `!=`-guarded write; sends `objectWillChange` before mutating (Combine semantics), once per batch per channel.
    private func write<C: ObservableObject, T: Equatable>(
        _ object: C, _ keyPath: ReferenceWritableKeyPath<C, T>, _ channel: StateChannel, _ new: T
    ) where C.ObjectWillChangePublisher == ObservableObjectPublisher {
        guard object[keyPath: keyPath] != new else { return }
        if gate.shouldPublish(channel.rawValue) { object.objectWillChange.send() }
        object[keyPath: keyPath] = new
    }

    private func read<T>(_ channel: StateChannel, _ value: T) -> T {
        recorder?.touch(channel)
        return value
    }

    var targetOffset: CGPoint {
        get { read(.offset, offsetChannel.target) }
        set { write(offsetChannel, \.target, .offset, newValue) }
    }
    var presentationOffset: CGPoint {
        get { read(.offset, offsetChannel.presentation) }
        set { write(offsetChannel, \.presentation, .offset, newValue) }
    }
    var targetZoom: CGFloat {
        get { read(.zoom, zoomChannel.target) }
        set { write(zoomChannel, \.target, .zoom, newValue) }
    }
    var presentationZoom: CGFloat {
        get { read(.zoom, zoomChannel.presentation) }
        set { write(zoomChannel, \.presentation, .zoom, newValue) }
    }
    var metrics: ScrollMetrics {
        get { read(.metrics, metricsChannel.value) }
        set { write(metricsChannel, \.value, .metrics, newValue) }
    }
    var phase: ZTronScrollPhase {
        get { read(.phase, phaseChannel.phase) }
        set { write(phaseChannel, \.phase, .phase, newValue) }
    }
    var isScrollAnimating: Bool {
        get { read(.phase, phaseChannel.isScrollAnimating) }
        set { write(phaseChannel, \.isScrollAnimating, .phase, newValue) }
    }
    var isZoomAnimating: Bool {
        get { read(.phase, phaseChannel.isZoomAnimating) }
        set { write(phaseChannel, \.isZoomAnimating, .phase, newValue) }
    }
    var isClockRunning: Bool {
        get { read(.phase, phaseChannel.isClockRunning) }
        set { write(phaseChannel, \.isClockRunning, .phase, newValue) }
    }

    func snapshot() -> StorageSnapshot {
        StorageSnapshot(targetOffset: offsetChannel.target, targetZoom: zoomChannel.target,
                        presentationOffset: offsetChannel.presentation, presentationZoom: zoomChannel.presentation,
                        metrics: metricsChannel.value, phase: phaseChannel.phase,
                        isScrollAnimating: phaseChannel.isScrollAnimating,
                        isZoomAnimating: phaseChannel.isZoomAnimating, isClockRunning: phaseChannel.isClockRunning)
    }
    func beginBatch() { gate.begin() }
    func endBatch() { gate.end() }
}

/// One `objectWillChange` for the channels a leaf needs (fallback path). Inert (never subscribes) on the
/// Observation path, so leaf view types are identical on both paths.
final class ChannelRelay: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private(set) var channels = Set<StateChannel>()
    private var cancellable: AnyCancellable?

    @MainActor func subscribe(to wanted: Set<StateChannel>, of storage: ChannelStorage) {
        guard wanted != channels else { return }
        channels = wanted
        cancellable = Publishers.MergeMany(wanted.map { storage.publisher(for: $0) })
            .sink { [weak self] in self?.objectWillChange.send() }
    }
}
