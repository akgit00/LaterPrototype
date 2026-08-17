import Foundation
import UserNotifications

/// Decides how push notifications are presented while the app is in the
/// foreground, and routes taps on notifications to the right screen. Banners
/// are shown for everything except the conversation or memory the user is
/// currently looking at (those already update live).
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()

    /// Thread id (conversation or memory) currently on screen; foreground
    /// banners whose `threadId` matches are suppressed, and anything already
    /// sitting in Notification Center for that thread is removed.
    var activeThreadID: String? {
        didSet {
            if let activeThreadID {
                Self.clearDelivered(threadID: activeThreadID)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let threadID = Self.threadID(of: notification.request.content)
        let shouldSuppress = await MainActor.run {
            guard let threadID, let active = NotificationCenterDelegate.shared.activeThreadID else {
                return false
            }
            return threadID.caseInsensitiveCompare(active) == .orderedSame
        }
        return shouldSuppress ? [] : [.banner, .list, .sound, .badge]
    }

    /// Handles the user tapping a notification: hands its thread to the app
    /// so the matching chat or memory opens, and clears any remaining
    /// notifications from the same thread.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        guard let threadID = Self.threadID(of: response.notification.request.content) else { return }
        Self.clearDelivered(threadID: threadID)
        await MainActor.run {
            NotificationRouter.shared.open(threadID: threadID)
        }
    }

    /// Removes every delivered notification belonging to the given thread from
    /// the user's Notification Center (e.g. once its chat or memory is opened).
    nonisolated static func clearDelivered(threadID: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            let ids = delivered
                .filter { note in
                    guard let thread = Self.threadID(of: note.request.content) else { return false }
                    return thread.caseInsensitiveCompare(threadID) == .orderedSame
                }
                .map { $0.request.identifier }
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    /// The thread id embedded in a push payload: the custom `threadId` key
    /// first, then the standard APNs `thread-id`.
    nonisolated private static func threadID(of content: UNNotificationContent) -> String? {
        if let custom = content.userInfo["threadId"] as? String, !custom.isEmpty {
            return custom
        }
        return content.threadIdentifier.isEmpty ? nil : content.threadIdentifier
    }
}
