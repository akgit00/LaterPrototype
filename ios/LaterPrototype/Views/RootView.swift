import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        Group {
            if auth.isLoading {
                loadingView
            } else if auth.user != nil {
                ContentView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.user?.id)
        .animation(.easeInOut(duration: 0.35), value: auth.isLoading)
    }

    private var loadingView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ProgressView()
                .tint(.white)
        }
    }
}
