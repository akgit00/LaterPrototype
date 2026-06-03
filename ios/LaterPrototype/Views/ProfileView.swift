import SwiftUI
import CoreLocation

struct ProfileView: View {
    let viewModel: LaterViewModel
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileManager.self) private var profile
    @State private var selectedSegment: ProfileSegment = .timeline
    @State private var showSignOutConfirm = false
    @State private var showEditProfile = false
    @State private var selectedMemoryID: UUID?

    private static let defaultBio = "Collecting moments across time & space"

    /// The account's default name, derived from auth, used when no override is set.
    private var accountName: String {
        if let name = auth.user?.name, !name.isEmpty { return name }
        if let email = auth.user?.email, !email.isEmpty {
            return String(email.prefix(while: { $0 != "@" }))
        }
        return "You"
    }

    private var displayName: String {
        profile.displayNameOverride ?? accountName
    }

    private var bio: String {
        profile.bioOverride ?? Self.defaultBio
    }

    private var avatarURL: String? {
        profile.avatarLocalURL ?? auth.user?.picture
    }

    private var initial: String {
        String(displayName.prefix(1)).uppercased()
    }

    enum ProfileSegment: String, CaseIterable {
        case timeline = "Timeline"
        case connections = "Connections"
        case legacy = "Legacy"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                        .padding(.bottom, 20)

                    statsRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)

                    Picker("Section", selection: $selectedSegment) {
                        ForEach(ProfileSegment.allCases, id: \.self) { segment in
                            Text(segment.rawValue).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    switch selectedSegment {
                    case .timeline:
                        timelineContent
                    case .connections:
                        connectionsContent
                    case .legacy:
                        legacyContent
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEditProfile = true
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showSignOutConfirm = true
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("Sign out of Later?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    profile.clear()
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(
                    profile: profile,
                    initialName: profile.displayNameOverride ?? accountName,
                    initialBio: profile.bioOverride ?? Self.defaultBio,
                    fallbackInitial: initial,
                    authPicture: auth.user?.picture
                )
            }
            .fullScreenCover(item: $selectedMemoryID) { memoryID in
                MemoryRoomView(memoryID: memoryID, viewModel: viewModel)
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)

                if let picture = avatarURL, let url = URL(string: picture) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Text(initial)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(.circle)
                } else {
                    Text(initial)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title2.weight(.bold))

                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if let email = auth.user?.email, !email.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.caption2)
                        Text(email)
                            .font(.caption)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                }
            }

            Button {
                showEditProfile = true
            } label: {
                Label("Edit Profile", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.bordered)
            .clipShape(.capsule)
            .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    private var cityCount: Int {
        Set(viewModel.memories.map { "\(Int($0.centerCoordinate.latitude)),\(Int($0.centerCoordinate.longitude))" }).count
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: "\(viewModel.memories.count)", label: "Memories")
            Divider().frame(height: 32)
            statItem(value: "12", label: "Capsules")
            Divider().frame(height: 32)
            statItem(value: "\(viewModel.allConnections.count)", label: "Connections")
            Divider().frame(height: 32)
            statItem(value: "\(cityCount)", label: "Cities")
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var timelineContent: some View {
        VStack(spacing: 12) {
            if viewModel.memories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No memories yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(viewModel.memories) { memory in
                    Button {
                        selectedMemoryID = memory.id
                    } label: {
                        HStack(spacing: 12) {
                            Text(shortDate(memory.date))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)

                            Circle()
                                .fill(.blue)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(memory.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(memory.connections.count) friends, \(memory.photoURLs.count) photos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 32)
    }

    private var connectionsContent: some View {
        VStack(spacing: 12) {
            if viewModel.allConnections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No connections yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(viewModel.allConnections) { connection in
                    let sharedCount = viewModel.memories.filter { $0.connections.contains(where: { $0.id == connection.id }) }.count

                    HStack(spacing: 12) {
                        ConnectionAvatarView(connection: connection, size: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text("\(sharedCount) shared memor\(sharedCount == 1 ? "y" : "ies")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "message.fill")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 32)
    }

    private var legacyContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.purple)

            Text("Your Digital Legacy")
                .font(.title3.weight(.bold))

            Text("Your public profile showcases your shared memories and connections. This is how friends and future connections will remember you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
            } label: {
                Text("Customize Legacy")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(.vertical, 24)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
