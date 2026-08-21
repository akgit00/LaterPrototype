import SwiftUI
import CoreLocation

// MARK: - Polls section

/// Group polls: anyone on the memory can ask, everyone votes. Tapping your
/// current pick clears your vote.
struct PollsSection: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let onCreate: () -> Void

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if memory.polls.isEmpty {
                ExtrasEmptyState(
                    icon: "chart.bar.fill",
                    title: "No polls yet",
                    message: "Settle it once and for all — best meal, best moment, who fell asleep first.",
                    buttonTitle: "Create a poll",
                    action: onCreate
                )
            } else {
                ForEach(memory.polls) { poll in
                    PollCard(memoryID: memoryID, poll: poll, viewModel: viewModel)
                }

                Button(action: onCreate) {
                    Label("Create a poll", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// One poll with live result bars.
struct PollCard: View {
    let memoryID: UUID
    let poll: MemoryPoll
    let viewModel: LaterViewModel

    private var myVote: PollVote? {
        poll.votes.first { viewModel.isAuthor($0.voterID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(poll.question)
                        .font(.subheadline.weight(.semibold))
                    Text("\(poll.authorName) · \(poll.votes.count) \(poll.votes.count == 1 ? "vote" : "votes")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.isAuthor(poll.authorID) || viewModel.isOwner(of: memoryID) {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.deletePoll(memoryID: memoryID, pollID: poll.id)
                        } label: {
                            Label("Delete poll", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                }
            }

            ForEach(poll.options) { option in
                optionRow(option)
            }

            if myVote != nil {
                Text("Tap your pick again to clear your vote.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .sensoryFeedback(.selection, trigger: myVote?.optionID)
    }

    private func optionRow(_ option: PollOption) -> some View {
        let count = poll.voteCount(for: option.id)
        let total = poll.votes.count
        let fraction = total == 0 ? 0 : Double(count) / Double(total)
        let isMyPick = myVote?.optionID == option.id

        return Button {
            viewModel.votePoll(memoryID: memoryID, pollID: poll.id, optionID: option.id)
        } label: {
            HStack(spacing: 8) {
                Text(option.text)
                    .font(.footnote.weight(isMyPick ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer()

                if isMyPick {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                }

                if total > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.tertiarySystemFill))
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(isMyPick ? 0.3 : 0.14))
                            .frame(width: proxy.size.width * fraction)
                            .animation(.spring(duration: 0.4), value: fraction)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isMyPick ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Builds a new poll: question plus 2–6 options.
struct NewPollSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var question: String = ""
    @State private var options: [String] = ["", ""]

    private var canSave: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && options.count(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("What are we deciding?", text: $question, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Options") {
                    ForEach(options.indices, id: \.self) { index in
                        HStack {
                            TextField("Option \(index + 1)", text: $options[index])
                            if options.count > 2 {
                                Button {
                                    options.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if options.count < 6 {
                        Button {
                            options.append("")
                        } label: {
                            Label("Add option", systemImage: "plus")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle("New poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        viewModel.addPoll(to: memoryID, question: question, options: options)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Prompts section

/// Question cards everyone can answer — one answer per person, editable.
struct PromptsSection: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let onCreate: () -> Void

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if memory.prompts.isEmpty {
                ExtrasEmptyState(
                    icon: "quote.bubble.fill",
                    title: "No prompts yet",
                    message: "Ask everyone the same question — \"Best moment?\" — and collect the answers here.",
                    buttonTitle: "Ask a prompt",
                    action: onCreate
                )
            } else {
                ForEach(memory.prompts) { prompt in
                    PromptCard(memoryID: memoryID, prompt: prompt, viewModel: viewModel)
                }

                Button(action: onCreate) {
                    Label("Ask a prompt", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// One prompt with everyone's answers and an inline answer field.
struct PromptCard: View {
    let memoryID: UUID
    let prompt: MemoryPrompt
    let viewModel: LaterViewModel

    @State private var draft: String = ""
    @State private var isEditing: Bool = false

    private var myAnswer: PromptAnswer? {
        prompt.answers.first { viewModel.isAuthor($0.authorID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.question)
                        .font(.subheadline.weight(.semibold))
                    Text("Asked by \(prompt.authorName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.isAuthor(prompt.authorID) || viewModel.isOwner(of: memoryID) {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.deletePrompt(memoryID: memoryID, promptID: prompt.id)
                        } label: {
                            Label("Delete prompt", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                }
            }

            ForEach(prompt.answers) { answer in
                answerRow(answer)
            }

            if myAnswer == nil || isEditing {
                answerField
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func answerRow(_ answer: PromptAnswer) -> some View {
        let isMine = viewModel.isAuthor(answer.authorID)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(answer.authorName + (isMine ? " (you)" : ""))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(answer.text)
                    .font(.footnote)
            }
            Spacer()
            if isMine && !isEditing {
                Button {
                    draft = answer.text
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    private var answerField: some View {
        HStack(spacing: 8) {
            TextField(myAnswer == nil ? "Your answer…" : "Rewrite your answer…", text: $draft, axis: .vertical)
                .font(.footnote)
                .lineLimit(1...3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 18))
                .onSubmit { submit() }

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.answerPrompt(memoryID: memoryID, promptID: prompt.id, text: text)
        draft = ""
        isEditing = false
    }
}

/// Creates a prompt from a suggestion or a custom question.
struct NewPromptSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var custom: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(PromptSuggestions.all, id: \.self) { suggestion in
                            Button {
                                viewModel.addPrompt(to: memoryID, question: suggestion)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(suggestion)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.footnote)
                                        .foregroundStyle(Color.accentColor)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or ask your own")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("Your question…", text: $custom)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { submitCustom() }

                            Button("Ask") { submitCustom() }
                                .buttonStyle(.borderedProminent)
                                .disabled(custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ask a prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submitCustom() {
        let text = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        viewModel.addPrompt(to: memoryID, question: text)
        dismiss()
    }
}
