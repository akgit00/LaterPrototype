import Foundation
import UserNotifications
import UIKit

/// Manages push notification permission, device token registration, and syncing
/// the token to Supabase so the server can send targeted notifications (new
/// comments, shares, messages, friend requests).
@Observable
@MainActor
final class PushNotificationService {
    static let shared = PushNotificationService()

    /// Whether the user has granted notification permission.
    private(set) var isAuthorized: Bool = false
    /// The hex-encoded APNs device token, available after a successful register.
    private(set) var deviceToken: String?

    private let tokenKey = "apns_device_token"
    private let userIDKey = "apns_token_user_id"

    private init() {}

    // MARK: - Permission

    /// Requests notification permission if not already granted. Safe to call on
    /// every app launch — iOS returns immediately if the user already decided.
    func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .notDetermined:
                    self.requestAuthorization()
                case .authorized, .provisional, .ephemeral:
                    self.isAuthorized = true
                    self.registerForRemoteNotifications()
                case .denied:
                    self.isAuthorized = false
                @unknown default:
                    break
                }
            }
        }
    }

    private func requestAuthorization() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                isAuthorized = granted
                if granted {
                    registerForRemoteNotifications()
                }
            } catch {
                isAuthorized = false
            }
        }
    }

    // MARK: - Token registration

    /// Registers for remote notifications. Called automatically after permission
    /// is granted; also called from the app delegate on cold launch.
    func registerForRemoteNotifications() {
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Called by the app delegate when APNs returns a device token.
    func didRegisterForRemoteNotifications(withDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        UserDefaults.standard.set(hex, forKey: tokenKey)
        // If we already know the signed-in user, sync the token immediately.
        if let userID = UserDefaults.standard.string(forKey: userIDKey) {
            Task { await syncToken(to: userID) }
        }
    }

    func didFailToRegisterForRemoteNotifications(withError error: Error) {
        // Non-fatal: the app still works without push; we'll retry on next launch.
    }

    // MARK: - Supabase sync

    /// Associates the APNs token with the signed-in user so the server can send
    /// them targeted push notifications. Safe to call multiple times — the server
    /// upserts the token row.
    func syncToken(for userID: String) async {
        UserDefaults.standard.set(userID, forKey: userIDKey)
        await syncToken(to: userID)
    }

    /// Clears the stored user association on sign-out (the token itself can
    /// stay; the server just won't send to it until the user signs in again).
    func clearUserAssociation() {
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }

    private func syncToken(to userID: String) async {
        guard let token = deviceToken ?? UserDefaults.standard.string(forKey: tokenKey) else { return }
        guard SupabaseREST.hasSession else { return }

        struct TokenUpsert: Encodable {
            let user_id: String
            let device_token: String
            let platform: String
            let updated_at: String
        }

        let row = TokenUpsert(
            user_id: userID,
            device_token: token,
            platform: "ios",
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        guard let body = try? SupabaseREST.makeEncoder().encode(row) else { return }
        do {
            try await SupabaseREST.request(
                path: "push_tokens",
                method: "POST",
                query: [URLQueryItem(name: "on_conflict", value: "user_id")],
                body: body,
                prefer: "resolution=merge-duplicates,return=minimal"
            )
        } catch {
            // Non-fatal: the table might not exist yet, or RLS may block it.
            // The app still works; we just can't send push notifications yet.
        }
    }
}
