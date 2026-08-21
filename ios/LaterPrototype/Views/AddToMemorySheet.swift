import SwiftUI
import UIKit

/// Everything the "+" menu can add or open inside a memory.
enum AddMemoryAction: String, Identifiable {
    case photos
    case voice
    case story
    case keepsake
    case poll
    case prompt
    case sealed
    case people
    case pinInside
    case collection
    case linkMemory
    case playlist
    case song
    case weather
    case anniversary
    case editDetails

    var id: String { rawValue }
}

/// The extras editor currently presented from the media sheet.
enum MemoryExtraSheet: Identifiable {
    case story(StoryEntry?)
    case voice
    case sealed
    case poll
    case prompt
    case keepsake
    case newCollection
    case linkMemories
    case weather
    case anniversary

    var id: String {
        switch self {
        case .story(let entry): "story-\(entry?.id.uuidString ?? "new")"
        case .voice: "voice"
        case .sealed: "sealed"
        case .poll: "poll"
        case .prompt: "prompt"
        case .keepsake: "keepsake"
        case .newCollection: "newCollection"
        case .linkMemories: "linkMemories"
        case .weather: "weather"
        case .anniversary: "anniversary"
        }
    }
}

/// The "+" customize menu: one place to add anything to a memory —
/// media, stories, voice notes, polls, keepsakes, links, and more.
struct AddToMemorySheet: View {
    let isOwner: Bool
    let onSelect: (AddMemoryAction) -> Void

    private struct Tile: Identifiable {
        let action: AddMemoryAction
        let icon: String
        let label: String
        let color: Color
        var ownerOnly: Bool = false
        var id: String { action.id }
    }

    private struct Group: Identifiable {
        let title: String
        let tiles: [Tile]
        var id: String { title }
    }

    private var groups: [Group] {
        [
            Group(title: "Capture", tiles: [
                Tile(action: .photos, icon: "photo.on.rectangle.angled", label: "Photos & Videos", color: .blue),
                Tile(action: .voice, icon: "waveform", label: "Voice note", color: .orange),
                Tile(action: .story, icon: "book.pages", label: "Story", color: .brown),
                Tile(action: .keepsake, icon: "ticket.fill", label: "Keepsake", color: .pink),
            ]),
            Group(title: "Together", tiles: [
                Tile(action: .poll, icon: "chart.bar.fill", label: "Poll", color: .purple),
                Tile(action: .prompt, icon: "quote.bubble.fill", label: "Prompt", color: .teal),
                Tile(action: .sealed, icon: "lock.fill", label: "Sealed note", color: .indigo),
                Tile(action: .people, icon: "person.badge.plus", label: "People", color: .green),
            ]),
            Group(title: "Organize", tiles: [
                Tile(action: .pinInside, icon: "mappin.and.ellipse", label: "Pin inside", color: .red, ownerOnly: true),
                Tile(action: .collection, icon: "square.stack.fill", label: "Collection", color: .cyan, ownerOnly: true),
                Tile(action: .linkMemory, icon: "link", label: "Link memory", color: .mint, ownerOnly: true),
                Tile(action: .playlist, icon: "music.note.list", label: "Playlist", color: .pink),
                Tile(action: .song, icon: "music.note", label: "Song", color: .purple),
            ]),
            Group(title: "Details", tiles: [
                Tile(action: .weather, icon: "cloud.sun.fill", label: "Weather & mood", color: .yellow, ownerOnly: true),
                Tile(action: .anniversary, icon: "bell.badge.fill", label: "Anniversary", color: .orange),
                Tile(action: .editDetails, icon: "pencil", label: "Edit details", color: .gray, ownerOnly: true),
            ]),
        ]
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups) { group in
                        let tiles = group.tiles.filter { isOwner || !$0.ownerOnly }
                        if !tiles.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(tiles) { tile in
                                        tileButton(tile)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add to this memory")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func tileButton(_ tile: Tile) -> some View {
        Button {
            onSelect(tile.action)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: tile.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tile.color)
                    .frame(width: 46, height: 46)
                    .background(tile.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))

                Text(tile.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Weather & mood

/// Shows and edits the memory's weather + mood chip. Weather is looked up
/// automatically for the memory's place and day; the mood is hand-picked.
struct WeatherMoodSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: WeatherSnapshot?
    @State private var mood: String?
    @State private var isFetching: Bool = false
    @State private var fetchFailed: Bool = false

    private var memory: Memory? { viewModel.memoryByID(memoryID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    weatherCard
                    moodPicker

                    if memory?.weather != nil {
                        Button(role: .destructive) {
                            viewModel.setWeather(for: memoryID, weather: nil)
                            dismiss()
                        } label: {
                            Label("Remove from header", systemImage: "trash")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weather & Mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .task { await loadInitial() }
        }
        .presentationDetents([.medium, .large])
    }

    private var canSave: Bool {
        snapshot?.temperatureCelsius != nil || snapshot?.weatherCode != nil || mood != nil
    }

    private var weatherCard: some View {
        VStack(spacing: 10) {
            if let snapshot, snapshot.temperatureCelsius != nil || snapshot.weatherCode != nil {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: 44))
                    .symbolRenderingMode(.multicolor)

                if let temperature = snapshot.temperatureText {
                    Text(temperature)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                }

                if let condition = snapshot.conditionLabel {
                    Text(condition)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let date = memory?.date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else if isFetching {
                ProgressView()
                    .padding(.vertical, 8)
                Text("Looking up that day's weather…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "cloud.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(fetchFailed
                     ? "Couldn't find weather for that day and place."
                     : "No weather loaded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await fetchWeather() }
            } label: {
                Label("Look up weather", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isFetching)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How did that day feel?")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                ForEach(WeatherSnapshot.moodOptions, id: \.self) { option in
                    Button {
                        mood = (mood == option) ? nil : option
                    } label: {
                        Text(option)
                            .font(.system(size: 26))
                            .frame(width: 52, height: 52)
                            .background(
                                mood == option ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(mood == option ? Color.accentColor : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Shown in the memory header, like \"72° Sunny · 😄\".")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func loadInitial() async {
        if let existing = memory?.weather {
            snapshot = existing
            mood = existing.mood
            if existing.temperatureCelsius == nil && existing.weatherCode == nil {
                await fetchWeather()
            }
        } else {
            await fetchWeather()
        }
    }

    private func fetchWeather() async {
        guard let memory, !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        if let fetched = await WeatherSnapshotService.fetch(coordinate: memory.centerCoordinate, date: memory.date) {
            snapshot = WeatherSnapshot(
                temperatureCelsius: fetched.temperatureCelsius,
                weatherCode: fetched.weatherCode,
                mood: mood
            )
            fetchFailed = false
        } else {
            fetchFailed = true
        }
    }

    private func save() {
        var result = snapshot ?? WeatherSnapshot(temperatureCelsius: nil, weatherCode: nil, mood: nil)
        result.mood = mood
        guard result.hasContent else { return }
        viewModel.setWeather(for: memoryID, weather: result)
        dismiss()
    }
}

// MARK: - Anniversary

/// Turns a yearly on-this-day reminder on or off for this memory. Personal
/// to this device, so everyone on a shared memory chooses for themselves.
struct AnniversarySheet: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isEnabled: Bool = false
    @State private var permissionDenied: Bool = false

    private var service: AnniversaryReminderService { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $isEnabled) {
                        Label("Yearly reminder", systemImage: "bell.badge.fill")
                    }
                    .onChange(of: isEnabled) { _, newValue in
                        guard newValue != service.isEnabled(memory.id) else { return }
                        Task {
                            let granted = await service.setEnabled(newValue, for: memory)
                            if !granted {
                                isEnabled = false
                                permissionDenied = true
                            } else {
                                permissionDenied = false
                            }
                        }
                    }
                } footer: {
                    Text("Every \(memory.date.formatted(.dateTime.month(.wide).day())), you'll get a reminder to look back at \"\(memory.title)\".")
                }

                if isEnabled, let next = service.nextOccurrence(for: memory) {
                    Section {
                        LabeledContent("Next reminder") {
                            Text(next, style: .date)
                        }
                    }
                }

                if permissionDenied {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notifications are off", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text("Allow notifications for Later in Settings to get anniversary reminders.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle("Anniversary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                isEnabled = service.isEnabled(memory.id)
            }
        }
        .presentationDetents([.medium])
    }
}
