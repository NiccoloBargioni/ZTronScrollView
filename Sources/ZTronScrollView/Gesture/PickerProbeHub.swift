import SwiftUI

/// `View.ztronScrollPickersAbsorbDrags(_:)` on iOS 17+ (spike PICKER-s2): the outermost `ZTronScrollView` of a tree installs
/// the one window probe, and the views nested in it join its hub to hear its reports. A probe anchor inside a nested view
/// breaks that view's own drags on 17.5 and 27.0 (`docs/design/PICKER-decline.md` §5.1); every probe on a window sees the
/// same touches anyway, so one per tree loses nothing. On 15-16 every view keeps its own D31 recognizer and hub.
@MainActor
final class PickerProbeHub: Equatable {
    private struct Member { weak var coordinator: PanCoordinator? }
    private weak var owner: PanCoordinator?
    private var members: [Member] = []

    init(owner: PanCoordinator) { self.owner = owner }

    /// Idempotent. Members that went away are dropped here; one whose modifier turned false ignores what it hears.
    func join(_ coordinator: PanCoordinator) {
        members.removeAll { $0.coordinator == nil }
        guard coordinator !== owner, !members.contains(where: { $0.coordinator === coordinator }) else { return }
        members.append(Member(coordinator: coordinator))
    }

    /// The probe at a sequence's first finger down: the owner and every member hear the same answer.
    func report(onPicker: Bool) {
        owner?.touchSequenceBegan(onPicker: onPicker)
        for member in members { member.coordinator?.touchSequenceBegan(onPicker: onPicker) }
    }

    var memberCount: Int { members.filter { $0.coordinator != nil }.count }

    nonisolated static func == (l: PickerProbeHub, r: PickerProbeHub) -> Bool { l === r }
}

private struct PickerProbeHubKey: EnvironmentKey {
    static var defaultValue: PickerProbeHub? { nil }
}

extension EnvironmentValues {
    /// The probe hub of the outermost enclosing `ZTronScrollView` (set on its content and passed down unchanged).
    var ztronPickerProbeHub: PickerProbeHub? {
        get { self[PickerProbeHubKey.self] }
        set { self[PickerProbeHubKey.self] = newValue }
    }
}
