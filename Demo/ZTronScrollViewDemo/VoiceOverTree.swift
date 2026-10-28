import UIKit

/// What VoiceOver can reach (the demo's own check, UIKit is fine here): the accessibility identifiers of the elements
/// in the key window's accessibility tree, walked as an assistive technology does (`accessibilityElements`, else
/// `accessibilityElementCount` / `accessibilityElement(at:)`, else the subviews; hidden subtrees skipped). XCUITest
/// also lists elements an app hides from VoiceOver (SwiftUI's `accessibilityHidden` keeps them for automation), so a UI
/// test reads this instead to tell whether an element is exposed to VoiceOver.
enum VoiceOverTree {
    /// SwiftUI's elements answer `accessibilityIdentifier` without declaring `UIAccessibilityIdentification`.
    @MainActor static func identifier(_ o: NSObject) -> String? {
        if let v = o as? UIAccessibilityIdentification { return v.accessibilityIdentifier }
        guard o.responds(to: NSSelectorFromString("accessibilityIdentifier")) else { return nil }
        return o.value(forKey: "accessibilityIdentifier") as? String
    }

    @MainActor static func identifiers(prefix: String) -> [String] {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        var out: [String] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ o: NSObject, _ depth: Int) {
            guard depth < 80, seen.insert(ObjectIdentifier(o)).inserted, !o.accessibilityElementsHidden else { return }
            if let v = o as? UIView, v.isHidden || v.alpha < 0.01 { return }
            if o.isAccessibilityElement {
                if let id = identifier(o), id.hasPrefix(prefix) { out.append(id) }
                return
            }
            if let els = o.accessibilityElements as? [NSObject] {
                els.forEach { visit($0, depth + 1) }
                return
            }
            let n = o.accessibilityElementCount()
            if n != NSNotFound, n > 0 {
                for i in 0..<n { if let e = o.accessibilityElement(at: i) as? NSObject { visit(e, depth + 1) } }
                return
            }
            (o as? UIView)?.subviews.forEach { visit($0, depth + 1) }
        }
        windows.filter(\.isKeyWindow).forEach { visit($0, 0) }
        return out
    }
}
