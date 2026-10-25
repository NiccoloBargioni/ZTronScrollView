import SwiftUI
import ZTronScrollView

@main
struct DemoApp: App {
    init() {
        // Must run before any view is created (design §10).
        if ProcessInfo.processInfo.arguments.contains("-ZTronForceAllFallbacks") {
            ZTronAvailability.forceAllFallbacks(true)
        }
        // The iOS 15-16 UIKit touch observer (D31) on a 17+ simulator: spatial events off, observer on. With
        // -ZTronForceAllFallbacks it is the shipped 15-16 shape.
        if ProcessInfo.processInfo.arguments.contains("-ZTronForceUIKitObserver") {
            ZTronAvailability.forceFallback(.spatialEvents, true)
            ZTronAvailability.forceUIKitTouchObserver(true)
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
            case "nestedPager": NestedPagerScreen()
            case "targets": TargetsScreen()
            case "eventLog": EventLogScreen()
            case "refresh": RefreshScreen()
            case "zoom": ZoomScreen()
            case "image": ImageScreen()
            case "calibrate": CalibrateScreen()
            case "resize": ResizeScreen()
            case "sheet": SheetScreen()
            case "scrollDisabled": ScrollDisabledScreen()
            case "buttonDrag": ButtonDragScreen()
            default: ProofScreen()
            }
        }
    }
}
