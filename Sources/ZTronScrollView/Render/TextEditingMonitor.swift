import Foundation

/// Whether a text input holds the keyboard focus (SwiftUI's `TextField`, `SecureField` and `TextEditor` are `UITextField` /
/// `UITextView` underneath). The content gate reads it: `.disabled` on the content makes UIKit resign the focused field, so
/// while one is being edited the gate leaves the content enabled (``ContentGatePolicy``).
///
/// SwiftUI has no signal for it (no keyboard visibility, no focus of a view the app did not bind), so this listens to UIKit's
/// public editing notifications by name. The names are plain strings: the library imports no UIKit (SPEC S2) and reads no
/// UIKit symbol, view or object (`scripts/check-uikit-scope.sh` stays clean). Sources are held weakly, so a text input that
/// goes away without its end notification cannot keep the flag up.
@MainActor
final class TextEditingMonitor {
    /// Created with the first ``ZTronScrollState``, before any text input of the screen can be focused.
    static let shared = TextEditingMonitor()

    static let beginNames = ["UITextFieldTextDidBeginEditingNotification", "UITextViewTextDidBeginEditingNotification"]
    static let endNames = ["UITextFieldTextDidEndEditingNotification", "UITextViewTextDidEndEditingNotification"]

    /// The notification's object, handed to the main actor (the observers run on the main queue; the table never leaves it).
    private struct Source: @unchecked Sendable { let object: AnyObject }

    private let editors = NSHashTable<AnyObject>.weakObjects()
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        for name in Self.beginNames {
            tokens.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                guard let object = note.object as AnyObject? else { return }
                let source = Source(object: object)
                MainActor.assumeIsolated {
                    self?.editors.add(source.object)
                    #if DEBUG
                    ZTronRenderCounters.increment("editing.begin")
                    #endif
                }
            })
        }
        for name in Self.endNames {
            tokens.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                guard let object = note.object as AnyObject? else { return }
                let source = Source(object: object)
                MainActor.assumeIsolated {
                    self?.editors.remove(source.object)
                    #if DEBUG
                    ZTronRenderCounters.increment("editing.end")
                    #endif
                }
            })
        }
    }

    var isEditing: Bool { !editors.allObjects.isEmpty }
}
