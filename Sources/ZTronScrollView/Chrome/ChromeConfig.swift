import SwiftUI

// Cold chrome settings (SPEC S8, design M8-chrome §1). The shape every M8 modifier follows: a MEMBER on `ZTronScrollView`
// (stored in `ZTronScrollView.chrome`, binds to that view only) and a `ztron`-prefixed `View` TWIN (writes
// `EnvironmentValues.ztronChromeConfig`, reaches every `ZTronScrollView` below, and applies SwiftUI's own modifier
// under `#available`, D8). Resolution inside the container: member, else twin, else the native environment where it can
// be read, else the default. Both layers are optional per field, so "unset" is distinct from an explicit value (an
// explicit `.automatic` overrides an outer `.hidden`, as in SwiftUI). Later M8 tasks append their fields here.

/// A value per axis; `nil` leaves the axis alone (the layer says nothing about it).
struct AxisPair<Value: Equatable>: Equatable {
    var horizontal: Value?
    var vertical: Value?

    init(horizontal: Value? = nil, vertical: Value? = nil) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// Writes `value` on the axes in `axes` (a modifier's `axes:` argument).
    mutating func set(_ value: Value?, axes: Axis.Set) {
        if axes.contains(.horizontal) { horizontal = value }
        if axes.contains(.vertical) { vertical = value }
    }
}

/// A type-erased `Equatable` (a trigger is only `Equatable`, not `Hashable`, so `AnyHashable` does not fit): equal when
/// both wrap the same type and the values compare equal.
struct AnyEquatable: Equatable {
    private let value: Any
    private let isEqual: (Any) -> Bool

    init<T: Equatable>(_ value: T) {
        self.value = value
        self.isEqual = { ($0 as? T) == value }
    }

    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool { lhs.isEqual(rhs.value) }
}

/// The chrome settings one layer (the member's or the environment's) declares. Equatable: the container compares
/// configurations to decide whether the cold overlay has to re-resolve.
struct ChromeConfig: Equatable {
    /// `scrollIndicators(_:axes:)` / `ztronScrollIndicators(_:axes:)` per axis.
    var indicators = AxisPair<ZTronScrollIndicatorVisibility>()
    /// `ZTronScrollView.init(_:showsIndicators:content:)`: `false` hides both axes; `true` is the default and says nothing.
    var showsIndicators: Bool?
    /// `contentMargins(_:_:for: .scrollIndicators)` (M8-2) lands here: added to the scroll indicator insets.
    var indicatorInsets: EdgeInsets?
    /// `scrollIndicatorsFlash(onAppear:)`.
    var flashOnAppear: Bool?
    /// `scrollIndicatorsFlash(trigger:)`: the indicators flash once each time the value changes.
    var flashTrigger: AnyEquatable?
}

private struct ChromeConfigKey: EnvironmentKey {
    static var defaultValue: ChromeConfig { ChromeConfig() }
}

extension EnvironmentValues {
    /// The chrome settings the `ztron…` twins carry down to the `ZTronScrollView`s below (cold; never a hot value).
    var ztronChromeConfig: ChromeConfig {
        get { self[ChromeConfigKey.self] }
        set { self[ChromeConfigKey.self] = newValue }
    }
}
