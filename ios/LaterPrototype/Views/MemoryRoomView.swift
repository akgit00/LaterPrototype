import SwiftUI
import MapKit

struct MemoryRoomView: View {
    let memory: Memory
    @Environment(\.dismiss) private var dismiss
    @State private var mapPosition: MapCameraPosition
    @State private var selectedPhotoIndex: Int?
    @State private var showPhotoViewer: Bool = false

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

            VStack(spacing: 0) {
                headerOverlay
                Spacer()
                bottomPanel
            }
        }
        .sheet(isPresented: $showPhotoViewer) {
            if let index = selectedPhotoIndex {
                PhotoViewerSheet(photoURLs: memory.photoURLs, initialIndex: index)
            }
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

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            if let music = memory.music {
                MusicCardView(music: music)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 36, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(memory.chatLog) { message in
                            ChatBubbleView(message: message)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: 160)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThickMaterial)
                    .ignoresSafeArea(edges: .bottom)
            )
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
