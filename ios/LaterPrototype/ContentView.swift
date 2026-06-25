import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileManager.self) private var profile
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = LaterViewModel()
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Explore", systemImage: "globe", value: 0) {
                WorldMapView(viewModel: viewModel)
            }

            Tab("Capsules", systemImage: "envelope.badge.shield.half.filled", value: 1) {
                TimeCapsuleView()
            }

            Tab("Profile", systemImage: "person.crop.circle", value: 2) {
                ProfileView(viewModel: viewModel)
            }
            .badge(viewModel.totalUnread)
        }
        .tint(.blue)
        .task(id: auth.user?.id) {
            guard let user = auth.user else { return }
            viewModel.configure(userID: user.id, email: user.email, displayName: user.name)
            await profile.configure(userID: user.id)
            await viewModel.sync()
        }
        // Periodically poll the cloud while the app is active so new comments,
        // friend requests and shared memories appear without a restart. Friend
        // requests are checked every few seconds (cheap) so they show up almost
        // instantly, while the heavier full pull runs less often.
        .task(id: auth.user?.id) {
            guard auth.user != nil else { return }
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                tick += 1
                await viewModel.loadUnreadCounts()
                if tick % 4 == 0 {
                    await viewModel.refresh()
                } else {
                    await viewModel.loadConnections()
                }
            }
        }
        // Refresh immediately when the app returns to the foreground.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, auth.user != nil else { return }
            Task { await viewModel.refresh() }
        }
    }
}
