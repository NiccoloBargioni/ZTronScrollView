import CoreGraphics
import Foundation

/// Per-axis bounce policy with the cases of SwiftUI's `ScrollBounceBehavior` (iOS 16.4).
///
/// Conversion works in one direction only: `BounceBehavior` → `ScrollBounceBehavior` (a `switch` onto the public
/// static members). SwiftUI's type is an opaque struct without `Equatable` and without public cases, so a value set
/// with `.scrollBounceBehavior(_:axes:)` (and read from `EnvironmentValues.vertical/horizontalScrollBounceBehavior`)
/// cannot be mapped back to `.automatic` / `.always` / `.basedOnSize` without reflection, which the library does not
/// use. The SwiftUI layer therefore carries this type in its own modifier and environment key
/// (`ztronScrollBounceBehavior(_:axes:)`); see the "Limitations" of `docs/design/design-note.md`.
public enum BounceBehavior: Sendable, Hashable, CaseIterable {
    /// Native default: bounces on every enabled axis.
    case automatic
    /// Always bounces.
    case always
    /// Bounces only when the content is larger than the viewport on that axis.
    case basedOnSize
}

/// Resolves whether one axis rubber-bands, combining SwiftUI's bounce behavior with UIKit's
/// `bounces` / `alwaysBounceVertical` / `alwaysBounceHorizontal` knobs (SPEC S6 "Bounce").
public struct BounceConfiguration: Sendable, Equatable {
    /// SwiftUI `scrollBounceBehavior(_:axes:)` equivalent.
    public var behavior: BounceBehavior
    /// `UIScrollView.bounces`: `false` wins over everything.
    public var bounces: Bool
    /// `alwaysBounceVertical` / `alwaysBounceHorizontal` for this axis.
    public var alwaysBounce: Bool

    public init(behavior: BounceBehavior = .automatic, bounces: Bool = true, alwaysBounce: Bool = false) {
        self.behavior = behavior
        self.bounces = bounces
        self.alwaysBounce = alwaysBounce
    }

    /// - `bounces == false` → `false`
    /// - `.always` → `true`
    /// - `.basedOnSize` → `isScrollable || alwaysBounce`
    /// - `.automatic` → `isAxisEnabled || alwaysBounce` (a vertical native `ScrollView` bounces vertically even when
    ///   its content fits)
    public func resolve(isAxisEnabled: Bool, isScrollable: Bool) -> Bool {
        guard bounces else { return false }
        switch behavior {
        case .always: return true
        case .basedOnSize: return isScrollable || alwaysBounce
        case .automatic: return isAxisEnabled || alwaysBounce
        }
    }
}
