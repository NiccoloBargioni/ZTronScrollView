import XCTest

/// DBG-s8 measurement harness (not a contract): what stops a vertical drag that starts on a view inside SwiftUI's own vertical `ScrollView` from scrolling the
/// page, per gesture shape, per OS. It does nothing (skipped) unless `ZS_VARIANTS` is set, so the suite stays fast; re-run it on every new OS (docs/progress/DBG-s8.md).
///
///     TEST_RUNNER_ZS_VARIANTS='plain,drag10-sim,drag16-sim~300,zt-h' scripts/test-demo-ui.sh <destination> -only-testing:ZTronScrollViewDemoUITests/MixedProbeUITests
///
/// `ZS_VARIANTS` is a comma separated list of `name[^dxXdy][~velocity]`: `name` is a `-ZTronMixedVariant` of `MixedProbeScreen`, `^-80x0` the drag vector in points
/// (default 0 x -60), `~slow|default|fast|<pt/s>` the velocity (default slow). One launch and one drag per entry; each prints
/// `MIXV <os> <preferred|forced> pan=<mode> <variant>: page=<pt> v=<variant> n=<gesture callbacks> cx=<carousel x> in=<S|-V|-H|-> out=<...>` (grep the full log): `page` = how far the
/// page scrolled, `n` = how many times the variant's SwiftUI gesture reported, `in` / `out` = the `.scrollView(axis:)` coordinate spaces seen inside / outside the page.
/// Env: `ZS_APP_IDS=bundle,bundle` runs every entry against other installed copies of the demo (e.g. one whose Mach-O `LC_BUILD_VERSION` sdk was patched with `vtool`),
/// `ZS_PROBE=1` also makes the app log the touch's recognizers, the page's pan states (KVO + call stacks) to `$ZS_PROBE_DIR/probe-<tag>.log` (`MixedUIKitProbe`).
final class MixedProbeUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var forced: Bool { env["ZS_DEMO_FORCED"] == "1" }
    private var mode: String? { env["ZS_PAN_MODE"].flatMap { $0.isEmpty ? nil : $0 } }
    private var probeDir: String? { env["ZS_PROBE"] == "1" ? (env["ZS_PROBE_DIR"] ?? NSTemporaryDirectory()) : nil }
    private var variants: [String] { (env["ZS_VARIANTS"] ?? "").split(separator: ",").map(String.init) }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(variants.isEmpty, "measurement harness: set ZS_VARIANTS (see the header)")
    }

    private func velocity(_ name: String?) -> XCUIGestureVelocity {
        switch name ?? "" {
        case "fast": return .fast
        case "default": return .default
        case let n where Double(n) != nil: return XCUIGestureVelocity(rawValue: CGFloat(Double(n)!))
        default: return .slow
        }
    }

    private func readout(_ app: XCUIApplication) -> String {
        for _ in 0..<3 {
            app.buttons["Info"].tap()
            Thread.sleep(forTimeInterval: 0.4)
            if let s = app.staticTexts["mixedInfo"].value as? String, !s.isEmpty { return s }
        }
        return "?"
    }

    func testPageScrollPerVariant() {
        let os = UIDevice.current.systemVersion
        let appIds = (env["ZS_APP_IDS"] ?? "").split(separator: ",").map(String.init)
        for (appId, spec) in (appIds.isEmpty ? [""] : appIds).flatMap({ a in variants.map { (a, $0) } }) {
            let parts = spec.split(separator: "~", maxSplits: 1).map(String.init)
            let vecParts = parts[0].split(separator: "^", maxSplits: 1).map(String.init)
            let v = vecParts[0], vel = parts.count > 1 ? parts[1] : nil
            let c = vecParts.count > 1 ? vecParts[1].split(separator: "x").compactMap { Double($0) } : []
            let vec = c.count == 2 ? CGVector(dx: c[0], dy: c[1]) : CGVector(dx: 0, dy: -60)
            let appName = appId.split(separator: ".").last.map(String.init)
            let tag = ["\(os)", v, forced ? "f" : "p", mode ?? "def", vecParts.count > 1 ? "v" + vecParts[1] : nil, vel, appName.flatMap { appId.isEmpty ? nil : $0 }]
                .compactMap { $0 }.joined(separator: "-")
            let label = "\(appName.flatMap { appId.isEmpty ? nil : $0 + " " } ?? "")\(forced ? "forced" : "preferred") pan=\(mode ?? "default") \(v)"
                + "\(vecParts.count > 1 ? "^" + vecParts[1] : "")\(vel.map { "~" + $0 } ?? "")"
            if let dir = probeDir { try? FileManager.default.removeItem(atPath: "\(dir)/probe-\(tag).log") }
            let app = appId.isEmpty ? XCUIApplication() : XCUIApplication(bundleIdentifier: appId)
            app.launchArguments = ["-ZTronScreen", "mixedProbe", "-ZTronMixedVariant", v] + (forced ? ["-ZTronForceAllFallbacks"] : [])
                + (mode.map { ["-ZTronPanGestureMode", $0] } ?? [])
                + (probeDir.map { ["-ZTronProbe", tag, "-ZTronProbeDir", $0] } ?? [])
            app.launch()
            let target = app.descendants(matching: .any)["mixed.carousel"].firstMatch
            guard target.waitForExistence(timeout: 8) else { print("MIXV \(os) \(label): target missing"); app.terminate(); continue }
            let before = target.frame.minY
            let a = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            a.press(forDuration: 0.05, thenDragTo: a.withOffset(vec), withVelocity: velocity(vel), thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 1.0)
            let page = Int((before - target.frame.minY).rounded())
            print("MIXV \(os) \(label): page=\(page) \(readout(app))")
            app.terminate()
        }
    }
}
