import Foundation
import UserNotifications

/// Schedules the local "your year is wrapped" notification that fires on
/// Dec 31 at 9 AM. The schedule is rebuilt on every sync so the memory count
/// in the message stays fresh, and it is cancelled while the year holds no
/// memories (nothing to wrap). Wraps are computed on device, so a local
/// notification — not a server push — is the reliable delivery path.
enum YearWrapReminderService {
    private static let identifierPrefix = "year-wrap-"

    /// Thread id embedded in the notification so a tap routes to the
    /// Collections tab and opens that year's Wrapped story.
    static func threadID(for year: Int) -> String {
        "wrapped-\(year)"
    }

    /// Parses the wrap year back out of a notification thread id.
    static func year(fromThreadID threadID: String) -> Int? {
        guard threadID.hasPrefix("wrapped-") else { return nil }
        return Int(threadID.dropFirst("wrapped-".count))
    }

    /// (Re)schedules this year's unlock notification from the latest memory
    /// list. Safe to call often — the request identifier is per-year, so
    /// re-adding simply replaces the pending copy.
    static func refreshSchedule(memories: [Memory], now: Date = Date()) async {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let identifier = identifierPrefix + String(year)
        let center = UNUserNotificationCenter.current()

        let count = memories.count { calendar.component(.year, from: $0.date) == year }
        guard count > 0 else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let settings = await center.notificationSettings()
        let allowed: [UNAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
        guard allowed.contains(settings.authorizationStatus) else { return }

        var components = DateComponents()
        components.year = year
        components.month = 12
        components.day = 31
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        // Dec 31 morning already passed for this year — nothing left to schedule.
        guard trigger.nextTriggerDate() != nil else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        let yearText = String(year)
        let content = UNMutableNotificationContent()
        content.title = "Your \(yearText) Wrapped is here 🎁"
        content.body = count == 1
            ? "The memory you pinned this year is ready to relive. Come unwrap your year."
            : "\(count) memories wove \(yearText) together. Come unwrap your year."
        content.sound = .default
        content.threadIdentifier = threadID(for: year)
        content.userInfo = ["threadId": threadID(for: year)]

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Removes every pending wrap notification (used when the signed-in
    /// account changes, so one user's wrap never fires for another).
    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
            if !ids.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }
}
