import SwiftUI
import MapKit
import PhotosUI

struct MemoryRoomView: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss
    @State private var mapPosition: MapCameraPosition
    @State private var selectedPhotoIndex: Int?
    @State private var showPhotoViewer: Bool = false
    @State private var selectedDetent: PresentationDetent = .fraction(0.45)
    @State private var showMediaSheet: Bool = true
    @State private var showAddPhotosPicker: Bool = false
    @State private var showAddPlaylistSheet: Bool = false
    @State private var selectedPhotosItems: [PhotosPickerItem] = []

    init(memory: Memory) {
        self.memory = memory
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(
            center: memory.centerCoordinate,
            span: MKCoordinateSpan(latitudeDelta: memory.spanDelta, longitudeDelta: memory.spanDelta)
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
                memory: memory,
                onPhotoTap: { index in
                    selectedPhotoIndex = index
                    showPhotoViewer = true
                },
                onAddPhotos: {
                    showAddPhotosPicker = true
                },
                onAddPlaylist: {
                    showAddPlaylistSheet = true
                }
            )
            .presentationDetents([.fraction(0.15), .fraction(0.45), .large], selection: $selectedDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
            .presentationCornerRadius(24)
            .presentationContentInteraction(.scrolls)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showPhotoViewer) {
            if let index = selectedPhotoIndex {
                PhotoViewerSheet(photoURLs: memory.photoURLs, initialIndex: index)
            }
        }
        .photosPicker(isPresented: $showAddPhotosPicker, selection: $selectedPhotosItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
        .sheet(isPresented: $showAddPlaylistSheet) {
            AddPlaylistSheet()
                .presentationDetents([.medium])
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

                Button {
                } label: {
                    Image(systemName: "square.and.arrow.up")
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
        }
        .padding(.top, 4)
    }
}

struct MemoryMediaSheet: View {
    let memory: Memory
    let onPhotoTap: (Int) -> Void
    let onAddPhotos: () -> Void
    let onAddPlaylist: () -> Void

    @State private var selectedSection: MediaSection = .photos

    enum MediaSection: String, CaseIterable {
        case photos = "Photos"
        case videos = "Videos"
        case playlist = "Playlist"
        case chat = "Chat Log"
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
                case .chat:
                    chatSection
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    private func iconFor(_ section: MediaSection) -> String {
        switch section {
        case .photos: return "photo.fill"
        case .videos: return "video.fill"
        case .playlist: return "music.note.list"
        case .chat: return "bubble.left.and.bubble.right.fill"
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(memory.photoURLs.count) Photos")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onAddPhotos()
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
                    onAddPhotos()
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
                        onPhotoTap(index)
                    } label: {
                        Color(.secondarySystemBackground)
                            .aspectRatio(1, contentMode: .fill)
                            .overlay {
                                AsyncImage(url: URL(string: url)) { phase in
                                    if let image = phase.image {
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .allowsHitTesting(false)
                                    } else if phase.error != nil {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.tertiary)
                                    } else {
                                        ProgressView()
                                    }
                                }
                            }
                            .clipShape(.rect(cornerRadius: 8))
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
                    onAddPhotos()
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
                        onAddPhotos()
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
                            onAddPhotos()
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
                            VideoThumbnailCard(video: video)
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

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(memory.chatLog.count) Messages")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            if memory.chatLog.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No chat messages")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(memory.chatLog) { message in
                    ChatBubbleView(message: message)
                        .padding(.horizontal, 20)
                }
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
                AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
                }
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
    @Environment(\.dismiss) private var dismiss
    @State private var playlistURL: String = ""
    @State private var selectedSource: PlaylistSource = .spotify

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Source", selection: $selectedSource) {
                    Text("Spotify").tag(PlaylistSource.spotify)
                    Text("Apple Music").tag(PlaylistSource.appleMusic)
                }
                .pickerStyle(.segmented)

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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Or search for a playlist")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("Search \(selectedSource.rawValue)...")
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }

                Spacer()

                Button {
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
                .disabled(playlistURL.isEmpty)
                .opacity(playlistURL.isEmpty ? 0.5 : 1)
            }
            .padding(20)
            .navigationTitle("Link Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
                    AsyncImage(url: URL(string: imageURL)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        } else if phase.error != nil {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
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
                            AsyncImage(url: URL(string: url)) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if phase.error != nil {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                }
                            }
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
