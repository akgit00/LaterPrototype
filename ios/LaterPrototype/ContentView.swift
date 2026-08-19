import SwiftUI
import UserNotifications

struct ContentView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileManager.self) private var profile
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = LaterViewModel()
    @State private var selectedTab: Int = 0

    /// Notification-tap routing: the pending thread comes from the router and
    /// resolves to a chat or a memory once data is loaded.
    @State private var router = NotificationRouter.shared
    @State private var routedChatFriend: Connection?
    @State private var routedMemoryID: UUID?
    @State private var hasCompletedInitialSync = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Explore", systemImage: "globe", value: 0) {
                WorldMapView(viewModel: viewModel)
            }

            Tab("Search", systemImage: "magnifyingglass", value: 1) {
                UserSearchView(viewModel: viewModel)
            }

            Tab("Capsules", systemImage: "envelope.badge.shield.half.filled", value: 2) {
                TimeCapsuleView(viewModel: viewModel)
            }

            Tab("Profile", systemImage: "person.crop.circle", value: 3) {
                ProfileView(viewModel: viewModel)
            }
            .badge(viewModel.totalUnread)
        }
        .tint(.blue)
        .task(id: auth.user?.id) {
            guard let user = auth.user else { return }
            viewModel.configure(userID: user.id, email: user.email, displayName: user.name)
            await profile.configure(userID: user.id)
            await PushNotificationService.shared.syncToken(for: user.id)
            await viewModel.sync()
            // Data is ready — resolve any notification tapped before/at launch.
            hasCompletedInitialSync = true
            routePendingNotification()
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
                if router.pendingThreadID != nil {
                    routePendingNotification()
                }
            }
        }
        // Refresh immediately when the app returns to the foreground.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, auth.user != nil else { return }
            // Re-check notification permission and retry the token sync in case
            // the user changed settings or a previous attempt failed.
            PushNotificationService.shared.refreshAndResync()
            // The app shows all current state once open, so the icon badge is
            // stale by definition.
            UNUserNotificationCenter.current().setBadgeCount(0)
            Task { await viewModel.refresh() }
        }
        // Route notification taps to their source: the chat for a message,
        // the memory room for shares and comments.
        .onChange(of: router.pendingThreadID) { _, _ in
            routePendingNotification()
        }
        .sheet(item: $routedChatFriend) { friend in
            ChatView(viewModel: viewModel, friend: friend)
        }
        .fullScreenCover(item: $routedMemoryID) { memoryID in
            MemoryRoomView(memoryID: memoryID, viewModel: viewModel)
        }
    }

    /// Opens the source of a tapped notification once the data backing it has
    /// loaded: a friend's chat for messages, the memory room for shares and
    /// comments, or the Profile tab (requests + conversations) as a fallback.
    private func routePendingNotification() {
        guard let threadID = router.pendingThreadID else { return }

        // Capsule-unlock pushes carry the "capsules" thread and route straight
        // to the Capsules tab, which refreshes itself on appear.
        if threadID == "capsules" {
            router.pendingThreadID = nil
            routedChatFriend = nil
            routedMemoryID = nil
            router.showCapsuleHistory = true
            selectedTab = 2
            return
        }

        if let uuid = UUID(uuidString: threadID) {
            if let friend = viewModel.allConnections.first(where: { $0.id == uuid }) {
                router.pendingThreadID = nil
                routedMemoryID = nil
                routedChatFriend = friend
                return
            }
            if viewModel.memoryByID(uuid) != nil {
                router.pendingThreadID = nil
                routedChatFriend = nil
                routedMemoryID = uuid
                return
            }
        }

        // Unknown thread (e.g. a friend request from someone not yet in the
        // friends list): fall back to the Profile tab, where requests and
        // conversations live — but only once the first sync has finished, so
        // a cold start still gets a chance to resolve the real target.
        if hasCompletedInitialSync {
            router.pendingThreadID = nil
            selectedTab = 3
        }
    }
}
