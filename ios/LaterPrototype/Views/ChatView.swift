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
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                composer
            }
            .navigationTitle(friend.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
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
                        ForEach(messages) { message in
                            bubble(message)
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

    private func bubble(_ message: LaterViewModel.ChatBubble) -> some View {
        HStack {
            if message.isMine { Spacer(minLength: 48) }
            Text(message.body)
                .font(.body)
                .foregroundStyle(message.isMine ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.isMine ? AnyShapeStyle(Color.blue) : AnyShapeStyle(Color(.secondarySystemBackground)),
                    in: .rect(cornerRadius: 18)
                )
            if !message.isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.isMine ? .trailing : .leading)
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
