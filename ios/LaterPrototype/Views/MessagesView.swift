import SwiftUI

/// A dedicated conversations tab — every connection with the newest chat
/// activity first, so messages are one tap away instead of buried in Profile.
struct MessagesView: View {
    let viewModel: LaterViewModel
    /// Opens people search so the user can find someone to message.
    let onFindFriends: () -> Void

    @State private var chatFriend: Connection?

    /// Connections ordered by most recent message, then alphabetically for
    /// friends with no conversation yet.
    private var orderedConnections: [Connection] {
        viewModel.allConnections.sorted { lhs, rhs in
            let lhsDate = viewModel.conversationPreviews[lhs.id]?.date
            let rhsDate = viewModel.conversationPreviews[rhs.id]?.date
            switch (lhsDate, rhsDate) {
            case let (.some(left), .some(right)):
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.allConnections.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onFindFriends()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Find people")
                }
            }
            .task {
                await viewModel.loadUnreadCounts()
            }
            .sheet(item: $chatFriend) { friend in
                ChatView(viewModel: viewModel, friend: friend)
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(orderedConnections) { connection in
                conversationRow(connection)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadConnections()
            await viewModel.loadUnreadCounts()
        }
    }

    private func conversationRow(_ connection: Connection) -> some View {
        let preview = viewModel.conversationPreviews[connection.id]
        let unread = viewModel.unreadByFriend[connection.id] ?? 0

        return Button {
            viewModel.markConversationRead(with: connection)
            chatFriend = connection
        } label: {
            HStack(spacing: 12) {
                ConnectionAvatarView(connection: connection, size: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let preview {
                        Text(preview.isMine ? "You: \(preview.body)" : preview.body)
                            .font(.footnote)
                            .fontWeight(unread > 0 ? .medium : .regular)
                            .foregroundStyle(unread > 0 ? .primary : .secondary)
                            .lineLimit(1)
                    } else {
                        Text("Say hi to @\(connection.username)")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    if let preview {
                        Text(timeLabel(preview.date))
                            .font(.caption2)
                            .foregroundStyle(unread > 0 ? Color.blue : Color(.tertiaryLabel))
                    }

                    if unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.blue, in: .capsule)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)

            Text("No conversations yet")
                .font(.headline)

            Text("Connect with friends to start\nsharing messages and memories.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onFindFriends()
            } label: {
                Label("Find Friends", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(.capsule)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Compact timestamp: time today, "Yesterday", weekday within a week,
    /// otherwise month + day.
    private func timeLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        if days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
