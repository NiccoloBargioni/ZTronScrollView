import SwiftUI

/// Named coordinate spaces (design §7). `content` sits under the transform effect: frames read in it do not change
/// while scrolling; `viewport` is the clipped, untransformed container.
public enum ZTronCoordinateSpaces {
    public static var content: CoordinateSpace { CoordinateSpace.named("ztronScroll.content") }
    public static var viewport: CoordinateSpace { CoordinateSpace.named("ztronScroll.viewport") }
}

@available(iOS 17, *)
public extension NamedCoordinateSpace {
    static var ztronContent: NamedCoordinateSpace { .named("ztronScroll.content") }
    static var ztronViewport: NamedCoordinateSpace { .named("ztronScroll.viewport") }
}

struct ViewportMetrics: Equatable {
    var size: CGSize
    var safeArea: EdgeInsets
    /// D64: the keyboard probe's value (`ScrollMetrics.keyboardExtension`) when it travels with this report (15 / forced:
    /// one preference carries both); `nil`: not part of it (16+: the probe records it from its layout pass, `setKeyboardExtension`).
    var keyboard: CGFloat? = nil
}

/// Declares a coordinate space; the `if` is on a `let` flag, so the placeholder's branch never flips (R6).
struct NamedSpaceModifier: ViewModifier {
    let name: String
    let useNew: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if useNew, #available(iOS 17, *) {
            content.coordinateSpace(.named(name))
        } else {
            content.coordinateSpace(name: name)
        }
    }
}

struct ViewportMetricsKey: PreferenceKey {
    static let defaultValue = ViewportMetrics(size: .zero, safeArea: EdgeInsets())
    static func reduce(value: inout ViewportMetrics, nextValue: () -> ViewportMetrics) {
        let n = nextValue()
        // Siblings contribute the default; keep the real one. The keyboard probe (D64) contributes only its own field.
        if n.size != .zero { value.size = n.size; value.safeArea = n.safeArea }
        if let k = n.keyboard { value.keyboard = k }
    }
}

/// Lives in the viewport's background, never around content.
struct ViewportObserver: ViewModifier {
    let state: ZTronScrollState
    /// The edges the viewport root ignores the safe area on. The observed frame lies inside the safe area, so the
    /// viewport (what the effect is asked about) is that frame plus the ignored insets.
    let edges: Edge.Set

    private func metrics(size: CGSize, safe: EdgeInsets) -> ViewportMetrics {
        ViewportMetrics(size: CGSize(width: size.width + (edges.contains(.leading) ? safe.leading : 0) + (edges.contains(.trailing) ? safe.trailing : 0),
                                     height: size.height + (edges.contains(.top) ? safe.top : 0) + (edges.contains(.bottom) ? safe.bottom : 0)),
                        safeArea: safe)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if state.usesGeometryChange, #available(iOS 16, *) {
            // The probe records its height from its own layout pass, so the viewport report of the same update (an
            // action, after layout) commits it with the safe area it belongs to. A geometry action of its own is not
            // ordered against the container's: on 27.0 the keyboard's dismissal reached the state viewport first, and
            // `R` was resolved with the keyboard still in (586 pt container, R 293 pt, drawn for 4 frames).
            content
                .background(alignment: .bottom) {
                    KeyboardProbe.frame { KeyboardProbeLayout(state: state) { Color.clear } }
                }
                .onGeometryChange(for: ViewportMetrics.self,
                                  of: { metrics(size: $0.size, safe: $0.safeAreaInsets) },
                                  action: { state.setViewport($0) })
        } else {
            // One preference carries both reports, so they reach the state together.
            content
                .background(GeometryReader {
                    Color.clear.preference(key: ViewportMetricsKey.self,
                                           value: metrics(size: $0.size, safe: $0.safeAreaInsets))
                })
                .background(alignment: .bottom) {
                    KeyboardProbe.frame {
                        GeometryReader {
                            Color.clear.preference(key: ViewportMetricsKey.self,
                                                   value: ViewportMetrics(size: .zero, safeArea: EdgeInsets(),
                                                                          keyboard: $0.size.height))
                        }
                    }
                }
                .onPreferenceChange(ViewportMetricsKey.self) { state.setViewport($0) }
        }
    }
}

/// D64: the keyboard probe. A zero-height box on the container's bottom edge that ignores the `.keyboard` safe-area region
/// there: SwiftUI extends it down to the keyboard-free safe area, so its height is how far the keyboard's region reaches
/// above that (`ScrollMetrics.keyboardExtension`; 0 without a keyboard, and then it never changes: a rotation, a bar or a
/// `.safeAreaInset` leaves it alone). The header's slot ignores the same region (`ScrollContainer`), so it is the
/// container's region between the safe areas plus this height. Cold: its geometry changes when the keyboard does.
enum KeyboardProbe {
    static func frame<V: View>(@ViewBuilder _ reader: () -> V) -> some View {
        reader()
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 16+: the keyboard probe's reader. Placed in the probe's extended frame, it records that frame's height in the state
/// synchronously from the main thread's layout pass (`setKeyboardExtension`; the async renderer's passes lay out the
/// presented state and are skipped, as in `HeaderSlotLayout`). Fills its proposal. It needs a subview: SwiftUI never
/// placed an empty one (27.0, the seam lab: no report at all).
@available(iOS 16, *)
struct KeyboardProbeLayout: Layout {
    let state: ZTronScrollState

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for v in subviews { v.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
        guard Thread.isMainThread else { return }
        let h = bounds.height
        MainActor.assumeIsolated {
            #if DEBUG
            ZTronRenderCounters.increment("viewport.keyboardProbe")   // cold: never while scrolling (ScalingHeaderHostedTests)
            #endif
            state.setKeyboardExtension(h)
        }
    }
}

/// D75 K2 (M8b-s8 s9): the curve a keyboard-driven inset change that moves aligned fitting content is written in when the
/// turn has no transaction of its own (D64: the keyboard's report arrives with none) and the keyboard hides (a shown
/// keyboard's report lands inside UIKit's keyboard animation, which Core Animation already interpolates). UIKit's keyboard animation curve as
/// a spring (mass 3, stiffness 1000, damping 500; iOS 13+, the same on 15–16), so the content (and a `.headerFollows`
/// header) moves with the keyboard as SwiftUI's keyboard avoidance moves a native ScrollView's content.
enum KeyboardInsetFollow {
    static let animation = Animation.interpolatingSpring(mass: 3, stiffness: 1000, damping: 500)
}
