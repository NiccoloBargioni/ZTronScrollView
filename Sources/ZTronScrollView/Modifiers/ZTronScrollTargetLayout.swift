import SwiftUI

extension View {
    /// `scrollTargetLayout(isEnabled:)` for a ``ZTronScrollView`` (SPEC S8-3, dual mode): marks the layout whose children
    /// are the scroll targets of a view-aligned behavior. Inside a `ZTronScrollView` the targets are the children that carry
    /// ``ztronScrollID(_:)`` (SwiftUI's explicit ids are not observable, so they are not found automatically); with
    /// `isEnabled: false` view-aligned behaviors leave the release alone. On iOS 17+ SwiftUI's own modifier is applied as
    /// well, so a native `ScrollView` below follows the same layout. Cold: no content body re-runs for it.
    @ViewBuilder
    public func ztronScrollTargetLayout(isEnabled: Bool = true) -> some View {
        let marked = modifier(ScrollTargetLayoutModifier(isEnabled: isEnabled))
        if #available(iOS 17, *) {
            marked.scrollTargetLayout(isEnabled: isEnabled)
        } else {
            marked
        }
    }
}

/// Tells the enclosing scroll view's registry whether this layout counts as a target layout.
struct ScrollTargetLayoutModifier: ViewModifier {
    let isEnabled: Bool
    @Environment(\.ztronTargetRegistry) private var registry
    @State private var token = ReporterToken()

    func body(content: Content) -> some View {
        // `!=`-guarded and cold (the registry is not observed): safe in `body`, and re-run when `isEnabled` changes.
        registry?.setLayout(token, enabled: isEnabled)
        return content
            .onAppear { registry?.setLayout(token, enabled: isEnabled) }
            .onDisappear { registry?.removeLayout(token) }
    }
}
