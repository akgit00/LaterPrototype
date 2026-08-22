import SwiftUI
import UIKit

/// The Collections tab: automatic end-of-year wraps up top, followed by the
/// user's own collections — eras, trip series, anything worth grouping.
struct CollectionsView: View {
    let viewModel: LaterViewModel

    @State private var editorTarget: CollectionEditorTarget?
    @State private var openedDisplay: CollectionDisplay?
    @State private var collectionToDelete: LifeCollection?
    @State private var collectionToRename: LifeCollection?
    @State private var renameText: String = ""
    @State private var importPayload: SharedCollectionPayload?
    @State private var showNoLinkAlert: Bool = false
    /// Watches for tapped year-wrap notifications to open that year's story.
    @State private var router = NotificationRouter.shared

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.memories.isEmpty && viewModel.lifeCollections.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            yearsSection
                            customSection
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 32)
                    }
                    .refreshable { await viewModel.loadLifeCollections() }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        importFromClipboard()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = .create
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                CollectionEditorSheet(viewModel: viewModel, existing: target.collection)
            }
            .fullScreenCover(item: $openedDisplay) { display in
                CollectionDetailView(display: display, viewModel: viewModel)
            }
            .onAppear { openPendingWrapIfNeeded() }
            .onChange(of: router.pendingWrapYear) { _, _ in openPendingWrapIfNeeded() }
            .confirmationDialog(
                "Delete \"\(collectionToDelete?.name ?? "collection")\"?",
                isPresented: Binding(
                    get: { collectionToDelete != nil },
                    set: { if !$0 { collectionToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Collection", role: .destructive) {
                    if let collection = collectionToDelete {
                        viewModel.deleteLifeCollection(id: collection.id)
                    }
                    collectionToDelete = nil
                }
                Button("Cancel", role: .cancel) { collectionToDelete = nil }
            } message: {
                Text("The memories inside stay untouched — only the collection goes away.")
            }
            .sheet(item: $importPayload) { payload in
                CollectionImportSheet(payload: payload, viewModel: viewModel)
            }
            .alert("Rename Collection", isPresented: Binding(
                get: { collectionToRename != nil },
                set: { if !$0 { collectionToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let collection = collectionToRename {
                        viewModel.renameLifeCollection(id: collection.id, to: renameText)
                    }
                    collectionToRename = nil
                }
                Button("Cancel", role: .cancel) { collectionToRename = nil }
            }
            .alert("No collection link found", isPresented: $showNoLinkAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Copy a shared collection link (or the whole message it came in), then tap Import again.")
            }
        }
    }

    /// Reads a pasted share link from the clipboard and previews the import.
    private func importFromClipboard() {
        if let text = UIPasteboard.general.string,
           let payload = CollectionShareCodec.decode(text: text) {
            importPayload = payload
        } else {
            showNoLinkAlert = true
        }
    }

    /// Opens the Wrapped story for a tapped unlock notification once the
    /// wrap's year is known. Falls back to just landing on this tab when the
    /// year holds no memories anymore.
    private func openPendingWrapIfNeeded() {
        guard let year = router.pendingWrapYear else { return }
        router.pendingWrapYear = nil
        guard let wrap = viewModel.yearWraps.first(where: { $0.year == year }) else { return }
        openedDisplay = CollectionDisplay.from(wrap, opensInWrapped: true)
    }

    // MARK: - Years (auto wraps)

    private var yearsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Your Years", subtitle: "Made automatically when a year ends")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(viewModel.yearWraps) { wrap in
                        YearWrapCard(
                            wrap: wrap,
                            onOpenWeb: {
                                openedDisplay = CollectionDisplay.from(wrap, opensInWrapped: false)
                            },
                            onOpenWrapped: {
                                openedDisplay = CollectionDisplay.from(wrap, opensInWrapped: true)
                            }
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16)
        }
    }

    // MARK: - Custom collections

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "My Collections", subtitle: "Group memories into eras of your life")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(viewModel.lifeCollections) { collection in
                    CollectionCard(
                        collection: collection,
                        memories: viewModel.memories(in: collection)
                    ) {
                        openedDisplay = CollectionDisplay.from(
                            collection,
                            memories: viewModel.memories(in: collection)
                        )
                    }
                    .contextMenu {
                        Button {
                            editorTarget = .edit(collection)
                        } label: {
                            Label("Edit Collection", systemImage: "pencil")
                        }
                        Button {
                            renameText = collection.name
                            collectionToRename = collection
                        } label: {
                            Label("Rename", systemImage: "character.cursor.ibeam")
                        }
                        if let message = CollectionShareCodec.shareMessage(for: collection) {
                            ShareLink(item: message) {
                                Label("Share Collection", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button(role: .destructive) {
                            collectionToDelete = collection
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                newCollectionTile
            }
            .padding(.horizontal, 16)
        }
    }

    private var newCollectionTile: some View {
        Button {
            editorTarget = .create
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                Text("New Collection")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing to collect yet", systemImage: "square.stack.3d.up.slash")
        } description: {
            Text("Pin a few memories on the Explore globe first. They'll gather here into collections and your automatic year-end wrap.")
        }
    }
}

/// What the editor sheet is being opened for.
private enum CollectionEditorTarget: Identifiable {
    case create
    case edit(LifeCollection)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let collection): collection.id.uuidString
        }
    }

    var collection: LifeCollection? {
        switch self {
        case .create: nil
        case .edit(let collection): collection
        }
    }
}

// MARK: - Year wrap card

private struct YearWrapCard: View {
    let wrap: YearWrap
    let onOpenWeb: () -> Void
    let onOpenWrapped: () -> Void

    private var placeCount: Int { WrappedStats.placeCount(of: wrap.memories) }

    private var gradientColors: [Color] {
        if !wrap.isComplete {
            return [Color(red: 0.07, green: 0.11, blue: 0.16), Color(red: 0.05, green: 0.32, blue: 0.36)]
        }
        let palettes: [[Color]] = [
            [Color(red: 0.16, green: 0.07, blue: 0.36), Color(red: 0.63, green: 0.15, blue: 0.85)],
            [Color(red: 0.36, green: 0.05, blue: 0.16), Color(red: 0.95, green: 0.36, blue: 0.20)],
            [Color(red: 0.02, green: 0.19, blue: 0.30), Color(red: 0.05, green: 0.63, blue: 0.60)],
            [Color(red: 0.24, green: 0.13, blue: 0.02), Color(red: 0.92, green: 0.62, blue: 0.12)],
        ]
        let index = abs(wrap.year) % palettes.count
        return palettes[index]
    }

    var body: some View {
        Button(action: onOpenWeb) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(String(wrap.year))
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    if wrap.isComplete {
                        Text("WRAPPED")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white, in: Capsule())
                    } else {
                        Text("IN PROGRESS")
                            .font(.caption2.weight(.heavy))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                }

                Spacer()

                if !wrap.isComplete {
                    yearProgressBar
                        .padding(.bottom, 10)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(wrap.memories.count) \(wrap.memories.count == 1 ? "memory" : "memories") · \(placeCount) \(placeCount == 1 ? "place" : "places")")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(wrap.isComplete
                             ? "See the web it wove"
                             : "Unlocks Dec 31 · \(YearWrap.daysUntilUnlock()) days")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    Button(action: onOpenWrapped) {
                        Label(wrap.isComplete ? "Wrapped" : "Peek", systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.2), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(width: 290, height: 180)
            .background {
                ZStack {
                    LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    WebGlyph()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                        .frame(width: 150, height: 150)
                        .offset(x: 80, y: -20)
                }
            }
            .clipShape(.rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
    }

    private var yearProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                Capsule()
                    .fill(.white)
                    .frame(width: max(proxy.size.width * YearWrap.yearProgress(), 8))
            }
        }
        .frame(height: 5)
    }
}

/// A tiny constellation-web doodle drawn on the year cards.
private struct WebGlyph: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [
            CGPoint(x: rect.width * 0.15, y: rect.height * 0.30),
            CGPoint(x: rect.width * 0.48, y: rect.height * 0.12),
            CGPoint(x: rect.width * 0.85, y: rect.height * 0.35),
            CGPoint(x: rect.width * 0.62, y: rect.height * 0.62),
            CGPoint(x: rect.width * 0.25, y: rect.height * 0.80),
            CGPoint(x: rect.width * 0.88, y: rect.height * 0.85),
        ]
        let edges: [(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4), (0, 3), (1, 3), (3, 5), (2, 5)]
        for (a, b) in edges {
            path.move(to: points[a])
            path.addLine(to: points[b])
        }
        for point in points {
            path.addEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
        }
        return path
    }
}

// MARK: - Custom collection card

private struct CollectionCard: View {
    let collection: LifeCollection
    let memories: [Memory]
    let onOpen: () -> Void

    private var tint: Color { MemoryPinStyle.color(named: collection.colorName) }

    /// Newest photo across the member memories, used as the card cover.
    private var coverURL: String? {
        for memory in memories.sorted(by: { $0.date > $1.date }) {
            if let url = memory.photoURLs.first(where: { !$0.isEmpty }) {
                return url
            }
        }
        return nil
    }

    var body: some View {
        Button(action: onOpen) {
            Color(.secondarySystemBackground)
                .frame(height: 170)
                .overlay {
                    if coverURL != nil {
                        MediaImageView(urlString: coverURL)
                            .allowsHitTesting(false)
                    } else {
                        LinearGradient(
                            colors: [tint.opacity(0.85), tint.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .allowsHitTesting(false)
                    }
                }
                .overlay {
                    LinearGradient(
                        colors: [.black.opacity(0.05), .black.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 24))
                .overlay(alignment: .topLeading) {
                    Text(collection.emoji)
                        .font(.system(size: 17))
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collection.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(memories.count) \(memories.count == 1 ? "memory" : "memories")")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(12)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(tint.opacity(0.4), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editor sheet

/// Creates a new collection or edits an existing one: name, icon, color, and
/// which memories belong inside.
struct CollectionEditorSheet: View {
    let viewModel: LaterViewModel
    let existing: LifeCollection?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var colorName: String
    @State private var selectedIDs: Set<UUID>

    init(viewModel: LaterViewModel, existing: LifeCollection?, preselectedIDs: Set<UUID> = []) {
        self.viewModel = viewModel
        self.existing = existing
        self._name = State(initialValue: existing?.name ?? "")
        self._emoji = State(initialValue: existing?.emoji ?? "✨")
        self._colorName = State(initialValue: existing?.colorName ?? "purple")
        self._selectedIDs = State(initialValue: Set(existing?.memoryIDs ?? []).union(preselectedIDs))
    }

    private var sortedMemories: [Memory] {
        viewModel.memories.sorted { $0.date > $1.date }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name — e.g. College Era", text: $name)
                        .font(.headline)
                }

                Section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(LifeCollection.emojiOptions, id: \.self) { option in
                                Button {
                                    emoji = option
                                } label: {
                                    Text(option)
                                        .font(.title3)
                                        .frame(width: 42, height: 42)
                                        .background(
                                            emoji == option ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                            in: Circle()
                                        )
                                        .overlay {
                                            Circle().strokeBorder(
                                                emoji == option ? Color.accentColor : .clear,
                                                lineWidth: 2
                                            )
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(MemoryPinStyle.colorNames, id: \.self) { option in
                            Button {
                                colorName = option
                            } label: {
                                Circle()
                                    .fill(MemoryPinStyle.color(named: option))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if colorName == option {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.black))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Memories · \(selectedIDs.count) selected") {
                    if sortedMemories.isEmpty {
                        Text("No memories yet — pin some on the Explore globe first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedMemories) { memory in
                            memoryRow(memory)
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Collection" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.body.weight(.semibold))
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func memoryRow(_ memory: Memory) -> some View {
        let isSelected = selectedIDs.contains(memory.id)
        return Button {
            if isSelected {
                selectedIDs.remove(memory.id)
            } else {
                selectedIDs.insert(memory.id)
            }
        } label: {
            HStack(spacing: 12) {
                Color(.tertiarySystemFill)
                    .frame(width: 44, height: 44)
                    .overlay {
                        MediaImageView(urlString: memory.photoURLs.first)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(memory.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(memory.date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Existing members keep the user's arrangement (including drag-and-
        // drop reorders); newly added ones append at the end in date order.
        let keptOrder = (existing?.memoryIDs ?? []).filter { selectedIDs.contains($0) }
        let keptSet = Set(keptOrder)
        let added = viewModel.memories
            .filter { selectedIDs.contains($0.id) && !keptSet.contains($0.id) }
            .sorted { $0.date < $1.date }
            .map { $0.id }
        let orderedIDs = keptOrder + added
        let collection = LifeCollection(
            id: existing?.id ?? UUID(),
            name: trimmed,
            emoji: emoji,
            colorName: colorName,
            memoryIDs: orderedIDs,
            createdAt: existing?.createdAt ?? Date()
        )
        viewModel.saveLifeCollection(collection)
        dismiss()
    }
}
