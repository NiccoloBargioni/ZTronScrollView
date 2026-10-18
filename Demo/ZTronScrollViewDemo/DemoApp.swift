import SwiftUI
import ZTronScrollView

@main
struct DemoApp: App {
    init() {
        // Must run before any view is created (design §10).
        if ProcessInfo.processInfo.arguments.contains("-ZTronForceAllFallbacks") {
            ZTronAvailability.forceAllFallbacks(true)
        }
    }

    var body: some Scene {
        WindowGroup { ProofScreen() }
    }
}
