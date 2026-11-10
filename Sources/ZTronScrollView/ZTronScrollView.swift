import SwiftUI
import Combine
import ZTronScrollPhysics

/// Pure-SwiftUI scroll view. M2: render path only (offset / zoom transform, frame clock, programmatic commands);
/// gestures arrive in M3. The container's own body never reads hot values (SPEC S4).
public struct ZTronScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let externalState: ZTronScrollState?
    private let content: Content
    private var zoomLimits: ZoomLimits?
    private var doubleTap: DoubleTapZoom?
    private var nestedPolicy: ZTronNestedScrollPolicy?
    var config = ScrollViewConfig()
    /// Chrome members (indicators, M8): the `ztron…` twins carry the same settings in the environment.
    var chrome = ChromeConfig()
    @StateObject private var holder = StateHolder()

    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.externalState = nil
        self.content = content()
        if !showsIndicators { chrome.showsIndicators = false }
    }

    public init(_ axes: Axis.Set = .vertical, state: ZTronScrollState, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = true
        self.externalState = state
        self.content = content()
    }

    public var body: some View {
        let state = externalState ?? holder.state
        return ScrollContainer(axes: axes, state: state, content: content, zoomLimits: zoomLimits, doubleTap: doubleTap,
                               nestedPolicy: nestedPolicy, config: config, chrome: chrome)
            .environment(\.ztronScrollState, state)
    }
}

extension ZTronScrollView {
    /// Zoom limits, absolute or relative to the content's fit / fill scale (recomputed on resize). Zooming is enabled
    /// iff max > min; the default is 1...1, as in UIKit.
    public func zoomRange(min: ZTronZoomScale, max: ZTronZoomScale) -> Self {
        var copy = self
        copy.zoomLimits = ZoomLimits(min: min.bound, max: max.bound)
        return copy
    }

    /// Double tap toggles between the minimum scale and `scale` (default: the maximum), around the tap. Off by default.
    public func doubleTapToZoom(_ enabled: Bool = true, scale: ZTronZoomScale? = nil) -> Self {
        var copy = self
        copy.doubleTap = enabled ? DoubleTapZoom(scale: scale) : nil
        return copy
    }

    /// How this view yields a drag to the `ZTronScrollView` (or ScrollArbitration container) that holds it; see
    /// `ZTronNestedScrollPolicy`. Default `.automatic` (UIScrollView parity); `.independent` opts out.
    public func nestedScrollPolicy(_ policy: ZTronNestedScrollPolicy) -> Self {
        var copy = self
        copy.nestedPolicy = policy
        return copy
    }
}

/// Owns the state created by `init(_:showsIndicators:content:)`; created once per view identity.
@MainActor
final class StateHolder: ObservableObject {
    /// Stored (cost4-A): the synthesized `objectWillChange` reflects over every stored property for `@Published` fields
    /// (one first-use conformance lookup per field type at the first appearance); this class has none.
    nonisolated(unsafe) let objectWillChange = ObservableObjectPublisher()

    let state = ZTronScrollState()
}

/// content -> size measurement -> content space -> layout host -> TransformHost (the viewport-sized effect, M5 C1)
/// -> viewport space -> safe-area policy -> observer, clip, hit shape.
struct ScrollContainer<Content: View>: View {
    let axes: Axis.Set
    let state: ZTronScrollState
    let content: Content
    let zoomLimits: ZoomLimits?
    let doubleTap: DoubleTapZoom?
    let nestedPolicy: ZTronNestedScrollPolicy?
    let config: ScrollViewConfig
    let chrome: ChromeConfig
    @Environment(\.ztronZoomLimits) private var envLimits
    @Environment(\.ztronDoubleTapZoom) private var envDoubleTap
    @Environment(\.ztronScrollConfig) private var envConfig
    @Environment(\.ztronProxyScope) private var proxyScope
    @StateObject private var coordinator: PanCoordinator
    @StateObject private var observerStore = ObserverStore()
    /// The refresh coordinator and its cold bookkeeping, shared by the refresh slots (D80: front and behind).
    @StateObject private var refreshHolder: RefreshHolder

    init(axes: Axis.Set, state: ZTronScrollState, content: Content, zoomLimits: ZoomLimits? = nil,
         doubleTap: DoubleTapZoom? = nil, nestedPolicy: ZTronNestedScrollPolicy? = nil,
         config: ScrollViewConfig = ScrollViewConfig(), chrome: ChromeConfig = ChromeConfig()) {
        self.zoomLimits = zoomLimits
        self.chrome = chrome
        self.doubleTap = doubleTap
        self.nestedPolicy = nestedPolicy
        self.config = config
        self.axes = axes
        self.state = state
        self.content = content
        state.scrollAxes = axes
        _coordinator = StateObject(wrappedValue: PanCoordinator(state: state, axes: axes))
        _refreshHolder = StateObject(wrappedValue: RefreshHolder(state: state))
    }

    private var effectiveLimits: ZoomLimits { zoomLimits ?? envLimits ?? ZoomLimits() }

    var body: some View {
        let edges = state.contentInsetAdjustmentBehavior.edges(for: axes)
        // Member, else environment twin (M6): a cold write, never observed.
        state.targetBehavior = config.behavior ?? envConfig.behavior
        // Anchors and the position binding (M6 s3): cold writes; the binding's value is read here so a new one re-evaluates
        // this view and nothing in the content.
        state.initialOffsetAnchor = config.anchor(.initialOffset, else: envConfig)
        state.sizeChangesAnchor = config.anchor(.sizeChanges, else: envConfig)
        // D75: the alignment anchor is published by the hooks below (`alignmentChanged()`), never during this body.
        let alignmentAnchor = config.anchor(.alignment, else: envConfig)
        state.alignmentAnchorCold = alignmentAnchor
        let positionBinding = config.position ?? envConfig.position
        state.positionDriver.bind(positionBinding)
        let position = positionBinding?.read()
        let ticket = state.positionDriver.ticket(for: position)
        // Container role (NESTED §3): the ZTronScrollViews in the content register with this view's arbiter, with
        // frames in a named space on the content (cold: they do not change while this view scrolls). Constant per
        // identity, so the environment write never re-evaluates content bodies.
        let nested = coordinator.nestedArbiter
        let observerBoxes = observerStore.boxes(for: envConfig.observers + config.observers)
        // Scaling header (M8b-3): a cold write, resolved against the viewport width at the next layout (so the first
        // layout already reserves the resting height); a change after that is applied by `headerSpecChanged()` below.
        let header = config.header
        // D65: the pull behavior, member else environment twin else `.openGap` (as the target behavior above: this body
        // already depends on `envConfig`); it rides on the cold spec, so a change goes through `headerSpecChanged()`.
        let sizing = header?.sizing(pull: config.headerPull ?? envConfig.headerPull ?? .openGap)
        state.headerSpec = sizing
        // D75: a number that changes with what decides the content's alignment, so the `.transaction` hook below sees the
        // transaction of a `fittingContent:` or anchor change (the hooks publish the alignment in its animation).
        let alignmentTicket = state.alignmentTicket(.init(fitting: sizing?.fitting, anchor: alignmentAnchor))
        // D80: the refresh slot behind the content, only on the path without layer groups (the state's flag, fixed for its
        // life: 17+ build the tree without it).
        let refreshBehind = !state.usesGeometryGroup
        // cost4-A: the header slots from the first evaluation with a header on (`headerSlotsAttached`).
        if header != nil { state.headerSlotsAttached = true }
        let headerSlots = state.headerSlotsAttached
        return content
            // `.slideBehind(backdrop:)` (D68): the color behind the content, in content space (under the transform and the
            // content-integral overlays: it moves with the content and covers exactly its rect, so a `.slideBehind` header
            // never shows through a content without its own background). Always applied (`Color.clear`, drawing and
            // hit-testing nothing, without one): a backdrop or collapse mode change never changes the content's structure.
            .background { header?.collapse.backdrop ?? Color.clear }
            // Content-integral overlays (M6b): laid out from the content's own size, inside both content spaces and under
            // the transform; twins below members. Always applied (an empty list draws nothing).
            .overlay(alignment: .topLeading) {
                ContentOverlayHost(state: state, decls: envConfig.contentOverlays + config.contentOverlays)
            }
            .environment(\.ztronTargetRegistry, state.targets)
            .environment(\.scrollArbiter, nested)
            .modifier(ContentSizeMeasure(state: state))
            .modifier(NamedSpaceModifier(name: "ztronScroll.content", useNew: state.usesNamedCoordinateSpace))
            .modifier(NamedSpaceModifier(name: nested.coordinateSpaceName, useNew: state.usesNamedCoordinateSpace))
            .modifier(HeaderContentReserve(state: state))   // a horizontal view's content lays out below the banner (M8b-3)
            .modifier(ContentLayoutHost(axes: axes, useLayout: state.usesLayoutProtocol))
            .modifier(TransformHost(state: state, axes: axes, hasHeader: header != nil))
            .modifier(NamedSpaceModifier(name: "ztronScroll.viewport", useNew: state.usesNamedCoordinateSpace))
            .ignoresSafeArea(.all, edges: edges)
            // D80 (open item 27): on the path without layer groups (15–16, the forced fallbacks), a gap refresh indicator
            // without a layer group (a custom indicator, no scaling header) is drawn BEHIND the content, in the viewport's
            // own frame like the front slot below: it keeps no layer while its gap is off the screen, so a rotation that
            // brings the gap back cannot draw it over the content still sliding in (UIKit's refresh control is the scroll
            // view's lowest subview too). Every other indicator is drawn by the front slot (`RefreshLayerMath.draws`).
            .background(Group {
                if refreshBehind {
                    RefreshOverlay(state: state, pan: coordinator, holder: refreshHolder, axes: axes,
                                   member: config.refreshers, layer: .behind)
                        .ignoresSafeArea(.all, edges: edges)
                }
            })
            // A `.slideBehind` header (D68): the same slot as the overlay below (same frame, same layout pass, same safe-area
            // handling), BEHIND the content, which slides over it. Touches in the band the content leaves uncovered reach
            // it (the content's hit area is its own drawn frame). Both slots are always attached; `HeaderOverlay` shows
            // the header in the one of its mode.
            .background(alignment: .top) {
                if headerSlots {
                    HeaderOverlay(spec: header, state: state, behind: true)
                        .ignoresSafeArea(.all, edges: edges.subtracting([.top, .bottom]))
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        .modifier(HeaderLiftHost(state: state, axes: axes, viewportSized: false, slot: .headerBehind,
                                                 active: header?.collapse.kind.isSlideBehind == true))   // D75 lift
                }
            }
            // Scaling header (M8b-3), attached AFTER `.ignoresSafeArea`: SwiftUI places its slot's top edge at the safe-area
            // top in the same layout pass as the container size (no state, so a rotation or an animated resize moves it with
            // the content); the side edges are ignored again (full width). The bottom safe area is NOT ignored: the slot
            // is the region between the safe areas, so its height IS the overflow container (D59) of that same layout pass.
            // A committed bottom inset subtracted from a slot that reached the bottom was stale in the animated pass of a
            // resize that moves the scroll view's bottom off the home indicator (top-pinned height change: the inset goes
            // 34 -> 0 at the commit), so an engaged `.capped` / `.refit` limit was re-set by the commit (M8b-s6: 70 pt).
            // The keyboard is not part of the container (D64): the slot also ignores the `.keyboard` region on the bottom
            // edge, so showing or hiding the keyboard never changes `R` (the state resolves the same region:
            // `ScrollMetrics.keyboardExtension` from `ViewportObserver`'s probe); the content's inset still includes it.
            // D75 `.headerFollows`: the lift (`HeaderLiftHost`, `ScalingHeader/HeaderLift.swift`) moves the slot's header
            // onto fitting content's top edge, the content's padding term for term; identity on a view that never lifts.
            .overlay(alignment: .top) {
                if headerSlots {
                    HeaderOverlay(spec: header, state: state)
                        .ignoresSafeArea(.all, edges: edges.subtracting([.top, .bottom]))
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        .modifier(HeaderLiftHost(state: state, axes: axes, viewportSized: false, slot: .headerFront,
                                                 active: header.map { !$0.collapse.kind.isSlideBehind } ?? false))
                }
            }
            // Above the header (z-order contract), in the viewport's own frame again, so their metric coordinates hold.
            .overlay(RefreshOverlay(state: state, pan: coordinator, holder: refreshHolder, axes: axes,
                                    member: config.refreshers)
                .ignoresSafeArea(.all, edges: edges))   // refresh indicators (M8b)
            .overlay(ScrollIndicatorsOverlay(state: state, member: chrome)
                .ignoresSafeArea(.all, edges: edges))   // chrome leaves: the viewport's own frame (M8)
            .modifier(ViewportObserver(state: state, edges: edges))
            .modifier(MeasurementIsolation())
            .background(FrameClockDriver(state: state))
            .background(TargetEnvironmentCapture(state: state))
            .background(Group { if let proxyScope { ProxyFrameReporter(scope: proxyScope, state: state) } })
            .clipped()
            .contentShape(Rectangle())
            .modifier(PanGestureAdapter(coordinator: coordinator, axes: axes, doubleTap: doubleTap ?? envDoubleTap,
                                        nestedPolicy: nestedPolicy))
            .modifier(ObserverRegistration(state: state, boxes: observerBoxes))
            .modifier(PositionTicket(ticket: ticket))
            .modifier(PositionTicket(ticket: alignmentTicket))   // D75: see `alignmentTicket` above
            .transaction { state.positionDriver.noteTransaction($0) }
            .modifier(ContainerHooks(state: state, proxyScope: proxyScope,
                                     values: .init(position: position, limits: effectiveLimits, sizing: sizing,
                                                   anchor: alignmentAnchor)))
    }
}

/// The container's appear / disappear / change hooks in one modifier (cost4-A). They were five `onAppear`, one
/// `onDisappear` and four `onChangeCompat` stacked on the container's chain: every one a new wrapper type over the whole
/// chain (an `onChangeCompat` also an `AnyView` of it on 17+), each one first-use conformance lookups at the first
/// appearance. Same actions, same order: SwiftUI runs stacked `onAppear` (and `onChange`) actions inner first (27.0,
/// 17.5), so the merged appear runs them as they were stacked, and a change runs the changed values' actions in their
/// stacking order (position, zoom limits, header sizing, alignment anchor). The values a change compares against are the
/// ones the last appear or change saw (`ContainerHookValues.Box`), on every OS.
struct ContainerHooks: ViewModifier {
    let state: ZTronScrollState
    let proxyScope: ProxyScope?
    let values: ContainerHookValues
    @State private var last = ContainerHookValues.Box()

    func body(content: Content) -> some View {
        let state = state, proxyScope = proxyScope, values = values, last = last
        return content
            .onAppear {
                last.value = values
                state.zoomLimits = values.limits
                state.positionDriver.receive(values.position)
                proxyScope?.attach(state)
                state.headerSpecChanged()
                state.alignmentChanged()
            }
            .onDisappear { proxyScope?.detach(state) }
            .onChangeCompat(of: values) { new in
                let old = last.value
                last.value = new
                if old?.position != new.position { state.positionDriver.receive(new.position) }
                if old?.limits != new.limits { state.zoomLimits = new.limits }
                if old?.sizing != new.sizing { state.headerSpecChanged() }
                if old?.anchor != new.anchor { state.alignmentChanged() }
            }
    }
}

/// What `ContainerHooks` watches.
struct ContainerHookValues: Equatable {
    var position: ZTronScrollPosition?
    var limits: ZoomLimits
    var sizing: HeaderSizing?
    var anchor: UnitPoint?

    /// The values the last appear or change saw (never published).
    final class Box {
        var value: ContainerHookValues?
    }
}
