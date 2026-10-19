import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        // `-zoomCal`: the native zoom-animation calibration screen (ZoomCalibrationViewController) instead of the pager.
        window.rootViewController = ProcessInfo.processInfo.arguments.contains("-zoomCal")
            ? ZoomCalibrationViewController() : PagerViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
