import SwiftUI
import CoreLocation

/// Another person's profile: who they are, your relationship with them, and
/// the memories you share. Opened from the friends list, chat headers, and
/// search results.
struct FriendProfileView: View {
    let connection: Connection
    let viewModel: LaterViewModel
    /// Hidden when this profile is opened from inside a chat with the person.
    var showsMessageButton: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var cloudProfile: CloudProfile?
    @State private var chatFriend: Connection?
    @State private var selectedMemoryID: UUID?
    @State private var showRemoveConfirm: Bool = false
    @State private var actionFeedback: String?
    @State private var isWorking: Bool = false

    private var displayName: String {
        if let name = cloudProfile?.display_name, !name.isEmpty { return name }
        return connection.displayName
    }

    private var username: String {
        cloudProfile?.username ?? connection.username
    }

    /// The connection enriched with the freshest cloud name and avatar.
    private var displayConnection: Connection {
        Connection(
            id: connection.id,
            username: username,
            displayName: displayName,
            avatarColor: connection.avatarColor,
            avatarURL: cloudProfile?.avatar_url ?? connection.avatarURL
        )
    }

    private var sharedMemories: [Memory] {
        viewModel.memoriesInvolving(connection.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    actionArea
                    statsRow
                    sharedMemoriesSection
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if case .friend = viewModel.relationship(with: connection.id) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showRemoveConfirm = true
                            } label: {
                                Label("Remove Friend", systemImage: "person.badge.minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Remove \(displayName) as a friend?",
                isPresented: $showRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove Friend", role: .destructive) {
                    Task {
                        await viewModel.removeFriend(connection)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $chatFriend) { friend in
                ChatView(viewModel: viewModel, friend: friend)
            }
            .fullScreenCover(item: $selectedMemoryID) { memoryID in
                MemoryRoomView(memoryID: memoryID, viewModel: viewModel)
            }
            .task {
                cloudProfile = (try? await CloudMemoryService.fetchProfile(id: connection.id.uuidString)) ?? nil
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ConnectionAvatarView(connection: displayConnection, size: 96)
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.weight(.bold))
                Text("@\(username)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                if let bio = cloudProfile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var actionArea: some View {
        VStack(spacing: 10) {
            switch viewModel.relationship(with: connection.id) {
            case .friend:
                if showsMessageButton {
                    Button {
                        viewModel.markConversationRead(with: connection)
                        chatFriend = displayConnection
                    } label: {
                        Label("Message", systemImage: "message.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(.capsule)
                } else {
                    Label("Friends", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }

            case .incomingRequest(let request):
                VStack(spacing: 8) {
                    Text("\(displayName) sent you a friend request")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                isWorking = true
                                await viewModel.acceptRequest(request)
                                isWorking = false
                            }
                        } label: {
                            Label("Accept", systemImage: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .clipShape(.capsule)

                        Button {
                            Task {
                                isWorking = true
                                await viewModel.removeRequest(request)
                                isWorking = false
                            }
                        } label: {
                            Label("Decline", systemImage: "xmark")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .clipShape(.capsule)
                    }
                }
                .disabled(isWorking)

            case .outgoingRequest(let request):
                HStack(spacing: 10) {
                    Label("Request Sent", systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground), in: .capsule)

                    Button {
                        Task { await viewModel.removeRequest(request) }
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(.capsule)
                }

            case .notConnected:
                Button {
                    Task { await sendRequest() }
                } label: {
                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        }
                        Label("Add Friend", systemImage: "person.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(.capsule)
                .disabled(isWorking)
            }

            if let actionFeedback {
                Text(actionFeedback)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
    }

    private func sendRequest() async {
        isWorking = true
        defer { isWorking = false }
        actionFeedback = nil
        let result = await viewModel.sendConnectionRequest(identifier: username)
        switch result {
        case .sent:
            break
        case .alreadyConnected:
            actionFeedback = "You're already connected."
        case .requestPending:
            actionFeedback = "There's already a pending request."
        case .notFound:
            actionFeedback = "This account can't be found anymore."
        case .selfRequest:
            actionFeedback = "That's you!"
        case .failure(let message):
            actionFeedback = message
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(value: sharedMemories.count, label: "Shared")
            Divider().frame(height: 32)
            stat(value: sharedMemories.flatMap(\.photoURLs).count, label: "Photos")
            Divider().frame(height: 32)
            stat(value: sharedMemories.flatMap(\.videos).count, label: "Videos")
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sharedMemoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEMORIES TOGETHER")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            if sharedMemories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No shared memories yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(sharedMemories) { memory in
                        Button {
                            selectedMemoryID = memory.id
                        } label: {
                            memoryTile(memory)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func memoryTile(_ memory: Memory) -> some View {
        ZStack {
            if let firstPhoto = memory.photoURLs.first {
                Color(.secondarySystemBackground)
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        MediaImageView(urlString: firstPhoto)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .teal.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading) {
                Spacer()
                Text(memory.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(memory.date, format: .dateTime.month(.abbreviated).year())
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }
}
