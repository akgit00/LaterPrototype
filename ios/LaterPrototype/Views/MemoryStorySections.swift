import SwiftUI
import CoreLocation

// MARK: - Story section

/// Long-form written versions of what happened. Everyone on the memory can
/// add their own take; each person gets one entry they can keep editing.
struct StorySection: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    /// Opens the editor — nil writes a new entry, an entry edits it.
    let onEdit: (StoryEntry?) -> Void

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    private var myEntry: StoryEntry? {
        memory.storyEntries.first { viewModel.isAuthor($0.authorID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if memory.storyEntries.isEmpty {
                ExtrasEmptyState(
                    icon: "book.pages",
                    title: "No story yet",
                    message: "Write down what happened — everyone on this memory can add their own version.",
                    buttonTitle: "Write the story",
                    action: { onEdit(nil) }
                )
            } else {
                ForEach(memory.storyEntries) { entry in
                    storyCard(entry)
                }

                Button {
                    onEdit(myEntry)
                } label: {
                    Label(
                        myEntry == nil ? "Add your version" : "Edit your version",
                        systemImage: myEntry == nil ? "plus" : "pencil"
                    )
                    .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 20)
    }

    private func storyCard(_ entry: StoryEntry) -> some View {
        let isMine = viewModel.isAuthor(entry.authorID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(entry.authorName)
                    .font(.footnote.weight(.semibold))
                if isMine {
                    Text("You")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
                Spacer()
                Text(entry.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.text)
                .font(.subheadline)
                .lineSpacing(3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            if isMine {
                Button {
                    onEdit(entry)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if isMine || viewModel.isOwner(of: memoryID) {
                Button(role: .destructive) {
                    viewModel.deleteStoryEntry(memoryID: memoryID, entryID: entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

/// Writes or rewrites one person's story entry.
struct StoryEditorSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let existing: StoryEntry?
    @Environment(\.dismiss) private var dismiss

    @State private var text: String

    init(memoryID: UUID, viewModel: LaterViewModel, existing: StoryEntry?) {
        self.memoryID = memoryID
        self.viewModel = viewModel
        self.existing = existing
        _text = State(initialValue: existing?.text ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                Text("Your version appears alongside everyone else's in the Story section.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(existing == nil ? "Write the story" : "Edit your version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let existing {
                            viewModel.updateStoryEntry(memoryID: memoryID, entryID: existing.id, text: text)
                        } else {
                            viewModel.addStoryEntry(to: memoryID, text: text)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Voice notes section

/// Short audio recordings — the sound of the day, retold jokes, ambient noise.
struct VoiceNotesSection: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let onRecord: () -> Void

    private var player: VoiceNotePlayer { .shared }

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if memory.voiceNotes.isEmpty {
                ExtrasEmptyState(
                    icon: "waveform",
                    title: "No voice notes yet",
                    message: "Capture the sound of this memory — a laugh, a story, the room itself.",
                    buttonTitle: "Record a voice note",
                    action: onRecord
                )
            } else {
                ForEach(memory.voiceNotes) { note in
                    voiceRow(note)
                }

                Button(action: onRecord) {
                    Label("Record a voice note", systemImage: "mic.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 20)
        .onDisappear { player.stop() }
    }

    private func voiceRow(_ note: VoiceNote) -> some View {
        let isActive = player.activeNoteID == note.id
        let isLoading = player.loadingNoteID == note.id
        return Button {
            Task { await player.toggle(note) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 42, height: 42)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: isActive ? "stop.fill" : "play.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(note.authorName) · \(VoiceNoteFormat.duration(note.duration)) · \(note.date.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isActive {
                    Image(systemName: "waveform")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if viewModel.isAuthor(note.authorID) || viewModel.isOwner(of: memoryID) {
                Button(role: .destructive) {
                    if isActive { player.stop() }
                    viewModel.deleteVoiceNote(memoryID: memoryID, noteID: note.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

/// Records a new voice note: tap to record, stop, preview, name it, save.
struct VoiceRecorderSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var recorder = VoiceNoteRecorder()
    @State private var title: String = ""
    @State private var isSaving: Bool = false
    @State private var didSave: Bool = false
    @State private var previewID = UUID()

    private var player: VoiceNotePlayer { .shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                switch recorder.phase {
                case .idle:
                    recordButton
                    Text("Tap to start recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .denied:
                    ContentUnavailableView {
                        Label("Microphone access needed", systemImage: "mic.slash")
                    } description: {
                        Text("Allow microphone access in Settings to record voice notes.")
                    } actions: {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }

                case .recording:
                    elapsedText
                    Button {
                        recorder.stop()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.red.opacity(0.15))
                                .frame(width: 84, height: 84)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.red)
                                .frame(width: 30, height: 30)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Recording… tap to stop")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .recorded:
                    elapsedText

                    HStack(spacing: 14) {
                        Button {
                            Task { await player.toggle(previewNote) }
                        } label: {
                            Label(
                                player.activeNoteID == previewID ? "Stop" : "Play back",
                                systemImage: player.activeNoteID == previewID ? "stop.fill" : "play.fill"
                            )
                            .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)

                        Button {
                            player.stop()
                            recorder.discard()
                        } label: {
                            Label("Re-record", systemImage: "arrow.counterclockwise")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }

                    TextField("Name this voice note (optional)", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 8)

                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Save to memory")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                    .padding(.horizontal, 8)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Voice note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        player.stop()
                        recorder.discard()
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(recorder.phase == .recording || isSaving)
        .onDisappear {
            player.stop()
            if !didSave { recorder.discard() }
        }
    }

    private var previewNote: VoiceNote {
        VoiceNote(
            id: previewID,
            authorID: "",
            authorName: "",
            title: "Preview",
            audioURL: recorder.fileURL?.absoluteString ?? "",
            duration: recorder.elapsed,
            date: Date()
        )
    }

    private var recordButton: some View {
        Button {
            Task { await recorder.requestAndStart() }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 84, height: 84)
                Image(systemName: "mic.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
    }

    private var elapsedText: some View {
        Text(VoiceNoteFormat.duration(recorder.elapsed))
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private func save() {
        guard let fileURL = recorder.fileURL, !isSaving else { return }
        player.stop()
        isSaving = true
        let duration = recorder.elapsed
        let noteTitle = title
        Task {
            await viewModel.addVoiceNote(to: memoryID, title: noteTitle, localFileURL: fileURL, duration: duration)
            didSave = true
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Sealed notes section

/// Notes locked until a chosen date — tiny time capsules inside the memory.
struct SealedNotesSection: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let onAdd: () -> Void

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    /// Locked notes first (soonest unlock on top), then opened ones.
    private var orderedNotes: [SealedNote] {
        memory.sealedNotes.sorted { first, second in
            if first.isUnlocked != second.isUnlocked {
                return !first.isUnlocked
            }
            return first.unlockDate < second.unlockDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if memory.sealedNotes.isEmpty {
                ExtrasEmptyState(
                    icon: "lock.fill",
                    title: "Leave a note for the future",
                    message: "Write something now — it stays sealed until the day you pick, even from you.",
                    buttonTitle: "Seal a note",
                    action: onAdd
                )
            } else {
                ForEach(orderedNotes) { note in
                    sealedCard(note)
                }

                Button(action: onAdd) {
                    Label("Seal a note", systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func sealedCard(_ note: SealedNote) -> some View {
        let card = Group {
            if note.isUnlocked {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("From \(note.authorName)")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        Text("Opened \(note.unlockDate.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(note.text)
                        .font(.subheadline)
                        .lineSpacing(3)
                }
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.indigo.opacity(0.15))
                            .frame(width: 42, height: 42)
                        Image(systemName: "lock.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.indigo)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sealed by \(note.authorName)")
                            .font(.footnote.weight(.semibold))
                        (Text("Opens \(note.unlockDate.formatted(.dateTime.month(.abbreviated).day().year())) · ")
                            + Text(note.unlockDate, style: .relative))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

        card.contextMenu {
            if viewModel.isAuthor(note.authorID) || viewModel.isOwner(of: memoryID) {
                Button(role: .destructive) {
                    viewModel.deleteSealedNote(memoryID: memoryID, noteID: note.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

/// Writes a new sealed note and picks its unlock date.
struct SealedNoteSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var unlockDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    private var minimumDate: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    private struct QuickSpan: Identifiable {
        let label: String
        let component: Calendar.Component
        let value: Int
        var id: String { label }
    }

    private let spans: [QuickSpan] = [
        QuickSpan(label: "1 month", component: .month, value: 1),
        QuickSpan(label: "6 months", component: .month, value: 6),
        QuickSpan(label: "1 year", component: .year, value: 1),
        QuickSpan(label: "5 years", component: .year, value: 5),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your note")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $text)
                            .font(.body)
                            .frame(minHeight: 130)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Opens on")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(spans) { span in
                                Button(span.label) {
                                    if let date = Calendar.current.date(byAdding: span.component, value: span.value, to: Date()) {
                                        unlockDate = date
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                        }

                        DatePicker("", selection: $unlockDate, in: minimumDate..., displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }

                    Text("Sealed notes stay hidden from everyone — including you — until the day they open.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Seal a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Seal") {
                        viewModel.addSealedNote(to: memoryID, text: text, unlockDate: unlockDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Shared empty state

/// Compact call-to-action shown when a section has no content yet.
struct ExtrasEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button(action: action) {
                Text(buttonTitle)
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
