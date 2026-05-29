import SwiftUI

@main
struct LaterPrototypeApp: App {
    @State private var authManager = AuthManager()
    @State private var profileManager = ProfileManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .environment(profileManager)
        }
    }
}
