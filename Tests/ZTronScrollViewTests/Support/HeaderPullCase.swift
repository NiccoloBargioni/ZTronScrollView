import SwiftUI
@testable import ZTronScrollView

/// The pull cases of a vertical scaling header (D65): `.preserve` `.openGap` (the default), `.preserve` `.followContent`
/// (D61) and `.stretch` (which ignores the pull behavior; it is set to `.followContent` there to show that).
enum HeaderPullCase: String, CaseIterable, Sendable, CustomStringConvertible {
    case openGap, followContent, stretch
    var description: String { rawValue }
    var behavior: ZTronHeaderScalingBehavior { self == .stretch ? .stretch : .preserve }
    var pull: ZTronHeaderPullBehavior { self == .openGap ? .openGap : .followContent }
}
