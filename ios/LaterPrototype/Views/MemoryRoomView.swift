import SwiftUI
import MapKit
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct MemoryRoomView: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mapPosition: MapCameraPosition
    @State private var selectedPhotoIndex: Int?
    @State private var showPhotoViewer: Bool = false
    @State private var selectedDetent: PresentationDetent = .fraction(0.45)
    @State private var showMediaSheet: Bool = true
    @State private var showAddPlaylistSheet: Bool = false
    @State private var showAddPeopleSheet: Bool = false
    @State private var playingVideoURL: URL?
    @State private var showDeleteMemoryConfirm: Bool = false

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: CLLocationCoordinate2D())
    }

    init(memoryID: UUID, viewModel: LaterViewModel) {
        self.memoryID = memoryID
        self.viewModel = viewModel
        let mem = viewModel.memoryByID(memoryID)
        let center = mem?.centerCoordinate ?? CLLocationCoordinate2D()
        let span = mem?.spanDelta ?? 0.5
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                ForEach(memory.pins) { pin in
                    if let imageURL = pin.imageURL {
                        Annotation(pin.title, coordinate: pin.coordinate) {
                            Button {
                                if let idx = memory.photoURLs.firstIndex(of: imageURL) {
                                    selectedPhotoIndex = idx
                                    showPhotoViewer = true
                                }
                            } label: {
                                PhotoPinView(imageURL: imageURL, title: pin.title)
                            }
                        }
                    } else {
                        Annotation(pin.title, coordinate: pin.coordinate) {
                            SmallPinView()
                        }
                    }
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .ignoresSafeArea()

            headerOverlay
        }
        .sheet(isPresented: $showMediaSheet) {
            MemoryMediaSheet(
                memoryID: memoryID,
                viewModel: viewModel,
                selectedPhotoIndex: $selectedPhotoIndex,
                showPhotoViewer: $showPhotoViewer,
                playingVideoURL: $playingVideoURL,
                onAddPlaylist: {
                    showAddPlaylistSheet = true
                },
                onAddPeople: {
                    showAddPeopleSheet = true
                }
            )
            .presentationDetents([.fraction(0.15), .fraction(0.45), .large], selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
            .presentationCornerRadius(24)
            .presentationContentInteraction(.scrolls)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showAddPlaylistSheet) {
            AddPlaylistSheet(memoryID: memoryID, viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAddPeopleSheet) {
            AddPeopleSheet(memoryID: memoryID, viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Delete this memory?",
            isPresented: $showDeleteMemoryConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Memory", role: .destructive) {
                viewModel.deleteMemory(memoryID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all photos, videos, and details for \"\(memory.title)\".")
        }
    }

    private var headerOverlay: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }

                Spacer()

                Menu {
                    Button {
                        showAddPeopleSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        showDeleteMemoryConfirm = true
                    } label: {
                        Label("Delete Memory", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Text(memory.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)

            if !memory.creators.isEmpty {
                Text("Memory created by " + memory.creators.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }

            if !memory.connections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: -6) {
                        ForEach(memory.connections) { connection in
                            ConnectionAvatarView(connection: connection, size: 28)
                                .overlay {
                                    Circle().stroke(.white, lineWidth: 2)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .contentMargins(.horizontal, 0)
                .padding(.top, 2)
            }
        }
        .padding(.top, 4)
    }
}

struct MemoryMediaSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Binding var selectedPhotoIndex: Int?
    @Binding var showPhotoViewer: Bool
    @Binding var playingVideoURL: URL?
    let onAddPlaylist: () -> Void
    let onAddPeople: () -> Void

    @State private var selectedSection: MediaSection = .photos
    @State private var showAddPhotosPicker: Bool = false
    @State private var selectedPhotosItems: [PhotosPickerItem] = []
    @State private var isImporting: Bool = false

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: CLLocationCoordinate2D())
    }

    enum MediaSection: String, CaseIterable {
        case photos = "Photos"
        case videos = "Videos"
        case playlist = "Playlist"
        case comments = "Comments"
        case people = "People"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(memory.title)
                        .font(.title3.weight(.bold))
                    Text(memory.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MediaSection.allCases, id: \.self) { section in
                            Button {
                                withAnimation(.spring(duration: 0.3)) {
                                    selectedSection = section
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: iconFor(section))
                                        .font(.caption2)
                                    Text(section.rawValue)
                                        .font(.subheadline.weight(.medium))
                                    if let count = badgeCount(for: section), count > 0 {
                                        Text("\(count)")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(
                                                selectedSection == section
                                                    ? Color(.systemBackground).opacity(0.3)
                                                    : Color(.tertiarySystemFill),
                                                in: Capsule()
                                            )
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    selectedSection == section
                                        ? AnyShapeStyle(Color.primary)
                                        : AnyShapeStyle(Color(.tertiarySystemFill))
                                    , in: Capsule()
                                )
                                .foregroundStyle(selectedSection == section ? Color(.systemBackground) : .primary)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .contentMargins(.horizontal, 0)

                switch selectedSection {
                case .photos:
                    photosSection
                case .videos:
                    videosSection
                case .playlist:
                    playlistSection
                case .comments:
                    commentsSection
                case .people:
                    peopleSection
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .photosPicker(
            isPresented: $showAddPhotosPicker,
            selection: $selectedPhotosItems,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos])
        )
        .onChange(of: selectedPhotosItems) { _, items in
            guard !items.isEmpty else { return }
            let captured = items
            selectedPhotosItems = []
            Task { await importPickedItems(captured) }
        }
        .sheet(isPresented: $showPhotoViewer) {
            if let index = selectedPhotoIndex {
                PhotoViewerSheet(photoURLs: memory.photoURLs, initialIndex: index)
            }
        }
        .fullScreenCover(item: $playingVideoURL) { url in
            VideoPlayerView(url: url)
        }
    }

    private func importPickedItems(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false }

        for item in items {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }

            if isVideo {
                guard let urlString = MediaStore.saveVideo(data), let url = URL(string: urlString) else { continue }
                let thumbnail = await MediaStore.generateThumbnail(for: url)
                let duration = await MediaStore.durationString(for: url)
                let video = VideoAttachment(
                    thumbnailURL: thumbnail ?? "",
                    title: "Video",
                    duration: duration,
                    videoURL: urlString
                )
                await viewModel.addVideo(to: memoryID, video: video)
            } else {
                guard let urlString = MediaStore.saveImage(data) else { continue }
                await viewModel.addPhotoURL(to: memoryID, url: urlString)
            }
        }
    }

    private func iconFor(_ section: MediaSection) -> String {
        switch section {
        case .photos: return "photo.fill"
        case .videos: return "video.fill"
        case .playlist: return "music.note.list"
        case .comments: return "bubble.left.fill"
        case .people: return "person.2.fill"
        }
    }

    private func badgeCount(for section: MediaSection) -> Int? {
        switch section {
        case .photos: return memory.photoURLs.count
        case .videos: return memory.videos.count
        case .playlist: return memory.playlist != nil ? 1 : nil
        case .comments: return memory.comments.count
        case .people: return memory.connections.count
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(memory.photoURLs.count) Photos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button {
                    showAddPhotosPicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 20)

            let columns = [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4)
            ]

            LazyVGrid(columns: columns, spacing: 4) {
                Button {
                    showAddPhotosPicker = true
                } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                                Text("Add")
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                }

                ForEach(Array(memory.photoURLs.enumerated()), id: \.offset) { index, url in
                    Button {
                        selectedPhotoIndex = index
                        showPhotoViewer = true
                    } label: {
                        Color(.secondarySystemBackground)
                            .aspectRatio(1, contentMode: .fill)
                            .overlay {
                                MediaImageView(urlString: url)
                                    .allowsHitTesting(false)
                            }
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.removePhotoURL(from: memoryID, url: url)
                        } label: {
                            Label("Delete Photo", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(memory.videos.count) Videos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddPhotosPicker = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 20)

            if memory.videos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No videos yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        showAddPhotosPicker = true
                    } label: {
                        Text("Add Video")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Button {
                            showAddPhotosPicker = true
                        } label: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 180, height: 120)
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title2)
                                            .symbolRenderingMode(.hierarchical)
                                        Text("Add Video")
                                            .font(.caption.weight(.medium))
                                    }
                                    .foregroundStyle(.secondary)
                                }
                        }

                        ForEach(memory.videos) { video in
                            Button {
                                if let urlString = video.videoURL, let url = URL(string: urlString) {
                                    playingVideoURL = url
                                }
                            } label: {
                                VideoThumbnailCard(video: video)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.removeVideo(from: memoryID, video: video)
                                } label: {
                                    Label("Delete Video", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .contentMargins(.horizontal, 0)
            }
        }
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let playlist = memory.playlist {
                HStack(spacing: 12) {
                    Color(.tertiarySystemBackground)
                        .frame(width: 56, height: 56)
                        .overlay {
                            if let url = playlist.coverURL {
                                AsyncImage(url: URL(string: url)) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .allowsHitTesting(false)
                                    }
                                }
                            } else {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(.rect(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(playlist.name)
                            .font(.headline)
                        HStack(spacing: 4) {
                            Image(systemName: playlist.source == .spotify ? "antenna.radiowaves.left.and.right" : "music.note")
                                .font(.caption2)
                            Text(playlist.source.rawValue)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        Text("\(playlist.tracks.count) tracks")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if playlist.externalURL != nil {
                        Button {
                            if let urlString = playlist.externalURL, let url = URL(string: urlString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    playlist.source == .spotify
                                        ? Color.green
                                        : Color.pink
                                    , in: Capsule()
                                )
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .contextMenu {
                    Button {
                        onAddPlaylist()
                    } label: {
                        Label("Change Playlist", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        viewModel.removePlaylist(from: memoryID)
                    } label: {
                        Label("Remove Playlist", systemImage: "trash")
                    }
                }

                Divider()
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .frame(width: 20)

                            if let art = track.albumArtURL {
                                Color(.tertiarySystemBackground)
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        AsyncImage(url: URL(string: art)) { phase in
                                            if let image = phase.image {
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .allowsHitTesting(false)
                                            }
                                        }
                                    }
                                    .clipShape(.rect(cornerRadius: 6))
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.tertiarySystemFill))
                                    .frame(width: 40, height: 40)
                                    .overlay {
                                        Image(systemName: "music.note")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if !track.duration.isEmpty {
                                Text(track.duration)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 20)

                        if index < playlist.tracks.count - 1 {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No playlist linked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Add a Spotify or Apple Music playlist to this memory")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Button {
                        onAddPlaylist()
                    } label: {
                        Label("Link Playlist", systemImage: "link.badge.plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(memory.comments.count) Comments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)

            if memory.comments.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No comments yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Be the first to drop a comment on this memory")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(memory.comments) { comment in
                    CommentBubbleView(comment: comment)
                        .padding(.horizontal, 20)
                }
            }

            CommentInputView(memoryID: memoryID, viewModel: viewModel)
                .padding(.horizontal, 20)
                .padding(.top, 4)
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(memory.connections.count) People")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onAddPeople()
                } label: {
                    Label("Add", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(.horizontal, 20)

            if memory.connections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No people added")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        onAddPeople()
                    } label: {
                        Label("Add People", systemImage: "person.badge.plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(memory.connections) { connection in
                    HStack(spacing: 12) {
                        ConnectionAvatarView(connection: connection, size: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(connection.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text("@\(connection.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            viewModel.removeConnection(from: memoryID, connection: connection)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

struct CommentBubbleView: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String(comment.username.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                Text(comment.username)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(comment.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(comment.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct CommentInputView: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @State private var commentText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 32, height: 32)
                .overlay {
                    Text(String((viewModel.currentUsername ?? "You").prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

            HStack(spacing: 8) {
                TextField("Add a comment...", text: $commentText, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...3)
                    .focused($isFocused)

                if !commentText.isEmpty {
                    Button {
                        let text = commentText
                        commentText = ""
                        isFocused = false
                        Task { await viewModel.addComment(to: memoryID, text: text) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemFill), in: Capsule())
        }
    }
}

struct AddPeopleSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var identifier: String = ""
    @State private var isSharing = false
    @State private var feedback: ShareFeedback?
    @FocusState private var isFieldFocused: Bool

    private struct ShareFeedback: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
    }

    private var memory: Memory {
        viewModel.memoryByID(memoryID) ?? Memory(title: "", centerCoordinate: CLLocationCoordinate2D())
    }

    private var canShare: Bool {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && !isSharing
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "at")
                            .foregroundStyle(.secondary)
                        TextField("username or email", text: $identifier)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .focused($isFieldFocused)
                            .onSubmit { share() }

                        if isSharing {
                            ProgressView()
                        } else {
                            Button(action: share) {
                                Image(systemName: "paperplane.fill")
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canShare)
                        }
                    }
                    if let feedback {
                        Label(feedback.message, systemImage: feedback.isError ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(feedback.isError ? .red : .green)
                    }
                } header: {
                    Text("Share with a friend")
                } footer: {
                    Text("They'll see this memory in their Explore map and timeline once they sign in.")
                }

                Section("Shared with") {
                    if memory.connections.isEmpty {
                        Text("Not shared yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(memory.connections) { connection in
                            HStack(spacing: 12) {
                                ConnectionAvatarView(connection: connection, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(connection.displayName)
                                        .font(.subheadline.weight(.medium))
                                    Text("@\(connection.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    viewModel.removeConnection(from: memoryID, connection: connection)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func share() {
        let query = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !isSharing else { return }
        isSharing = true
        feedback = nil
        isFieldFocused = false
        Task {
            let result = await viewModel.shareMemory(memoryID: memoryID, identifier: query)
            isSharing = false
            switch result {
            case let .shared(name):
                feedback = ShareFeedback(message: "Shared with \(name)", isError: false)
                identifier = ""
            case .notFound:
                feedback = ShareFeedback(message: "No one found with that username or email", isError: true)
            case .alreadyShared:
                feedback = ShareFeedback(message: "Already shared with them", isError: true)
            case .selfShare:
                feedback = ShareFeedback(message: "That's you!", isError: true)
            case let .failure(message):
                feedback = ShareFeedback(message: message, isError: true)
            }
        }
    }
}

struct VideoThumbnailCard: View {
    let video: VideoAttachment

    var body: some View {
        Color(.secondarySystemBackground)
            .frame(width: 180, height: 120)
            .overlay {
                MediaImageView(urlString: video.thumbnailURL)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay(alignment: .center) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !video.duration.isEmpty {
                        Text(video.duration)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.5), in: Capsule())
                    }
                }
                .padding(8)
            }
    }
}

struct AddPlaylistSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var playlistURL: String = ""
    @State private var playlistName: String = ""
    @State private var selectedSource: PlaylistSource = .spotify
    @State private var showSpotifyBrowse: Bool = false

    private let spotifyGreen = Color(red: 0.11, green: 0.84, blue: 0.38)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Source", selection: $selectedSource) {
                    Text("Spotify").tag(PlaylistSource.spotify)
                    Text("Apple Music").tag(PlaylistSource.appleMusic)
                }
                .pickerStyle(.segmented)

                if selectedSource == .spotify && SpotifyConfig.isConfigured {
                    Button {
                        showSpotifyBrowse = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Browse my Spotify playlists")
                                .font(.body.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(spotifyGreen, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }

                    Text("Or paste a link manually below")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlist Name")
                        .font(.subheadline.weight(.medium))

                    TextField("My Playlist", text: $playlistName)
                        .padding(12)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlist Link")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 10) {
                        Image(systemName: selectedSource == .spotify ? "antenna.radiowaves.left.and.right" : "music.note")
                            .foregroundStyle(selectedSource == .spotify ? .green : .pink)
                            .frame(width: 24)

                        TextField("Paste \(selectedSource.rawValue) link...", text: $playlistURL)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }

                Spacer()

                Button {
                    let playlist = PlaylistAttachment(
                        name: playlistName.isEmpty ? "My Playlist" : playlistName,
                        source: selectedSource,
                        externalURL: playlistURL.isEmpty ? nil : playlistURL
                    )
                    viewModel.setPlaylist(for: memoryID, playlist: playlist)
                    dismiss()
                } label: {
                    Text("Link Playlist")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            selectedSource == .spotify ? Color.green : Color.pink,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(.white)
                }
                .disabled(playlistURL.isEmpty && playlistName.isEmpty)
                .opacity((playlistURL.isEmpty && playlistName.isEmpty) ? 0.5 : 1)
            }
            .padding(20)
            .navigationTitle("Link Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showSpotifyBrowse) {
                SpotifyBrowseView(memoryID: memoryID, viewModel: viewModel) {
                    dismiss()
                }
            }
        }
    }
}

struct PhotoPinView: View {
    let imageURL: String
    let title: String

    var body: some View {
        VStack(spacing: 2) {
            Color(.secondarySystemBackground)
                .frame(width: 72, height: 72)
                .overlay {
                    MediaImageView(urlString: imageURL)
                        .allowsHitTesting(false)
                }
                .clipShape(.rect(cornerRadius: 8))
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(180))
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
    }
}

struct SmallPinView: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.red, .red.opacity(0.6)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 8
                )
            )
            .frame(width: 16, height: 16)
            .overlay {
                Circle()
                    .stroke(.white, lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.3), radius: 4)
    }
}

struct MusicCardView: View {
    let music: MusicAttachment

    var body: some View {
        HStack(spacing: 12) {
            Color(.tertiarySystemBackground)
                .frame(width: 48, height: 48)
                .overlay {
                    if let url = music.albumArtURL {
                        AsyncImage(url: URL(string: url)) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .allowsHitTesting(false)
                            }
                        }
                    } else {
                        Image(systemName: "music.note")
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(music.songTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.artist)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.75))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message.time)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(message.username + ":")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)

            Text(message.message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }
}

struct PhotoViewerSheet: View {
    let photoURLs: [String]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int

    init(photoURLs: [String], initialIndex: Int) {
        self.photoURLs = photoURLs
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $currentIndex) {
                ForEach(Array(photoURLs.enumerated()), id: \.offset) { index, url in
                    Color.clear
                        .overlay {
                            MediaImageView(urlString: url, contentMode: .fit)
                        }
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

struct VideoPlayerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .onDisappear { player.pause() }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
    }
}
