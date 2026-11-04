import SwiftUI
@testable import ZTronScrollView

/// D80: the refresh slots as the container lays them out, for the suites that host the indicators without a scroll view:
/// on the path without layer groups (15–16, the forced fallbacks) the `.behind` host under the `.front` one, else the front
/// host alone. Each leaf draws in one of them (`RefreshLayerMath.draws`).
struct RefreshSlots: View {
    let coordinator: RefreshCoordinator
    let state: ZTronScrollState
    let specs: [Edge: RefresherSpec]

    var body: some View {
        ZStack {
            if !state.usesGeometryGroup {
                RefreshIndicatorsHost(coordinator: coordinator, state: state, specs: specs, layer: .behind)
            }
            RefreshIndicatorsHost(coordinator: coordinator, state: state, specs: specs)
        }
    }
}
