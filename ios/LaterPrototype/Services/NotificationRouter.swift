import Foundation
import Observation

/// Hands the thread id of a tapped push notification from the notification
/// delegate to the SwiftUI layer, which opens the matching chat or memory
/// once the app's data is ready (including cold starts, where the tap
/// arrives before anything has loaded).
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    /// Thread id from the most recently tapped notification, waiting to be
    /// routed: a friend's user id for messages, a memory id for shares and
    /// comments. Cleared once the app navigates.
    var pendingThreadID: String?

    /// Set when a capsule-unlock notification is tapped, so the Capsules tab
    /// lands on its History segment (where the unlocked capsule now lives).
    /// Cleared by the tab once it switches.
    var showCapsuleHistory: Bool = false

    /// Set when a year-wrap unlock notification is tapped, so the Collections
    /// tab opens that year's Wrapped story. Cleared once it opens.
    var pendingWrapYear: Int?

    private init() {}

    func open(threadID: String) {
        pendingThreadID = threadID.lowercased()
    }
}
