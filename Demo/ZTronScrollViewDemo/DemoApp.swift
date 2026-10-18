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

    static var screenName: String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-ZTronScreen"), i + 1 < a.count { return a[i + 1] }
        return "proof"
    }

    var body: some Scene {
        WindowGroup {
            switch DemoApp.screenName {
            case "pan": PanScreen()
            case "controls": ControlsScreen()
            case "pager": PagerScreen()
            case "zoom": ZoomScreen()
            case "image": ImageScreen()
            case "calibrate": CalibrateScreen()
            default: ProofScreen()
            }
        }
    }
}
