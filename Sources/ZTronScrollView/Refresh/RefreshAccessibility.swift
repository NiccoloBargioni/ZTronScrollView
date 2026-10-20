import SwiftUI

// Accessibility of the refreshers (SPEC S9, design M8b §1.3): VoiceOver and Switch Control users cannot pull, so every
// refresher edge carries an element with the named actions "Refresh" (start edges) / "Load more" (end edges), announced
// through `AccessibilityNotification.Announcement` on iOS 17+. Below 17 there is no public way to announce from SwiftUI
// without UIKit: the element's `accessibilityValue` carries the state instead (read on focus, not announced: a documented gap).

enum RefreshAccessibility {
    static func label(for edge: Edge) -> String {
        edge == .bottom || edge == .trailing ? "Load more" : "Refresh"
    }

    static func value(for mode: ZTronRefreshState.Mode) -> String {
        switch mode {
        case .notRefreshing: return "Idle"
        case .pulling: return "Pulling"
        case .refreshing: return "Refreshing"
        }
    }

    static func name(of edge: Edge) -> String {
        switch edge {
        case .top: return "top"
        case .leading: return "leading"
        case .bottom: return "bottom"
        case .trailing: return "trailing"
        }
    }

    /// The accessibility action: starts the refresh with its action, unless one is already running (one at a time).
    @MainActor
    static func perform(_ edge: Edge, on coordinator: RefreshCoordinator) {
        guard !coordinator.engines.values.contains(where: { $0.isRefreshing }) else { return }
        coordinator.begin(edge, runAction: true)
    }

    static func announce(_ text: String) {
        if #available(iOS 17, *) {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

/// A small, hit-test-transparent accessibility element per refresher edge (the overlay is `allowsHitTesting(false)`; an
/// accessibility action does not need a touch). Start edges sit at the top leading corner, end edges at the bottom trailing.
struct RefreshAccessibilityElement: View {
    @ObservedObject var coordinator: RefreshCoordinator
    let edge: Edge

    var body: some View {
        let label = RefreshAccessibility.label(for: edge)
        let mode = coordinator.states[edge]?.mode ?? .notRefreshing
        let isEnd = edge == .bottom || edge == .trailing
        return Color.clear
            .frame(width: 44, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(RefreshAccessibility.value(for: mode)))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("ztron.refresh.a11y.\(RefreshAccessibility.name(of: edge))")
            .accessibilityAction { RefreshAccessibility.perform(edge, on: coordinator) }
            .accessibilityAction(named: Text(label)) { RefreshAccessibility.perform(edge, on: coordinator) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isEnd ? .bottomTrailing : .topLeading)
    }
}
