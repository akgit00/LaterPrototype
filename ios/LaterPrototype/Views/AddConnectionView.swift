import SwiftUI

/// A sheet for adding a connection by `@username` or email. Sends a request
/// the other person can accept from their own Connections tab.
struct AddConnectionView: View {
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var identifier = ""
    @State private var isSending = false
    @State private var feedback: Feedback?
    @FocusState private var fieldFocused: Bool

    private struct Feedback: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    private var isDisabled: Bool {
        isSending || identifier.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    Text("Add a connection")
                        .font(.title3.weight(.bold))
                    Text("Enter a friend's @username or email. They'll get a request to confirm.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)

                HStack {
                    Image(systemName: "at")
                        .foregroundStyle(.secondary)
                    TextField("username or email", text: $identifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($fieldFocused)
                        .onSubmit { Task { await send() } }
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)

                if let feedback {
                    Text(feedback.message)
                        .font(.subheadline)
                        .foregroundStyle(feedback.isError ? .red : .green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .transition(.opacity)
                }

                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        if isSending { ProgressView().tint(.white) }
                        Text("Send request")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(isDisabled ? AnyShapeStyle(Color.blue.opacity(0.35)) : AnyShapeStyle(Color.blue), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .padding(.horizontal, 20)

                Spacer()
            }
            .navigationTitle("New Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { fieldFocused = true }
        }
    }

    private func send() async {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }

        let result = await viewModel.sendConnectionRequest(identifier: trimmed)
        withAnimation {
            switch result {
            case let .sent(name):
                feedback = Feedback(message: "Request sent to \(name).", isError: false)
            case .notFound:
                feedback = Feedback(message: "No one found with that username or email.", isError: true)
            case .alreadyConnected:
                feedback = Feedback(message: "You're already connected.", isError: true)
            case .requestPending:
                feedback = Feedback(message: "There's already a pending request with them.", isError: true)
            case .selfRequest:
                feedback = Feedback(message: "That's you! Try a friend's handle.", isError: true)
            case let .failure(message):
                feedback = Feedback(message: message, isError: true)
            }
        }

        if case .sent = result {
            try? await Task.sleep(for: .seconds(0.9))
            dismiss()
        }
    }
}
