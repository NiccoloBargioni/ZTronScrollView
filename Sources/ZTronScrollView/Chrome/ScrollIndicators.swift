import SwiftUI

// Scroll indicators (SPEC S6 "Also", S8 "Indicators", design M8-chrome §2; the exemplar of the M8 slice).
// The thumbs are leaves in the viewport overlay (`ChromeLeaf`): they re-render every frame of motion and never re-evaluate
// the content (SPEC S4). Everything cold (visibility resolution, the fade controller, flashes) lives in the overlay host,
// which re-evaluates on configuration changes only.

/// Visibility of a scroll indicator; mirrors SwiftUI's `ScrollIndicatorVisibility` (iOS 16; conversions in
/// `NativeChromeBridges.swift`).
public enum ZTronScrollIndicatorVisibility: Sendable, Equatable {
    /// Shown while the content moves (a drag, a release, a programmatic animation, a pinch) and faded after a short idle.
    case automatic
    /// Shown whenever the content is scrollable on the axis; never fades.
    case visible
    /// Not shown; a flash is a no-op.
    case hidden
    /// Not shown, whatever the platform would otherwise reveal (SwiftUI lets a mouse reveal `hidden` indicators on macOS;
    /// iOS has no such case, so the two draw the same here).
    case never
}

// MARK: - Members (S8-2a)

extension ZTronScrollView {
    /// `scrollIndicators(_:axes:)` for this view on iOS 15+. Wins over ``SwiftUI/View/ztronScrollIndicators(_:axes:)`` and
    /// over SwiftUI's own modifier above this view; an explicit value other than `.automatic` also wins over
    /// `init(_:showsIndicators:content:)` (SwiftUI's `ScrollView` behaves the same: `showsIndicators: false` only decides
    /// what `.automatic` means). The unprefixed spelling binds only on the `ZTronScrollView` itself.
    public func scrollIndicators(_ visibility: ZTronScrollIndicatorVisibility, axes: Axis.Set = [.horizontal, .vertical]) -> Self {
        var copy = self
        copy.chrome.indicators.set(visibility, axes: axes)
        return copy
    }

    /// `scrollIndicatorsFlash(onAppear:)` for this view on iOS 15+: the indicators flash once when the view appears.
    public func scrollIndicatorsFlash(onAppear: Bool) -> Self {
        var copy = self
        copy.chrome.flashOnAppear = onAppear
        return copy
    }

    /// `scrollIndicatorsFlash(trigger:)` for this view on iOS 15+: the indicators flash once each time `trigger` changes.
    public func scrollIndicatorsFlash<T: Equatable>(trigger: T) -> Self {
        var copy = self
        copy.chrome.flashTrigger = AnyEquatable(trigger)
        return copy
    }
}

// MARK: - Twins (S8-2b)

extension View {
    /// Environment twin of ``ZTronScrollView/scrollIndicators(_:axes:)`` (the member wins when both are set): reaches every
    /// `ZTronScrollView` below and, on iOS 16+, applies SwiftUI's `scrollIndicators(_:axes:)`, so one call site configures
    /// native and ZTron scroll views alike.
    @ViewBuilder
    public func ztronScrollIndicators(_ visibility: ZTronScrollIndicatorVisibility, axes: Axis.Set = [.horizontal, .vertical])
        -> some View {
        let overlaid = transformEnvironment(\.ztronChromeConfig) { $0.indicators.set(visibility, axes: axes) }
        if #available(iOS 16, *) {
            overlaid.scrollIndicators(visibility.native, axes: axes)
        } else {
            overlaid
        }
    }

    /// Environment twin of ``ZTronScrollView/scrollIndicatorsFlash(onAppear:)``; applies SwiftUI's modifier on iOS 17+.
    @ViewBuilder
    public func ztronScrollIndicatorsFlash(onAppear: Bool) -> some View {
        let overlaid = transformEnvironment(\.ztronChromeConfig) { $0.flashOnAppear = onAppear }
        if #available(iOS 17, *) {
            overlaid.scrollIndicatorsFlash(onAppear: onAppear)
        } else {
            overlaid
        }
    }

    /// Environment twin of ``ZTronScrollView/scrollIndicatorsFlash(trigger:)``; applies SwiftUI's modifier on iOS 17+.
    @ViewBuilder
    public func ztronScrollIndicatorsFlash<T: Equatable>(trigger: T) -> some View {
        let overlaid = transformEnvironment(\.ztronChromeConfig) { $0.flashTrigger = AnyEquatable(trigger) }
        if #available(iOS 17, *) {
            overlaid.scrollIndicatorsFlash(trigger: trigger)
        } else {
            overlaid
        }
    }
}

// MARK: - State API (UIKit parity)

extension ZTronScrollState {
    /// UIKit `scrollIndicatorInsets`: the inset of the indicators' track from the viewport edges, added to the automatic
    /// safe-area insets (the part of the safe area `contentInsetAdjustmentBehavior` applies to the content) and to the
    /// `contentMargins(for: .scrollIndicators)` of the view. Cold: publishes on the metrics channel; the thumbs follow.
    public var scrollIndicatorInsets: EdgeInsets {
        get { storage.metrics.indicatorInsets }
        set {
            guard newValue != storage.snapshot().metrics.indicatorInsets else { return }
            batch {
                var m = storage.snapshot().metrics
                m.indicatorInsets = newValue
                storage.metrics = m
            }
        }
    }

    /// UIKit `flashScrollIndicators()`: shows the indicators of the `.automatic` axes for a moment, then fades them. A
    /// no-op while both axes are `.hidden` / `.never`, and before the view has appeared.
    public func flashScrollIndicators() { indicatorController?.flash() }
}

// MARK: - Geometry

/// Look and timing of the thumbs (design M8 §2; tuned side by side with a UIKit sibling on a device, risk 3).
enum IndicatorStyle {
    static let thickness: CGFloat = 3
    static let edgeGap: CGFloat = 3
    static let minLength: CGFloat = 36
    static let minLengthRubber: CGFloat = 8
    /// Shown this long after the content stops, then faded.
    static let hideDelay: TimeInterval = 0.4
    static let fade: TimeInterval = 0.3
    /// A flash keeps the thumbs shown this long before the fade.
    static let flashHold: TimeInterval = 0.6
    static var color: Color { Color.primary.opacity(0.35) }
}

/// One thumb along its axis, in viewport points.
struct IndicatorThumb: Equatable {
    var origin: CGFloat
    var length: CGFloat
}

struct IndicatorLayout: Equatable {
    var horizontal: IndicatorThumb?
    var vertical: IndicatorThumb?
}

/// Pure thumb geometry (design M8 §2), per axis and in viewport points; `start` / `end` are top / bottom (vertical) or
/// leading / trailing (horizontal).
enum IndicatorMath {
    /// The thumb of one axis, or `nil` when the content does not exceed the viewport (not scrollable).
    ///
    /// `E = C·s + aci.start + aci.end` is the scrollable extent, `T` the track the thumb moves in (the viewport minus the
    /// indicator insets, the edge gaps and, when the other axis shows a thumb too, its thickness), `ℓ = max(minLength,
    /// V/E·T)` the length and `p = o′/(E − V)` the position, with `o′ = o + aci.start` (0 at the start rest position, the
    /// same convention as the resize math). Past an edge by `d` the thumb shrinks to `max(minLengthRubber, ℓ − d)` and
    /// stays pinned to that edge, as UIKit's does.
    static func thumb(viewport V: CGFloat, content C: CGFloat, zoom s: CGFloat,
                      inset aci: (start: CGFloat, end: CGFloat), indInset: (start: CGFloat, end: CGFloat),
                      offset o: CGFloat, otherVisible: Bool) -> IndicatorThumb? {
        guard V.isFinite, V > 0, C.isFinite, s.isFinite, o.isFinite else { return nil }
        let zoom = s > 0 ? s : 1
        let extent = max(0, C) * zoom + aci.start + aci.end
        guard extent > V else { return nil }
        let track = V - indInset.start - indInset.end - 2 * IndicatorStyle.edgeGap
            - (otherVisible ? IndicatorStyle.thickness + IndicatorStyle.edgeGap : 0)
        guard track > 0 else { return nil }
        let length = min(track, max(IndicatorStyle.minLength, V / extent * track))
        let range = extent - V
        let shifted = o + aci.start
        let base = indInset.start + IndicatorStyle.edgeGap
        if shifted < 0 {
            let shrunk = min(length, max(IndicatorStyle.minLengthRubber, length + shifted))
            return IndicatorThumb(origin: base, length: shrunk)
        }
        if shifted > range {
            let shrunk = min(length, max(IndicatorStyle.minLengthRubber, length - (shifted - range)))
            return IndicatorThumb(origin: base + track - shrunk, length: shrunk)
        }
        return IndicatorThumb(origin: base + shifted / range * (track - length), length: length)
    }

    /// Both thumbs of a scroll view. An axis shows a thumb when it can scroll (`axes`, plus any axis the zoomed content
    /// exceeds while zoom is enabled, D15), its visibility draws one and the content exceeds the viewport on it; a thumb
    /// on one axis shortens the track of the other.
    static func layout(offset: CGPoint, zoom: CGFloat, metrics m: ScrollMetrics, trackInsets t: EdgeInsets,
                       resolved: ResolvedIndicators, axes: Axis.Set, zoomEnabled: Bool) -> IndicatorLayout {
        let aci = m.adjustedContentInset
        let s = zoom > 0 && zoom.isFinite ? zoom : 1
        func exceeds(_ viewport: CGFloat, _ content: CGFloat, _ start: CGFloat, _ end: CGFloat) -> Bool {
            viewport > 0 && max(0, content) * s + start + end > viewport
        }
        let horizontalOn = (axes.contains(.horizontal) || zoomEnabled) && resolved.draws(resolved.horizontal)
            && exceeds(m.viewportSize.width, m.contentSize.width, aci.leading, aci.trailing)
        let verticalOn = (axes.contains(.vertical) || zoomEnabled) && resolved.draws(resolved.vertical)
            && exceeds(m.viewportSize.height, m.contentSize.height, aci.top, aci.bottom)
        return IndicatorLayout(
            horizontal: horizontalOn
                ? thumb(viewport: m.viewportSize.width, content: m.contentSize.width, zoom: s,
                        inset: (aci.leading, aci.trailing), indInset: (t.leading, t.trailing), offset: offset.x,
                        otherVisible: verticalOn)
                : nil,
            vertical: verticalOn
                ? thumb(viewport: m.viewportSize.height, content: m.contentSize.height, zoom: s,
                        inset: (aci.top, aci.bottom), indInset: (t.top, t.bottom), offset: offset.y,
                        otherVisible: horizontalOn)
                : nil)
    }

    /// The inset of the thumbs' track: the safe area the content actually adjusts for (`adjustedContentInset` minus the
    /// developer inset and the refresh hold, UIKit's `automaticallyAdjustsScrollIndicatorInsets`) plus the state's
    /// `scrollIndicatorInsets` plus the view's `extra` (`contentMargins(for: .scrollIndicators)`).
    static func trackInsets(_ m: ScrollMetrics, extra: EdgeInsets) -> EdgeInsets {
        let a = m.adjustedContentInset, c = m.contentInset, h = m.refreshHold, i = m.indicatorInsets
        func sum(_ adjusted: CGFloat, _ content: CGFloat, _ hold: CGFloat, _ own: CGFloat, _ more: CGFloat) -> CGFloat {
            max(0, adjusted - content - hold) + own + more
        }
        return EdgeInsets(top: sum(a.top, c.top, h.top, i.top, extra.top),
                          leading: sum(a.leading, c.leading, h.leading, i.leading, extra.leading),
                          bottom: sum(a.bottom, c.bottom, h.bottom, i.bottom, extra.bottom),
                          trailing: sum(a.trailing, c.trailing, h.trailing, i.trailing, extra.trailing))
    }
}

// MARK: - Visibility resolution

/// The visibility of both axes after the layers are combined.
struct ResolvedIndicators: Equatable {
    var horizontal: ZTronScrollIndicatorVisibility = .automatic
    var vertical: ZTronScrollIndicatorVisibility = .automatic

    func draws(_ v: ZTronScrollIndicatorVisibility) -> Bool { v == .automatic || v == .visible }
    var drawsAnything: Bool { draws(horizontal) || draws(vertical) }
    /// Activity and flashes show something only on `.automatic` axes (`.visible` is always shown, `.hidden` never).
    var hasAutomatic: Bool { horizontal == .automatic || vertical == .automatic }
}

enum IndicatorResolution {
    /// Per axis: `member` ?? `twin` ?? the native environment (iOS 16.4+) ?? `.automatic`. `showsIndicators: false` (the
    /// view's own default, `member` only) decides what `.automatic` means: hidden. An explicit `.visible` beats it, as in
    /// SwiftUI's `ScrollView` (measured on iOS 17.5 and 27.0 in `NativeIndicatorFixtureTests`).
    static func resolve(member: ChromeConfig, twin: ChromeConfig, native: AxisPair<ZTronScrollIndicatorVisibility>?)
        -> ResolvedIndicators {
        func axis(_ m: ZTronScrollIndicatorVisibility?, _ t: ZTronScrollIndicatorVisibility?,
                  _ n: ZTronScrollIndicatorVisibility?) -> ZTronScrollIndicatorVisibility {
            let explicit = m ?? t ?? n ?? .automatic
            return explicit == .automatic && member.showsIndicators == false ? .hidden : explicit
        }
        return ResolvedIndicators(
            horizontal: axis(member.indicators.horizontal, twin.indicators.horizontal, native?.horizontal),
            vertical: axis(member.indicators.vertical, twin.indicators.vertical, native?.vertical))
    }
}

// MARK: - Fade controller

/// The cold half of the fade: whether the `.automatic` thumbs are shown. Shown while the content is active, for
/// `hideDelay` after it stops and for `flashHold` after a flash, then faded out over `fade` by one SwiftUI animation: no
/// frame clock, no polling; one one-shot timer per deadline (the refresh coordinator's pattern, tests fire it by hand).
@MainActor
final class IndicatorController: ObservableObject {
    /// The opacity target of the `.automatic` thumbs. Changes at most a few times per interaction.
    @Published private(set) var isShown = false

    /// Clock for the deadlines; the host sets it to the state's clock.
    var now: @MainActor () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    /// One-shot timer; tests replace it to drive the clock by hand.
    var schedule: (_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> Void = { delay, fire in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { fire() } }
    }

    /// `false` while no axis is `.automatic`: activity and flashes show nothing and start no timer.
    private(set) var isEnabled = true
    /// The content is moving (interacting, decelerating or animating).
    private(set) var isActive = false
    /// Latest instant until which the thumbs stay shown without activity (hide delay or flash hold).
    private(set) var holdUntil: TimeInterval = -.infinity
    private var wakePending = false
    #if DEBUG
    /// What the last leaf evaluation drew (the render probe of the tests).
    private(set) var lastRender: (layout: IndicatorLayout, horizontalOpacity: Double, verticalOpacity: Double)?
    #endif

    /// DEBUG render probe: remembers the layout and opacities the hot leaf just drew (a no-op in release builds).
    func recordRender(_ layout: IndicatorLayout, horizontalOpacity: Double, verticalOpacity: Double) {
        #if DEBUG
        lastRender = (layout, horizontalOpacity, verticalOpacity)
        #endif
    }

    #if DEBUG
    /// The size the overlay was laid out at (DEBUG probe): chrome positions are viewport coordinates only if it equals the
    /// viewport, which is why the overlay sits inside `.ignoresSafeArea` in the container.
    private(set) var lastOverlaySize: CGSize?
    func noteOverlaySize(_ size: CGSize) { lastOverlaySize = size }
    #endif

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            holdUntil = -.infinity
            setShown(false, animated: false)
        } else {
            evaluate()
        }
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if !active { holdUntil = max(holdUntil, now() + IndicatorStyle.hideDelay) }
        evaluate()
    }

    /// Shows the thumbs for `flashHold`, once per call (never per frame).
    func flash() {
        guard isEnabled else { return }
        #if DEBUG
        ZTronRenderCounters.increment("indicators.flash")
        #endif
        holdUntil = max(holdUntil, now() + IndicatorStyle.flashHold)
        evaluate()
    }

    /// The view left the screen: nothing stays shown or scheduled.
    func reset() {
        isActive = false
        holdUntil = -.infinity
        setShown(false, animated: false)
    }

    /// Applies the rule "shown iff active or inside a hold" and schedules the wake-up that ends the hold.
    func evaluate() {
        let t = now()
        let shouldShow = isEnabled && (isActive || t < holdUntil)
        setShown(shouldShow, animated: true)
        guard shouldShow, !isActive, !wakePending else { return }
        wakePending = true
        schedule(max(0, holdUntil - t)) { [weak self] in
            guard let self else { return }
            self.wakePending = false
            self.evaluate()
        }
    }

    private func setShown(_ shown: Bool, animated: Bool) {
        guard shown != isShown else { return }
        if shown || !animated {
            // Appears at once (and cancels a fade in flight).
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isShown = shown }
        } else {
            #if DEBUG
            ZTronRenderCounters.increment("indicators.fadeOut")
            #endif
            withAnimation(.linear(duration: IndicatorStyle.fade)) { isShown = false }
        }
    }
}

// MARK: - Overlay (cold host + hot leaf)

/// The container's overlay hook: reads the native environment where it can (iOS 16.4+) and hands it to the host.
struct ScrollIndicatorsOverlay: View {
    let state: ZTronScrollState
    let member: ChromeConfig

    var body: some View {
        IndicatorNativeEnvironment { native in
            ScrollIndicatorsHost(state: state, member: member, native: native)
        }
    }
}

/// Cold: resolves the configuration, owns the controller and runs the flash lifecycle. Re-evaluates when the
/// configuration changes, never per frame.
struct ScrollIndicatorsHost: View {
    let state: ZTronScrollState
    let member: ChromeConfig
    let native: AxisPair<ZTronScrollIndicatorVisibility>?
    @Environment(\.ztronChromeConfig) private var twin
    @StateObject private var controller = IndicatorController()

    var body: some View {
        #if DEBUG
        ZTronRenderCounters.increment("indicators.host.body")
        #endif
        let resolved = IndicatorResolution.resolve(member: member, twin: twin, native: native)
        let extra = member.indicatorInsets ?? twin.indicatorInsets ?? EdgeInsets()
        let flashOnAppear = member.flashOnAppear ?? twin.flashOnAppear ?? false
        return ScrollIndicatorsLeaf(state: state, controller: controller, resolved: resolved, extraInsets: extra)
            .modifier(OverlayFrameProbe(controller: controller))
            .onAppear {
                controller.now = { state.now() }
                controller.setEnabled(resolved.hasAutomatic)
                state.indicatorController = controller
                if flashOnAppear { controller.flash() }
            }
            .onDisappear {
                if state.indicatorController === controller { state.indicatorController = nil }
                controller.reset()
            }
            .onChangeCompat(of: resolved.hasAutomatic) { controller.setEnabled($0) }
            .onChangeCompat(of: member.flashTrigger) { _ in controller.flash() }
            .onChangeCompat(of: twin.flashTrigger) { _ in controller.flash() }
    }
}

/// DEBUG only: reports the overlay's laid-out size to the controller; the identity in release builds.
struct OverlayFrameProbe: ViewModifier {
    let controller: IndicatorController

    func body(content: Content) -> some View {
        #if DEBUG
        content.background(GeometryReader { geometry -> Color in
            controller.noteOverlaySize(geometry.size)
            return Color.clear
        })
        #else
        content
        #endif
    }
}

/// Subscribes to the controller (cold) and builds the hot leaf.
struct ScrollIndicatorsLeaf: View {
    let state: ZTronScrollState
    @ObservedObject var controller: IndicatorController
    let resolved: ResolvedIndicators
    let extraInsets: EdgeInsets

    /// A resize in flight reports `.animating` for its own watch; that is not scrolling.
    static func isActive(_ sample: ChromeSample) -> Bool {
        switch sample.phase {
        case .interacting, .decelerating, .animating: return !sample.metrics.resize.isOpen
        case .idle, .tracking: return false
        }
    }

    var body: some View {
        let shown = controller.isShown
        let resolved = resolved, extra = extraInsets
        let controller = controller, state = state
        return ChromeLeaf(state, channels: resolved.drawsAnything ? .all : []) { sample in
            let track = IndicatorMath.trackInsets(sample.metrics, extra: extra)
            let layout = IndicatorMath.layout(offset: sample.offset, zoom: sample.zoom, metrics: sample.metrics,
                                              trackInsets: track, resolved: resolved, axes: state.scrollAxes,
                                              zoomEnabled: state.isZoomEnabled)
            let active = Self.isActive(sample)
            let horizontalOpacity: Double = resolved.horizontal == .visible || shown ? 1 : 0
            let verticalOpacity: Double = resolved.vertical == .visible || shown ? 1 : 0
            let _ = controller.recordRender(layout, horizontalOpacity: horizontalOpacity, verticalOpacity: verticalOpacity)
            IndicatorThumbs(layout: layout, viewport: sample.metrics.viewportSize, perpendicular: track,
                            horizontalOpacity: horizontalOpacity, verticalOpacity: verticalOpacity)
                .onChangeCompat(of: active) { controller.setActive($0) }
                .onAppear { controller.setActive(active) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The capsules, placed in the viewport's top-leading frame. A plain value view: it only draws.
struct IndicatorThumbs: View {
    let layout: IndicatorLayout
    let viewport: CGSize
    let perpendicular: EdgeInsets
    let horizontalOpacity: Double
    let verticalOpacity: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let v = layout.vertical {
                Capsule().fill(IndicatorStyle.color)
                    .frame(width: IndicatorStyle.thickness, height: v.length)
                    .offset(x: viewport.width - IndicatorStyle.edgeGap - IndicatorStyle.thickness - perpendicular.trailing,
                            y: v.origin)
                    .opacity(verticalOpacity)
            }
            if let h = layout.horizontal {
                Capsule().fill(IndicatorStyle.color)
                    .frame(width: h.length, height: IndicatorStyle.thickness)
                    .offset(x: h.origin,
                            y: viewport.height - IndicatorStyle.edgeGap - IndicatorStyle.thickness - perpendicular.bottom)
                    .opacity(horizontalOpacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
