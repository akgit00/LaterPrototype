import SwiftUI
import CoreLocation
import PhotosUI

// MARK: - Keepsakes section

/// Tickets, receipts, letters — the physical scraps that made the day.
struct KeepsakesSection: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let onAdd: () -> Void

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if memory.keepsakes.isEmpty {
                ExtrasEmptyState(
                    icon: "ticket.fill",
                    title: "No keepsakes yet",
                    message: "Save the ticket stub, the receipt, the note someone passed you.",
                    buttonTitle: "Add a keepsake",
                    action: onAdd
                )
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(memory.keepsakes) { keepsake in
                        keepsakeCard(keepsake)
                    }
                }

                Button(action: onAdd) {
                    Label("Add a keepsake", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.horizontal, 20)
    }

    private func keepsakeCard(_ keepsake: Keepsake) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL = keepsake.imageURL, !imageURL.isEmpty {
                Color(.tertiarySystemFill)
                    .frame(height: 110)
                    .overlay {
                        MediaImageView(urlString: imageURL)
                            .allowsHitTesting(false)
                    }
                    .clipped()
            } else {
                Color(.tertiarySystemFill)
                    .frame(height: 110)
                    .overlay {
                        Text(keepsake.kindValue.emoji)
                            .font(.system(size: 40))
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(keepsake.kindValue.emoji) \(keepsake.kindValue.label)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(keepsake.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                if !keepsake.note.isEmpty {
                    Text(keepsake.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text("From \(keepsake.authorName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            if viewModel.isAuthor(keepsake.authorID) || viewModel.isOwner(of: memoryID) {
                Button(role: .destructive) {
                    viewModel.deleteKeepsake(memoryID: memoryID, keepsakeID: keepsake.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

/// Adds a keepsake: pick its kind, name it, and optionally photograph it.
struct KeepsakeSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var kind: KeepsakeKind = .ticket
    @State private var title: String = ""
    @State private var note: String = ""
    @State private var pickedItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("What is it?") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(KeepsakeKind.allCases, id: \.self) { option in
                                Button {
                                    kind = option
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(option.emoji)
                                        Text(option.label)
                                            .font(.footnote.weight(.medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        kind == option ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                                        in: Capsule()
                                    )
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(kind == option ? Color.accentColor : .clear, lineWidth: 1.5)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    TextField("Title (e.g. \"Concert ticket\")", text: $title)
                    TextField("A note about it (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Photo (optional)") {
                    if let imageData, let image = UIImage(data: imageData) {
                        Color(.tertiarySystemFill)
                            .frame(height: 160)
                            .overlay {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 4, trailing: 12))

                        Button(role: .destructive) {
                            self.imageData = nil
                            pickedItem = nil
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                                .font(.footnote)
                        }
                    } else {
                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            Label("Photograph it", systemImage: "camera.on.rectangle")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
            }
            .navigationTitle("Add a keepsake")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty && imageData == nil)
                    }
                }
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        imageData = data
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let saveKind = kind
        let saveTitle = title
        let saveNote = note
        let saveImage = imageData
        Task {
            await viewModel.addKeepsake(to: memoryID, kind: saveKind, title: saveTitle, note: saveNote, imageData: saveImage)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Collections section

/// Named photo sub-albums curated by the owner ("Day 1", "The food", …).
struct CollectionsSection: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let onNew: () -> Void

    @State private var openCollectionID: UUID?

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    private var isOwner: Bool { viewModel.isOwner(of: memoryID) }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if memory.collections.isEmpty {
                if isOwner {
                    ExtrasEmptyState(
                        icon: "square.stack.fill",
                        title: "No collections yet",
                        message: "Group this memory's photos into little albums — \"Day 1\", \"The food\", \"Us\".",
                        buttonTitle: "New collection",
                        action: onNew
                    )
                } else {
                    Text("The owner hasn't made any collections yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(memory.collections) { collection in
                        collectionCard(collection)
                    }
                }

                if isOwner {
                    Button(action: onNew) {
                        Label("New collection", systemImage: "plus")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .padding(.horizontal, 20)
        .sheet(item: $openCollectionID) { collectionID in
            CollectionDetailSheet(memoryID: memoryID, collectionID: collectionID, viewModel: viewModel)
        }
    }

    private func collectionCard(_ collection: MemoryCollection) -> some View {
        Button {
            openCollectionID = collection.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Color(.tertiarySystemFill)
                    .frame(height: 92)
                    .overlay {
                        if let cover = collection.photoURLs.first {
                            MediaImageView(urlString: cover)
                                .allowsHitTesting(false)
                        } else {
                            Text(collection.emoji)
                                .font(.system(size: 36))
                        }
                    }
                    .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(collection.emoji) \(collection.name)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(collection.photoURLs.count) \(collection.photoURLs.count == 1 ? "photo" : "photos")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isOwner {
                Button(role: .destructive) {
                    viewModel.deleteCollection(memoryID: memoryID, collectionID: collection.id)
                } label: {
                    Label("Delete collection", systemImage: "trash")
                }
            }
        }
    }
}

/// Names a new collection and picks its emoji.
struct NewCollectionSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var emoji: String = "📁"

    private let emojiOptions: [String] = ["📁", "🌅", "🍜", "🥾", "🎢", "🏖️", "🌃", "👯", "🐚", "🎁"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Day 1, The food, Us", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 8)], spacing: 8) {
                        ForEach(emojiOptions, id: \.self) { option in
                            Button {
                                emoji = option
                            } label: {
                                Text(option)
                                    .font(.system(size: 24))
                                    .frame(width: 48, height: 48)
                                    .background(
                                        emoji == option ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(emoji == option ? Color.accentColor : .clear, lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section {
                    Text("After creating it, open the collection to pick which photos belong in it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        viewModel.addCollection(to: memoryID, name: name, emoji: emoji)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Shows a collection's photos; the owner can change which photos belong.
struct CollectionDetailSheet: View {
    let memoryID: UUID
    let collectionID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isSelecting: Bool = false
    @State private var selectedURLs: Set<String> = []
    @State private var viewer: PhotoViewerSelection?

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    private var collection: MemoryCollection? {
        memory.collections.first { $0.id == collectionID }
    }

    /// Collection photos in the memory's photo order.
    private var collectionPhotos: [String] {
        guard let collection else { return [] }
        return memory.photoURLs.filter { collection.photoURLs.contains($0) }
    }

    private var isOwner: Bool { viewModel.isOwner(of: memoryID) }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                if isSelecting {
                    selectionGrid
                } else {
                    photoGrid
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(collection.map { "\($0.emoji) \($0.name)" } ?? "Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if isOwner {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSelecting ? "Done" : "Select photos") {
                            if isSelecting {
                                let ordered = memory.photoURLs.filter { selectedURLs.contains($0) }
                                viewModel.setCollectionPhotos(memoryID: memoryID, collectionID: collectionID, photoURLs: ordered)
                                isSelecting = false
                            } else {
                                selectedURLs = Set(collection?.photoURLs ?? [])
                                isSelecting = true
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $viewer) { selection in
                PhotoViewerSheet(
                    photoURLs: selection.urls,
                    initialIndex: selection.index,
                    canSave: isOwner || memory.allowsMediaSaving
                )
            }
        }
    }

    private var photoGrid: some View {
        VStack(spacing: 12) {
            if collectionPhotos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(isOwner
                         ? "Empty so far — tap \"Select photos\" to fill this collection."
                         : "The owner hasn't added photos to this collection yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(collectionPhotos.enumerated()), id: \.element) { index, url in
                        Button {
                            viewer = PhotoViewerSelection(urls: collectionPhotos, index: index)
                        } label: {
                            photoCell(url)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }
        }
    }

    private var selectionGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap the photos that belong in this collection.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(memory.photoURLs, id: \.self) { url in
                    Button {
                        if selectedURLs.contains(url) {
                            selectedURLs.remove(url)
                        } else {
                            selectedURLs.insert(url)
                        }
                    } label: {
                        photoCell(url)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: selectedURLs.contains(url) ? "checkmark.circle.fill" : "circle")
                                    .font(.body)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, selectedURLs.contains(url) ? Color.accentColor : .black.opacity(0.35))
                                    .padding(6)
                            }
                            .opacity(selectedURLs.contains(url) ? 1 : 0.72)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
    }

    private func photoCell(_ url: String) -> some View {
        Color(.tertiarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                MediaImageView(urlString: url)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Linked memories section

/// Other memories connected to this one — the sequel trip, the same spot a
/// year later. Tap one to jump into it.
struct LinkedMemoriesSection: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let onLink: () -> Void

    @State private var openMemoryID: UUID?

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: .init())
    }

    private var isOwner: Bool { viewModel.isOwner(of: memoryID) }

    private var linkedMemories: [Memory] {
        memory.linkedMemoryIDs.compactMap { viewModel.memoryByID($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if linkedMemories.isEmpty {
                if isOwner {
                    ExtrasEmptyState(
                        icon: "link",
                        title: "No linked memories",
                        message: "Connect related memories — the sequel trip, the same place a year later.",
                        buttonTitle: "Link a memory",
                        action: onLink
                    )
                } else {
                    Text("No linked memories yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                }
            } else {
                ForEach(linkedMemories) { linked in
                    linkedCard(linked)
                }

                if isOwner {
                    Button(action: onLink) {
                        Label("Link a memory", systemImage: "link")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
            }
        }
        .padding(.horizontal, 20)
        .fullScreenCover(item: $openMemoryID) { linkedID in
            MemoryRoomView(memoryID: linkedID, viewModel: viewModel)
        }
    }

    private func linkedCard(_ linked: Memory) -> some View {
        Button {
            openMemoryID = linked.id
        } label: {
            HStack(spacing: 12) {
                Color(.tertiarySystemFill)
                    .frame(width: 54, height: 54)
                    .overlay {
                        if let cover = linked.photoURLs.first {
                            MediaImageView(urlString: cover)
                                .allowsHitTesting(false)
                        } else {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(linked.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(linked.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isOwner {
                Button(role: .destructive) {
                    let remaining = memory.linkedMemoryIDs.filter { $0 != linked.id }
                    viewModel.setLinkedMemories(memoryID: memoryID, linkedIDs: remaining)
                } label: {
                    Label("Unlink", systemImage: "link.badge.plus")
                }
            }
        }
    }
}

/// Picks which of your other memories connect to this one.
struct LinkMemoriesSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<UUID>

    init(memoryID: UUID, viewModel: LaterViewModel) {
        self.memoryID = memoryID
        self.viewModel = viewModel
        let current = viewModel.memoryByID(memoryID)?.linkedMemoryIDs ?? []
        _selectedIDs = State(initialValue: Set(current))
    }

    private var candidates: [Memory] {
        viewModel.memories.filter { $0.id != memoryID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("No other memories", systemImage: "link")
                    } description: {
                        Text("Create another memory first, then link it here.")
                    }
                } else {
                    List(candidates) { candidate in
                        Button {
                            if selectedIDs.contains(candidate.id) {
                                selectedIDs.remove(candidate.id)
                            } else {
                                selectedIDs.insert(candidate.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Color(.tertiarySystemFill)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        if let cover = candidate.photoURLs.first {
                                            MediaImageView(urlString: cover)
                                                .allowsHitTesting(false)
                                        } else {
                                            Image(systemName: "mappin.and.ellipse")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(candidate.date, style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedIDs.contains(candidate.id) ? Color.accentColor : Color(.tertiaryLabel))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Link memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ordered = viewModel.memories.filter { selectedIDs.contains($0.id) }.map(\.id)
                        viewModel.setLinkedMemories(memoryID: memoryID, linkedIDs: ordered)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
