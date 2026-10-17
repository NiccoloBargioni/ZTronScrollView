import SwiftUI

/// `defaultValue` is computed: a stored static of the non-`Sendable` existential is rejected under Swift 6
/// strict concurrency on older toolchains, while a computed getter is safe on all of them.
private struct ScrollArbiterKey: EnvironmentKey {
    static var defaultValue: (any ScrollArbiter)? { nil }
}

extension EnvironmentValues {
    /// The arbiter a scroller inside a container registers with; `nil` by default.
    ///
    /// A participant with no arbiter in its environment behaves exactly as a standalone scroller.
    public var scrollArbiter: (any ScrollArbiter)? {
        get { self[ScrollArbiterKey.self] }
        set { self[ScrollArbiterKey.self] = newValue }
    }
}
