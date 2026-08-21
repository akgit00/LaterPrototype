import Foundation
import UserNotifications
import Observation

/// Schedules a yearly local notification on each memory's anniversary.
/// Reminders are personal: they live on this device only, so anyone on a
/// shared memory can turn one on without affecting the others.
@Observable
final class AnniversaryReminderService {
    static let shared = AnniversaryReminderService()

    private(set) var enabledIDs: Set<UUID>

    private let storageKey = "anniversary_memory_ids"

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        enabledIDs = Set(stored.compactMap(UUID.init))
    }

    func isEnabled(_ memoryID: UUID) -> Bool {
        enabledIDs.contains(memoryID)
    }

    /// Turns the yearly reminder on/off for a memory. Returns false when
    /// notification permission was denied (the toggle should flip back).
    @discardableResult
    func setEnabled(_ enabled: Bool, for memory: Memory) async -> Bool {
        let center = UNUserNotificationCenter.current()

        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier(for: memory.id)])
            enabledIDs.remove(memory.id)
            persist()
            return true
        }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "On this day"
        let year = Calendar.current.component(.year, from: memory.date)
        content.body = "\"\(memory.title)\" happened on this day in \(year). Take a look back."
        content.sound = .default

        var components = Calendar.current.dateComponents([.month, .day], from: memory.date)
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: identifier(for: memory.id),
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
        } catch {
            return false
        }

        enabledIDs.insert(memory.id)
        persist()
        return true
    }

    /// The next time this memory's anniversary comes around.
    func nextOccurrence(for memory: Memory) -> Date? {
        var components = Calendar.current.dateComponents([.month, .day], from: memory.date)
        components.hour = 9
        return Calendar.current.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)
    }

    /// Clears a reminder when its memory is deleted.
    func removeReminder(for memoryID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: memoryID)])
        enabledIDs.remove(memoryID)
        persist()
    }

    private func identifier(for memoryID: UUID) -> String {
        "anniversary-\(memoryID.uuidString.lowercased())"
    }

    private func persist() {
        UserDefaults.standard.set(enabledIDs.map(\.uuidString), forKey: storageKey)
    }
}
