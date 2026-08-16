import Foundation
import UserNotifications

/// Decides how push notifications are presented while the app is in the
/// foreground. Banners are shown for everything except the conversation the
/// user is currently looking at (that chat already updates live).
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCenterDelegate()

    /// Thread id (conversation or memory) currently on screen; foreground
    /// banners whose `threadId` matches are suppressed.
    var activeThreadID: String?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let threadID = notification.request.content.userInfo["threadId"] as? String
        let shouldSuppress = await MainActor.run {
            guard let threadID, let active = NotificationCenterDelegate.shared.activeThreadID else {
                return false
            }
            return threadID.caseInsensitiveCompare(active) == .orderedSame
        }
        return shouldSuppress ? [] : [.banner, .list, .sound, .badge]
    }
}
