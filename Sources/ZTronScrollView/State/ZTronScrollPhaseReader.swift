import SwiftUI

/// Re-renders `content` only when the interaction phase changes (SPEC S11), on both storage paths. Offset and zoom
/// writes never wake it. Built on ``ZTronScrollReader`` with the phase as the derived value.
public struct ZTronScrollPhaseReader<Content: View>: View {
    private let explicitState: ZTronScrollState?
    private let content: (ZTronScrollPhase) -> Content

    public init(_ state: ZTronScrollState? = nil, @ViewBuilder content: @escaping (ZTronScrollPhase) -> Content) {
        self.explicitState = state
        self.content = content
    }

    public var body: some View {
        ZTronScrollReader(explicitState, of: { $0.phase }, content: content)
    }
}
