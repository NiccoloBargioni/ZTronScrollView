import Testing
import Foundation
@testable import ZTronScrollView

/// The gate asks whether a text input is being edited (`TextEditingMonitor`): UIKit's public editing notifications, by name.
@MainActor @Suite struct TextEditingMonitorTests {
    private let field = Notification.Name("UITextFieldTextDidBeginEditingNotification")
    private let fieldEnd = Notification.Name("UITextFieldTextDidEndEditingNotification")
    private let view = Notification.Name("UITextViewTextDidBeginEditingNotification")
    private let viewEnd = Notification.Name("UITextViewTextDidEndEditingNotification")

    /// The monitor listens on the main queue: let it run.
    private func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    @Test func tracksTheTextFieldThatBeginsAndEnds() async {
        let center = NotificationCenter()
        let monitor = TextEditingMonitor(center: center)
        #expect(!monitor.isEditing)
        let a = NSObject()
        center.post(name: field, object: a); await settle()
        #expect(monitor.isEditing)
        center.post(name: fieldEnd, object: a); await settle()
        #expect(!monitor.isEditing)
    }

    @Test func textViewsCountAndEachSourceEndsOnItsOwn() async {
        let center = NotificationCenter()
        let monitor = TextEditingMonitor(center: center)
        let a = NSObject(), b = NSObject()
        center.post(name: field, object: a); center.post(name: view, object: b); await settle()
        center.post(name: fieldEnd, object: a); await settle()
        #expect(monitor.isEditing, "the text view is still edited")
        center.post(name: viewEnd, object: b); await settle()
        #expect(!monitor.isEditing)
    }

    @Test func aSourceThatGoesAwayWithoutItsEndNotificationCannotKeepTheFlagUp() async {
        let center = NotificationCenter()
        let monitor = TextEditingMonitor(center: center)
        var a: NSObject? = NSObject()
        center.post(name: field, object: a); await settle()
        #expect(monitor.isEditing)
        a = nil
        await settle()   // the posted notification and its autoreleased references are gone
        #expect(!monitor.isEditing)
    }

    @Test func otherNotificationsAreIgnored() async {
        let center = NotificationCenter()
        let monitor = TextEditingMonitor(center: center)
        center.post(name: Notification.Name("UITextFieldTextDidChangeNotification"), object: NSObject()); await settle()
        #expect(!monitor.isEditing)
    }
}
