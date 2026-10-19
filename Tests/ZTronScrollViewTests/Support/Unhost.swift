import UIKit

/// Tears a test window down: hidden, no root controller. The hosting-heavy suites of M6 end with it; a process full of
/// live windows makes UIKit print "Observation tracking feedback loop detected" on iOS 27 (warnings, not failures).
@MainActor
func unhost(_ window: UIWindow?) {
    window?.isHidden = true
    window?.rootViewController = nil
}
