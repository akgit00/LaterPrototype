import SwiftUI

/// The Search tab: find people on Later by name or @username, open their
/// profile, and decide whether to send a friend request.
struct UserSearchView: View {
    let viewModel: LaterViewModel

    @State private var query: String = ""
    @State private var results: [CloudProfile] = []
    @State private var isSearching: Bool = false
    @State private var hasSearched: Bool = false
    @State private var searchError: String?
    @State private var selectedUser: Connection?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.top, 4)
            }
            .navigationTitle("Search")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Name or @username"
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .task(id: query) {
                await runSearch()
            }
            .sheet(item: $selectedUser) { user in
                FriendProfileView(connection: user, viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            idleState
        } else if isSearching && results.isEmpty && !hasSearched {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if let searchError {
            errorState(searchError)
        } else if results.isEmpty && hasSearched {
            emptyState
        } else {
            ForEach(results) { profile in
                if let connection = connection(for: profile) {
                    resultRow(connection: connection)
                }
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Find people on Later")
                .font(.headline)
            Text("Search by name or @username to see someone's profile and send them a friend request.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No one found")
                .font(.headline)
            Text("Try a different name or check the spelling of the @username.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Search didn't work")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func resultRow(connection: Connection) -> some View {
        Button {
            selectedUser = connection
        } label: {
            HStack(spacing: 12) {
                ConnectionAvatarView(connection: connection, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("@\(connection.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusChip(for: connection)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusChip(for connection: Connection) -> some View {
        switch viewModel.relationship(with: connection.id) {
        case .friend:
            chip("Friends", tint: .green)
        case .outgoingRequest:
            chip("Requested", tint: .secondary)
        case .incomingRequest:
            chip("Requests You", tint: .blue)
        case .notConnected:
            EmptyView()
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: .capsule)
    }

    private func connection(for profile: CloudProfile) -> Connection? {
        guard let uuid = UUID(uuidString: profile.id) else { return nil }
        let name = profile.display_name?.isEmpty == false ? profile.display_name! : profile.username
        return Connection(
            id: uuid,
            username: profile.username,
            displayName: name,
            avatarColor: LaterViewModel.avatarColor(for: profile.id),
            avatarURL: profile.avatar_url
        )
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            searchError = nil
            return
        }
        // Debounce typing: the task restarts on every keystroke.
        try? await Task.sleep(for: .milliseconds(350))
        if Task.isCancelled { return }

        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await ConnectionService.searchProfiles(matching: trimmed)
            if Task.isCancelled { return }
            results = found.filter { $0.id != viewModel.currentUserID }
            hasSearched = true
            searchError = nil
        } catch {
            if Task.isCancelled { return }
            searchError = error.localizedDescription
            hasSearched = true
        }
    }
}
