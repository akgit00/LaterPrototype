import SwiftUI
import UserNotifications

@main
struct LaterPrototypeApp: App {
    @State private var authManager = AuthManager()
    @State private var profileManager = ProfileManager()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .environment(profileManager)
        }
    }
}

/// Handles APNs (push notification) registration callbacks that can't be done
/// from a pure SwiftUI app lifecycle.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Present foreground banners (except for the chat currently open).
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
        // Kick off permission request early so the system prompt can appear
        // as soon as the user is signed in.
        PushNotificationService.shared.requestPermissionIfNeeded()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.didFailToRegisterForRemoteNotifications(withError: error)
        }
    }
}
