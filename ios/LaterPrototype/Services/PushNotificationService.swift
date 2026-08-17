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

    /// Where notification setup currently stands. Drives the status card in
    /// the Profile tab so problems are visible instead of failing silently.
    enum SetupState: Equatable {
        case unknown
        /// iOS hasn't asked the user for permission yet.
        case needsPermission
        /// The user declined notifications; only iOS Settings can re-enable.
        case denied
        /// Permission granted; waiting for the device token or server sync.
        case registering
        /// This device is registered with the server — pushes should arrive.
        case active
        /// Something went wrong; the text is safe to show the user.
        case failed(String)
    }

    /// Whether the user has granted notification permission.
    private(set) var isAuthorized: Bool = false
    /// The hex-encoded APNs device token, available after a successful register.
    private(set) var deviceToken: String?
    /// Current progress of the permission → token → server-sync pipeline.
    private(set) var setupState: SetupState = .unknown

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
                    self.setupState = .needsPermission
                    self.requestAuthorization()
                case .authorized, .provisional, .ephemeral:
                    self.isAuthorized = true
                    if self.setupState != .active {
                        self.setupState = .registering
                    }
                    self.registerForRemoteNotifications()
                case .denied:
                    self.isAuthorized = false
                    self.setupState = .denied
                @unknown default:
                    break
                }
            }
        }
    }

    /// Re-checks permission, re-registers, and retries the server sync. Called
    /// when the app returns to the foreground so changes made in iOS Settings
    /// (or transient network failures) heal automatically.
    func refreshAndResync() {
        requestPermissionIfNeeded()
        if let userID = UserDefaults.standard.string(forKey: userIDKey) {
            Task { await syncToken(to: userID) }
        }
    }

    private func requestAuthorization() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
                isAuthorized = granted
                if granted {
                    setupState = .registering
                    registerForRemoteNotifications()
                } else {
                    setupState = .denied
                }
            } catch {
                isAuthorized = false
                setupState = .failed("Could not request permission: \(error.localizedDescription)")
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
        // Registration fails on simulators and when the build's provisioning
        // profile lacks the push capability. Surface it instead of hiding it.
        setupState = .failed("Device registration failed: \(error.localizedDescription)")
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
        guard let token = deviceToken ?? UserDefaults.standard.string(forKey: tokenKey) else {
            // No APNs token yet — ask iOS again; the delegate callback re-runs
            // this sync as soon as the token arrives.
            if isAuthorized {
                registerForRemoteNotifications()
            }
            return
        }
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
            setupState = .active
        } catch {
            setupState = .failed("Could not register this device: \(error.localizedDescription)")
        }
    }
}
