import SwiftUI

/// A 1:1 conversation between the signed-in user and a connected friend.
struct ChatView: View {
    let viewModel: LaterViewModel
    let friend: Connection
    @Environment(\.dismiss) private var dismiss

    @State private var messages: [LaterViewModel.ChatBubble] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var showProfile = false
    @FocusState private var inputFocused: Bool

    /// The most recent of my messages the friend has read — the one that
    /// shows the "Read" receipt.
    private var lastReadMineID: UUID? {
        messages.last(where: { $0.isMine && $0.readAt != nil })?.id
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                composer
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                // Tapping the friend's picture or name opens their profile.
                ToolbarItem(placement: .principal) {
                    Button {
                        showProfile = true
                    } label: {
                        HStack(spacing: 8) {
                            ConnectionAvatarView(connection: friend, size: 30)
                            Text(friend.displayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showProfile = true
                        } label: {
                            Label("View Profile", systemImage: "person.crop.circle")
                        }
                        Toggle(isOn: $bindableViewModel.readReceiptsEnabled) {
                            Label("Send Read Receipts", systemImage: "checkmark.message")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showProfile) {
                FriendProfileView(connection: friend, viewModel: viewModel, showsMessageButton: false)
            }
        }
        .task { await load() }
        // Keep the conversation live: poll for new messages every couple of
        // seconds while the chat is open so the other person's replies appear
        // without pulling to refresh.
        .task(id: friend.id) { await pollLoop() }
        // While this chat is on screen its messages never count as unread, so
        // the message notification clears the moment the conversation opens.
        .onAppear { viewModel.activeChatFriendID = friend.id }
        .onDisappear {
            if viewModel.activeChatFriendID == friend.id {
                viewModel.activeChatFriendID = nil
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if isLoading {
                        ProgressView()
                            .padding(.top, 40)
                    } else if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            VStack(spacing: 10) {
                                if showsDayHeader(at: index) {
                                    dayHeader(for: message.date)
                                }
                                bubble(
                                    message,
                                    showsTime: showsTime(at: index),
                                    isLastReadMine: message.id == lastReadMineID
                                )
                            }
                            .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ConnectionAvatarView(connection: friend, size: 64)
            Text("Say hi to \(friend.displayName)")
                .font(.headline)
            Text("This is the beginning of your conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func bubble(_ message: LaterViewModel.ChatBubble, showsTime: Bool, isLastReadMine: Bool) -> some View {
        HStack {
            if message.isMine { Spacer(minLength: 48) }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 3) {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(message.isMine ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isMine ? AnyShapeStyle(Color.blue) : AnyShapeStyle(Color(.secondarySystemBackground)),
                        in: .rect(cornerRadius: 18)
                    )
                if showsTime {
                    Text(message.date, format: .dateTime.hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
                if isLastReadMine {
                    Text("Read")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }
            if !message.isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
    }

    private func dayHeader(for date: Date) -> some View {
        Text(dayLabel(for: date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemBackground), in: .capsule)
            .padding(.top, 6)
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// A day header shows before the first message of each calendar day.
    private func showsDayHeader(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index - 1].date, inSameDayAs: messages[index].date)
    }

    /// The time label shows on the last message of a sender's burst, or when
    /// more than a few minutes separate two messages.
    private func showsTime(at index: Int) -> Bool {
        guard index + 1 < messages.count else { return true }
        let current = messages[index]
        let next = messages[index + 1]
        if current.isMine != next.isMine { return true }
        return next.date.timeIntervalSince(current.date) > 300
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: .capsule)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? .blue : .secondary)
            }
            .disabled(!canSend || isSending)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() async {
        isLoading = true
        messages = await viewModel.loadConversation(with: friend)
        isLoading = false
        viewModel.markConversationRead(with: friend)
    }

    /// Repeatedly pulls the conversation so incoming messages show up almost
    /// instantly. New rows are merged in by id, so an in-flight send is never
    /// lost and existing bubbles don't flicker.
    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { break }
            let latest = await viewModel.loadConversation(with: friend)
            guard !latest.isEmpty else { continue }
            var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
            for message in latest { byID[message.id] = message }
            let merged = byID.values.sorted { $0.date < $1.date }
            // Refresh when messages arrive OR when read receipts change.
            if merged.map(\.id) != messages.map(\.id) || merged.map(\.readAt) != messages.map(\.readAt) {
                messages = merged
                // The chat is open and on-screen, so anything that just arrived
                // is effectively read — keep its badge from reappearing.
                viewModel.markConversationRead(with: friend)
            }
        }
    }

    private func send() async {
        guard canSend, !isSending else { return }
        let body = draft
        isSending = true
        defer { isSending = false }
        draft = ""
        if let bubble = await viewModel.sendMessage(to: friend, body: body) {
            messages.append(bubble)
        } else {
            draft = body
        }
    }
}
