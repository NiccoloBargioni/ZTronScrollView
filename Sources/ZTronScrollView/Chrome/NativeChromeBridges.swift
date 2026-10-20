import SwiftUI

// Conversions between the chrome mirrors and SwiftUI's own types (SPEC S8-4, design M8-chrome §1; D3 gating). Each type is
// gated at the first OS where the conversion can be written: SwiftUI's value types are opaque structs, so "native → ours"
// compares with the native statics through `Equatable` (the indicator visibility is `Equatable` from iOS 16.4, though the
// type itself exists from 16.0), and "ours → native" is a switch onto the statics. Indicator part (M8-1); the other chrome
// types append their conversions here.

// MARK: Scroll indicator visibility (16.0 / 16.4)

@available(iOS 16, *)
extension ZTronScrollIndicatorVisibility {
    /// SwiftUI's value for this case.
    public var native: ScrollIndicatorVisibility {
        switch self {
        case .automatic: return .automatic
        case .visible: return .visible
        case .hidden: return .hidden
        case .never: return .never
        }
    }
}

@available(iOS 16.4, *)
extension ZTronScrollIndicatorVisibility {
    /// Our case for SwiftUI's value, by comparing with its statics (`Equatable` from iOS 16.4); `nil` for a case this
    /// library does not know.
    public init?(_ native: ScrollIndicatorVisibility) {
        if native == .automatic {
            self = .automatic
        } else if native == .visible {
            self = .visible
        } else if native == .hidden {
            self = .hidden
        } else if native == .never {
            self = .never
        } else {
            return nil
        }
    }
}

/// Reads SwiftUI's `horizontalScrollIndicatorVisibility` / `verticalScrollIndicatorVisibility` (the environment the native
/// `scrollIndicators(_:axes:)` writes) and hands both to `content`. The keys exist from iOS 16.0, but the values can be
/// mapped from 16.4 on, so this is the 16.4 half of the resolution; below it `IndicatorNativeEnvironment` passes `nil`.
@available(iOS 16.4, *)
struct NativeIndicatorVisibilityReader<Content: View>: View {
    let content: (AxisPair<ZTronScrollIndicatorVisibility>?) -> Content
    @Environment(\.horizontalScrollIndicatorVisibility) private var horizontal
    @Environment(\.verticalScrollIndicatorVisibility) private var vertical

    var body: some View {
        content(AxisPair(horizontal: ZTronScrollIndicatorVisibility(horizontal),
                         vertical: ZTronScrollIndicatorVisibility(vertical)))
    }
}

/// The native indicator environment where it can be read (iOS 16.4+), `nil` below. A static `#available` branch (the OS
/// never changes), so the content's structural identity is stable.
struct IndicatorNativeEnvironment<Content: View>: View {
    let content: (AxisPair<ZTronScrollIndicatorVisibility>?) -> Content

    init(@ViewBuilder content: @escaping (AxisPair<ZTronScrollIndicatorVisibility>?) -> Content) {
        self.content = content
    }

    var body: some View {
        if #available(iOS 16.4, *) {
            NativeIndicatorVisibilityReader(content: content)
        } else {
            content(nil)
        }
    }
}
