import SwiftUI
import ZTronScrollPhysics

/// The pure per-edge refresh state machine (design M8b §1.3). No clock, no SwiftUI, no scroll state: the coordinator
/// feeds it events carrying one `Input` each and applies the effects it returns, so every transition is a test of values.
///
/// One pull is one finger-down sequence: the action fires at most once per pull (`firedThisPull`), and a second pull
/// during a refresh never fires it. The hold (the inset the indicator keeps open) is applied at the lift, never mid-drag:
/// changing the bounds under a finger would remap the rubber band and make the content jump.
struct RefreshEngine: Equatable {
    enum Phase: Equatable {
        case idle
        /// Finger down, pulling, below the trigger.
        case pulling
        /// `.onRelease`: crossed the trigger, the action waits for the lift.
        case armed
        /// The action runs and the finger is still down: the hold waits for the lift.
        case triggered
        case refreshing(since: TimeInterval)
        /// The action returned; the hold stays until `until` (minimum visible time), then clears.
        case finishing(until: TimeInterval)
        /// The pull or the refresh is over and the content is still on its way back to rest: the indicator goes with it and
        /// `progress` follows the live pull down to 0. Ends when the pull is gone, when a new pull takes over, or at `until`
        /// (a safeguard for a content nothing moves back, or one that is not drawn).
        case retracting(RetractLook, until: TimeInterval)
    }

    /// How the built-in indicator draws itself while its edge retracts. Display only: `ZTronRefreshState` does not change.
    enum RetractLook: Equatable {
        /// A pull let go below the trigger: the ring / arrow follows the decreasing `dragPosition`.
        case pull
        /// A refresh that ended: the spinner stays until the gap is closed, as `UIRefreshControl` does.
        case spinner
    }

    /// What the coordinator knows when it talks to the engine.
    struct Input: Equatable {
        /// Displayed overscroll past this edge (`RefreshMath.pull`), ≥ 0.
        var pull: CGFloat = 0
        var isTracking = false
        /// Zoom at its minimum (or `disablesWhenZoomed` off), scrolling enabled, no other edge refreshing.
        var enabled = true
        /// No motion without a finger is running: the hold may clear without fighting it.
        var isSettled = true
        var time: TimeInterval = 0
    }

    enum Event: Equatable {
        /// A frame: pull progress while the finger is down, the deadline check while finishing.
        case sample(Input)
        /// The finger lifted and the release pipeline follows. `cancelled`: the system cancelled the touch.
        case lift(Input, cancelled: Bool)
        /// The touch sequence ended without a release (nothing followed the finger).
        case sequenceEnd(Input)
        /// `beginRefreshing()` (`runAction: false`, UIKit parity) or the accessibility action (`runAction: true`).
        case begin(Input, runAction: Bool)
        /// The action returned, or `endRefreshing()`.
        case done(Input)
        /// The view disappeared / the refresher was removed: everything back to rest, unanimated.
        case cancel
    }

    enum Effect: Equatable {
        case progress(CGFloat)
        case mode(ZTronRefreshState.Mode, animated: Bool)
        /// Start the action (once) and the haptic.
        case trigger
        /// Open the hold. `reveal`: nothing follows the offset (no release pipeline), so scroll to it when at the edge.
        case hold(CGFloat, reveal: Bool)
        /// Close the hold. `atLift`: the release pipeline follows and springs the offset back; otherwise the M5 inset rule
        /// returns the content to rest (animated per `resetAnimation` iff `animated`).
        case clearHold(atLift: Bool, animated: Bool)
        case announce(String)
        /// The indicator starts retracting with `look`, or (`nil`) is done: it stays on screen while the content comes back.
        case retract(RetractLook?)
    }

    /// Pull (points) under which the content counts as back at rest: the retraction is over.
    static let retractedPull: CGFloat = 0.5
    /// The longest a retraction waits for the pull to go.
    static let retractTimeout: TimeInterval = 3

    let config: ZTronRefreshConfiguration
    let edge: Edge
    /// Inset the hold opens (`holdSize`); 0 for an overlay indicator.
    let holdSize: CGFloat
    private(set) var phase: Phase = .idle
    private(set) var mode = ZTronRefreshState.Mode.notRefreshing
    private(set) var progress: CGFloat = 0
    private(set) var firedThisPull = false
    private(set) var holdApplied = false
    private var sequenceActive = false
    /// When this pull fired its action: the refreshing look has been on screen since.
    private var triggeredAt: TimeInterval = 0
    /// The action returned while the finger was still down. The refreshing look stays until the lift, as
    /// `UIRefreshControl` keeps a refresh that ends mid-drag on screen until the touch ends (S9: "animate back to rest
    /// unless the user is tracking"); the speed of the pull must not decide whether the indicator is held.
    private var returnedUnderFinger = false

    init(config: ZTronRefreshConfiguration, edge: Edge, overlay: Bool = false) {
        self.config = config
        self.edge = edge
        self.holdSize = Self.holdSize(edge: edge, config: config, overlay: overlay)
    }

    /// `holdOffset ?? indicatorHeight`, plus `loadMorePadding` on the end edges; an overlay never pushes the content.
    static func holdSize(edge: Edge, config: ZTronRefreshConfiguration, overlay: Bool) -> CGFloat {
        guard !overlay else { return 0 }
        let base = max(0, config.holdOffset ?? config.indicatorHeight)
        let isEnd = edge == .bottom || edge == .trailing
        return base + (isEnd ? max(0, config.loadMorePadding) : 0)
    }

    /// `pull ÷ triggerDistance`, clamped to 0…1.
    func progress(for pull: CGFloat) -> CGFloat {
        guard pull > 0 else { return 0 }
        guard config.triggerDistance > 0 else { return 1 }
        return min(1, pull / config.triggerDistance)
    }

    /// Any phase but `.idle`: the coordinator keeps sampling.
    var isActive: Bool { phase != .idle }
    /// Nothing pulls or refreshes: idle, or the indicator is only going back with the content.
    private var isFree: Bool {
        switch phase {
        case .idle, .retracting: return true
        default: return false
        }
    }
    /// Triggered, refreshing or finishing: this edge owns the (global) refresh.
    var isRefreshing: Bool {
        switch phase {
        case .triggered, .refreshing, .finishing: return true
        default: return false
        }
    }

    mutating func handle(_ event: Event) -> [Effect] {
        var fx: [Effect] = []
        switch event {
        case let .sample(i): sample(i, &fx)
        case let .lift(i, cancelled): lift(i, cancelled: cancelled, &fx)
        case let .sequenceEnd(i): sequenceEnd(i, &fx)
        case let .begin(i, runAction): begin(i, runAction: runAction, &fx)
        case let .done(i): done(i, &fx)
        case .cancel: cancel(&fx)
        }
        return fx
    }

    // MARK: Transitions

    private mutating func sample(_ i: Input, _ fx: inout [Effect]) {
        switch phase {
        case .idle, .pulling, .armed, .retracting:
            guard i.enabled, i.isTracking, i.pull > 0 else {
                switch phase {
                case let .retracting(_, until):
                    // Nobody pulls: the indicator follows the content back, until the gap is gone.
                    if !i.enabled || i.pull <= Self.retractedPull || i.time >= until {
                        endRetraction(&fx)
                    } else {
                        setProgress(progress(for: i.pull), &fx)
                    }
                case .idle:
                    break
                default:
                    // Not (or no longer) pulling: back to rest without a trigger.
                    phase = .idle
                    reset(&fx)
                }
                return
            }
            if case .retracting = phase { phase = .idle; fx.append(.retract(nil)) }      // a new pull takes over
            sequenceActive = true
            let p = progress(for: i.pull)
            if phase == .idle { phase = .pulling; setMode(.pulling, animated: false, &fx) }
            setProgress(p, &fx)
            if p >= 1, !firedThisPull {
                if config.triggerMode == .whilePulling { fire(i, &fx) } else { phase = .armed }
            } else if phase == .armed, p < 1 {
                phase = .pulling                                  // .onRelease disarms below the trigger
            }
        case .triggered:
            if !i.isTracking {                                    // the lift was missed: nothing springs the offset
                endTouchWhileTriggered(i, reveal: true, &fx)
                if isFree { sequenceActive = false; firedThisPull = false }
            }
        case .refreshing:
            break
        case let .finishing(until):
            if i.time >= until, !i.isTracking, i.isSettled { finish(atLift: false, i, &fx) }
        }
    }

    private mutating func lift(_ i: Input, cancelled: Bool, _ fx: inout [Effect]) {
        switch phase {
        case .idle, .pulling, .armed, .retracting:
            // The lift is a position too: a crossing between two samples still counts, a pull below the trigger disarms.
            if i.enabled, !cancelled, i.pull > 0, progress(for: i.pull) >= 1, !firedThisPull {
                if case .retracting = phase { phase = .idle; fx.append(.retract(nil)) }
                sequenceActive = true
                setProgress(1, &fx)
                fire(i, &fx)
                startHold(i, reveal: false, &fx)
            } else if phase == .pulling || phase == .armed {
                retractAfterPull(i, &fx)
            }
        case .triggered:
            endTouchWhileTriggered(i, reveal: false, &fx)
        case .refreshing:
            break
        case let .finishing(until):
            // The reset waited for the lift; the release pipeline springs the offset to the cleared bounds.
            if i.time >= until, i.isSettled { finish(atLift: true, i, &fx) }
        }
        sequenceActive = false
        if isFree { firedThisPull = false }
    }

    private mutating func sequenceEnd(_ i: Input, _ fx: inout [Effect]) {
        switch phase {
        case .pulling, .armed:
            phase = .idle
            reset(&fx)
        case .triggered:
            endTouchWhileTriggered(i, reveal: true, &fx)
        case let .finishing(until):
            if i.time >= until, i.isSettled { finish(atLift: false, i, &fx) }
        case .idle, .refreshing, .retracting:
            break
        }
        sequenceActive = false
        if isFree { firedThisPull = false }
    }

    private mutating func begin(_ i: Input, runAction: Bool, _ fx: inout [Effect]) {
        if case .retracting = phase { phase = .idle; fx.append(.retract(nil)) }      // the indicator comes back as a refresh
        guard phase == .idle else { return }                      // a refresh is already running: no-op
        setProgress(1, &fx)
        setMode(.refreshing, animated: true, &fx)
        startHold(i, reveal: true, &fx)
        if runAction { fx.append(.trigger) }
        fx.append(.announce("Refreshing"))
    }

    private mutating func done(_ i: Input, _ fx: inout [Effect]) {
        switch phase {
        case let .refreshing(since):
            let until = max(i.time, since + config.minimumVisibleTime)
            phase = .finishing(until: until)
            if i.time >= until, !i.isTracking, i.isSettled { finish(atLift: false, i, &fx) }
        case .triggered:
            returnedUnderFinger = true                            // the refreshing look stays until the lift
        default:
            break                                                 // idempotent: a second `done`, or one after a cancel
        }
    }

    private mutating func cancel(_ fx: inout [Effect]) {
        if case .retracting = phase { fx.append(.retract(nil)) }
        phase = .idle
        firedThisPull = false
        sequenceActive = false
        returnedUnderFinger = false
        if holdApplied {
            holdApplied = false
            fx.append(.clearHold(atLift: false, animated: false))
        }
        setProgress(0, &fx)
        setMode(.notRefreshing, animated: false, &fx)
    }

    // MARK: Helpers

    private mutating func fire(_ i: Input, _ fx: inout [Effect]) {
        firedThisPull = true
        triggeredAt = i.time
        returnedUnderFinger = false
        phase = .triggered
        setProgress(1, &fx)                                       // stays 1 while refreshing
        setMode(.refreshing, animated: true, &fx)
        fx.append(.trigger)
        fx.append(.announce("Refreshing"))
    }

    /// The touch of a triggered pull is over. While the action runs, the hold opens (the release springs the content to it).
    /// When it already returned under the finger, the indicator has been refreshing since the trigger: if that was long
    /// enough nothing opens and the refresh just ends (the content springs back to rest); otherwise the hold opens for the
    /// time that is missing, counted from the trigger.
    private mutating func endTouchWhileTriggered(_ i: Input, reveal: Bool, _ fx: inout [Effect]) {
        guard returnedUnderFinger else {
            startHold(i, reveal: reveal, &fx)
            return
        }
        returnedUnderFinger = false
        let until = max(i.time, triggeredAt + config.minimumVisibleTime)
        if i.time >= until {
            if !reveal, i.pull > Self.retractedPull {
                retract(.spinner, i, &fx)                             // the release springs the content back, the spinner goes with it
            } else {
                phase = .idle
                setProgress(0, &fx)
                setMode(.notRefreshing, animated: true, &fx)
            }
            fx.append(.announce("Refresh complete"))
        } else {
            startHold(i, reveal: reveal, &fx)
            phase = .finishing(until: until)
        }
    }

    private mutating func startHold(_ i: Input, reveal: Bool, _ fx: inout [Effect]) {
        phase = .refreshing(since: i.time)
        holdApplied = true
        fx.append(.hold(holdSize, reveal: reveal))
    }

    /// The refresh is over and the hold clears. The content is still on its way back to rest (the release springs it at the
    /// lift, `resetAnimation` otherwise), so the indicator goes with it; a reset nobody animates leaves nothing to follow.
    private mutating func finish(atLift: Bool, _ i: Input, _ fx: inout [Effect]) {
        if i.pull > Self.retractedPull, atLift || config.resetAnimation != nil {
            retract(.spinner, i, &fx)
        } else {
            phase = .idle
            setProgress(0, &fx)
            setMode(.notRefreshing, animated: true, &fx)
        }
        if holdApplied {
            holdApplied = false
            fx.append(.clearHold(atLift: atLift, animated: true))
        }
        fx.append(.announce("Refresh complete"))
        if atLift || !sequenceActive { firedThisPull = false }
    }

    private mutating func reset(_ fx: inout [Effect]) {
        setProgress(0, &fx)
        setMode(.notRefreshing, animated: true, &fx)
    }

    /// The finger lifted below the trigger: the release pipeline springs the content back and the indicator goes with it.
    private mutating func retractAfterPull(_ i: Input, _ fx: inout [Effect]) {
        guard i.enabled, i.pull > Self.retractedPull else {
            phase = .idle
            reset(&fx)
            return
        }
        retract(.pull, i, &fx)
    }

    /// The indicator stays while the content comes back: not refreshing any more, `progress` following the pull.
    private mutating func retract(_ look: RetractLook, _ i: Input, _ fx: inout [Effect]) {
        phase = .retracting(look, until: i.time + Self.retractTimeout)
        setProgress(progress(for: i.pull), &fx)
        setMode(.notRefreshing, animated: true, &fx)
        fx.append(.retract(look))
    }

    /// The content is back at rest, or nothing is left to follow: the indicator goes.
    private mutating func endRetraction(_ fx: inout [Effect]) {
        phase = .idle
        setProgress(0, &fx)
        fx.append(.retract(nil))
    }

    private mutating func setMode(_ m: ZTronRefreshState.Mode, animated: Bool, _ fx: inout [Effect]) {
        guard m != mode else { return }
        mode = m
        fx.append(.mode(m, animated: animated))
    }

    private mutating func setProgress(_ p: CGFloat, _ fx: inout [Effect]) {
        guard p != progress else { return }
        progress = p
        fx.append(.progress(p))
    }
}

/// Geometry of a pull (design M8b §1.3), against the bounds WITHOUT the refresh hold: the displayed, rubber-banded
/// overscroll, as `UIRefreshControl` reads `contentOffset`.
enum RefreshMath {
    /// Signed distance of `offset` past the `edge` bound: positive = pulled past it, negative = inside (the distance
    /// to the bound). Bounds are those of `metrics` minus its own refresh hold at this zoom.
    static func signedPull(edge: Edge, offset: CGPoint, zoom: CGFloat, metrics m: ScrollMetrics,
                           alignment: UnitPoint) -> CGFloat {
        let aci = m.adjustedContentInset, hold = m.refreshHold
        let base = EdgeInsets(top: aci.top - hold.top, leading: aci.leading - hold.leading,
                              bottom: aci.bottom - hold.bottom, trailing: aci.trailing - hold.trailing)
        let b = ResizeMath.geometry(viewport: m.viewportSize, content: m.contentSize, insets: base, alignment: alignment)
            .bounds(at: zoom)
        switch edge {
        case .top: return b.y.min - offset.y
        case .bottom: return offset.y - b.y.max
        case .leading: return b.x.min - offset.x
        case .trailing: return offset.x - b.x.max
        }
    }

    static func pull(edge: Edge, offset: CGPoint, zoom: CGFloat, metrics: ScrollMetrics, alignment: UnitPoint) -> CGFloat {
        max(0, signedPull(edge: edge, offset: offset, zoom: zoom, metrics: metrics, alignment: alignment))
    }

    /// The hold inset one edge opens.
    static func holdInsets(edge: Edge, amount: CGFloat) -> EdgeInsets {
        switch edge {
        case .top: return EdgeInsets(top: amount, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: amount, trailing: 0)
        case .leading: return EdgeInsets(top: 0, leading: amount, bottom: 0, trailing: 0)
        case .trailing: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: amount)
        }
    }
}
