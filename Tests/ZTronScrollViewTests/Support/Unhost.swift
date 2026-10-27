import Testing
import UIKit

/// Tears a test window down: hidden, no root controller. A window that holds a `UIScrollView` is retired instead
/// (``ScrollViewWindows``): the same, but the window and its scroll views stay allocated.
@MainActor
func unhost(_ window: UIWindow?) {
    guard let window else { return }
    if !ScrollViewWindows.retire(window) {
        window.isHidden = true
        window.rootViewController = nil
    }
}

/// Keeps every test window that holds a `UIScrollView` (a native SwiftUI `ScrollView`, `List`, …) and those scroll
/// views allocated until the process exits, on iOS 26+ (DBG-s9).
///
/// iOS 26+ UIKit counts Observation-tracking invalidations per object address and clears the counts after a
/// CATransaction commit through `UIApplication.shared`, which is nil in this app-less test process, so they never
/// clear. A `UIScrollView` registering with its window's scroll-pocket collector costs the window 2 counted invalidations
/// and itself 1, and each test's window reuses the address of the previous one: after ~20 such windows at one address,
/// every later window there printed "Observation tracking feedback loop detected" (threshold 40), even a `Color.clear`
/// one. Kept objects never free their address; windows without a `UIScrollView` record no counted invalidation.
///
/// A kept window is retired (hidden, root controller dropped, so its content stops rendering) by `unhost` or by the
/// first `host()` of a later test: every test that hosts a `UIScrollView` is synchronous, so it has finished by then.
@MainActor
enum ScrollViewWindows {
    /// Only UIKit with Observation tracking counts invalidations.
    nonisolated static var isNeeded: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    private static var kept: [AnyObject] = []
    /// Kept windows that may still show their test's content, with the test that hosted them.
    private static var live: [(window: UIWindow, test: Test.ID?)] = []

    /// Keeps `window` if its hierarchy holds a `UIScrollView` (iOS 26+); returns whether it is kept.
    @discardableResult
    static func keepIfScrolling(_ window: UIWindow) -> Bool {
        guard isNeeded else { return false }
        if isKept(window) { return true }
        let scrollViews = allScrollViews(in: window)
        guard !scrollViews.isEmpty else { return false }
        kept.append(window)
        kept.append(contentsOf: scrollViews as [AnyObject])
        live.append((window, Test.current?.id))
        return true
    }

    static func isKept(_ object: AnyObject) -> Bool { kept.contains { $0 === object } }

    /// Retires the live windows of every test but the running one.
    static func retireFinished(running: Test.ID? = Test.current?.id) {
        for entry in live where entry.test != running { retire(entry.window) }
    }

    /// Hides a kept window and drops its root controller, keeping it and its scroll views allocated; returns whether
    /// `window` is kept.
    @discardableResult
    static func retire(_ window: UIWindow) -> Bool {
        guard keepIfScrolling(window) else { return false }
        for view in allScrollViews(in: window) where !isKept(view) { kept.append(view) }
        live.removeAll { $0.window === window }
        window.isHidden = true
        window.rootViewController = nil
        return true
    }

    private static func allScrollViews(in view: UIView) -> [UIScrollView] {
        var found = view.subviews.flatMap(allScrollViews(in:))
        if let scrollView = view as? UIScrollView { found.insert(scrollView, at: 0) }
        return found
    }
}
