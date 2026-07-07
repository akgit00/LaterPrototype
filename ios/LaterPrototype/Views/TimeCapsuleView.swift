import SwiftUI
import PhotosUI
import AVKit

struct TimeCapsuleView: View {
    @State private var capsules: [TimeCapsule] = []
    @State private var showCreateSheet: Bool = false
    @State private var openedCapsule: TimeCapsule?

    var body: some View {
        NavigationStack {
            Group {
                if capsules.isEmpty {
                    CapsuleEmptyState(onCreate: { showCreateSheet = true })
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(capsules) { capsule in
                                Button {
                                    if capsule.isDelivered {
                                        openedCapsule = capsule
                                    }
                                } label: {
                                    TimeCapsuleCard(capsule: capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Time Capsules")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateCapsuleSheet { newCapsule in
                    capsules.insert(newCapsule, at: 0)
                    CapsuleStore.save(capsules)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $openedCapsule) { capsule in
                CapsuleDetailSheet(capsule: capsule)
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            if let stored = CapsuleStore.load() {
                capsules = stored
            }
        }
    }
}

struct CapsuleEmptyState: View {
    let onCreate: () -> Void
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulse ? 1.1 : 0.95)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 8) {
                Text("No capsules yet")
                    .font(.title2.weight(.bold))
                Text("Seal a message to your future self or a friend. We'll keep it locked until the day you choose.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                onCreate()
            } label: {
                Label("Create your first capsule", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.blue, in: Capsule())
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

nonisolated struct TimeCapsule: Identifiable, Sendable, Codable {
    let id: UUID
    let title: String
    let message: String
    let recipient: String
    let deliveryDate: Date
    let createdDate: Date
    /// Sealed-in photos (local file URLs).
    let photoURLs: [String]
    /// Sealed-in videos.
    let videos: [VideoAttachment]
    /// An optional song / playlist link sealed with the capsule.
    let songLink: String?

    /// A capsule is delivered once its delivery date has arrived.
    var isDelivered: Bool {
        deliveryDate <= Date()
    }

    /// Number of attachments sealed inside (shown while locked).
    var attachmentCount: Int {
        photoURLs.count + videos.count + (songLink == nil ? 0 : 1)
    }

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        recipient: String,
        deliveryDate: Date,
        createdDate: Date,
        photoURLs: [String] = [],
        videos: [VideoAttachment] = [],
        songLink: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.recipient = recipient
        self.deliveryDate = deliveryDate
        self.createdDate = createdDate
        self.photoURLs = photoURLs
        self.videos = videos
        self.songLink = songLink
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, message, recipient, deliveryDate, createdDate
        case photoURLs, videos, songLink
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        recipient = try container.decode(String.self, forKey: .recipient)
        deliveryDate = try container.decode(Date.self, forKey: .deliveryDate)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        photoURLs = try container.decodeIfPresent([String].self, forKey: .photoURLs) ?? []
        videos = try container.decodeIfPresent([VideoAttachment].self, forKey: .videos) ?? []
        songLink = try container.decodeIfPresent(String.self, forKey: .songLink)
    }
}

struct TimeCapsuleCard: View {
    let capsule: TimeCapsule

    private var daysUntilDelivery: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: capsule.deliveryDate).day ?? 0
    }

    private var progress: Double {
        let total = capsule.deliveryDate.timeIntervalSince(capsule.createdDate)
        let elapsed = Date().timeIntervalSince(capsule.createdDate)
        guard total > 0 else { return 1.0 }
        return min(max(elapsed / total, 0), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(capsule.title)
                        .font(.headline)

                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text("To: \(capsule.recipient)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: capsule.isDelivered ? "envelope.open.fill" : "lock.fill")
                    .font(.title3)
                    .foregroundStyle(capsule.isDelivered ? .green : .orange)
                    .symbolEffect(.pulse, isActive: !capsule.isDelivered)
            }

            Text(capsule.isDelivered ? capsule.message : String(repeating: "•", count: min(capsule.message.count, 40)))
                .font(.subheadline)
                .foregroundStyle(capsule.isDelivered ? .primary : .tertiary)
                .lineLimit(2)

            if capsule.attachmentCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                    Text("\(capsule.attachmentCount) \(capsule.attachmentCount == 1 ? "attachment" : "attachments") sealed inside")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .tint(progress >= 1.0 ? .green : .blue)

                HStack {
                    Text("Opens \(capsule.deliveryDate, style: .date)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if daysUntilDelivery > 0 {
                        Text("\(daysUntilDelivery) days left")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Text("Ready to open")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct CreateCapsuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSeal: (TimeCapsule) -> Void
    @State private var title: String = ""
    @State private var message: String = ""
    @State private var recipient: String = ""
    @State private var deliveryDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    @State private var songLink: String = ""
    @State private var photoURLs: [String] = []
    @State private var videos: [VideoAttachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting: Bool = false

    private func seal() {
        let trimmedRecipient = recipient.trimmingCharacters(in: .whitespaces)
        let trimmedLink = songLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let capsule = TimeCapsule(
            title: title.trimmingCharacters(in: .whitespaces),
            message: message,
            recipient: trimmedRecipient.isEmpty ? "Future me" : trimmedRecipient,
            deliveryDate: deliveryDate,
            createdDate: Date(),
            photoURLs: photoURLs,
            videos: videos,
            songLink: trimmedLink.isEmpty ? nil : trimmedLink
        )
        onSeal(capsule)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Capsule Details") {
                    TextField("Title", text: $title)
                    TextField("Recipient", text: $recipient)
                    DatePicker("Delivery Date", selection: $deliveryDate, in: Date()..., displayedComponents: .date)
                }

                Section("Message") {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                }

                Section {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 10,
                        matching: .any(of: [.images, .videos])
                    ) {
                        HStack {
                            Label("Add Photos & Videos", systemImage: "photo.badge.plus")
                            Spacer()
                            if isImporting {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }

                    if !photoURLs.isEmpty || !videos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(photoURLs.enumerated()), id: \.offset) { index, url in
                                    Color(.secondarySystemBackground)
                                        .frame(width: 64, height: 64)
                                        .overlay {
                                            MediaImageView(urlString: url)
                                                .allowsHitTesting(false)
                                        }
                                        .clipShape(.rect(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                MediaStore.deleteFile(at: url)
                                                photoURLs.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .padding(3)
                                        }
                                }

                                ForEach(videos) { video in
                                    Color(.secondarySystemBackground)
                                        .frame(width: 64, height: 64)
                                        .overlay {
                                            MediaImageView(urlString: video.thumbnailURL)
                                                .allowsHitTesting(false)
                                        }
                                        .clipShape(.rect(cornerRadius: 8))
                                        .overlay(alignment: .center) {
                                            Image(systemName: "play.circle.fill")
                                                .foregroundStyle(.white)
                                                .shadow(radius: 2)
                                        }
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                removeVideo(video)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .padding(3)
                                        }
                                }
                            }
                        }
                    }

                    TextField("Song or playlist link (optional)", text: $songLink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Attachments")
                } footer: {
                    Text("Photos, videos, and a song stay sealed until the capsule opens.")
                }
            }
            .navigationTitle("New Time Capsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Clean up any imported files if the capsule isn't sealed.
                        for url in photoURLs { MediaStore.deleteFile(at: url) }
                        for video in videos { removeVideoFiles(video) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Seal") { seal() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || message.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)
                }
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                let captured = items
                pickerItems = []
                Task { await importPicked(captured) }
            }
        }
    }

    private func removeVideo(_ video: VideoAttachment) {
        removeVideoFiles(video)
        videos.removeAll { $0.id == video.id }
    }

    private func removeVideoFiles(_ video: VideoAttachment) {
        if let videoURL = video.videoURL {
            MediaStore.deleteFile(at: videoURL)
        }
        MediaStore.deleteFile(at: video.thumbnailURL)
    }

    private func importPicked(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false }

        for item in items {
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }

            if isVideo {
                guard let urlString = MediaStore.saveVideo(data), let url = URL(string: urlString) else { continue }
                let thumbnail = await MediaStore.generateThumbnail(for: url)
                let duration = await MediaStore.durationString(for: url)
                videos.append(
                    VideoAttachment(
                        thumbnailURL: thumbnail ?? "",
                        title: "Video",
                        duration: duration,
                        videoURL: urlString
                    )
                )
            } else if let urlString = MediaStore.saveImage(data) {
                photoURLs.append(urlString)
            }
        }
    }
}

struct CapsuleDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let capsule: TimeCapsule
    @State private var photoViewer: PhotoViewerSelection?
    @State private var playingVideoURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope.open.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(capsule.title)
                                .font(.title3.weight(.bold))
                            Text("To: \(capsule.recipient)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(capsule.message)
                        .font(.body)

                    if !capsule.photoURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PHOTOS")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            let columns = [
                                GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4),
                                GridItem(.flexible(), spacing: 4)
                            ]
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(Array(capsule.photoURLs.enumerated()), id: \.offset) { index, url in
                                    Button {
                                        photoViewer = PhotoViewerSelection(index: index)
                                    } label: {
                                        Color(.secondarySystemBackground)
                                            .aspectRatio(1, contentMode: .fill)
                                            .overlay {
                                                MediaImageView(urlString: url)
                                                    .allowsHitTesting(false)
                                            }
                                            .clipShape(.rect(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }

                    if !capsule.videos.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("VIDEOS")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(capsule.videos) { video in
                                        Button {
                                            if let urlString = video.videoURL, let url = URL(string: urlString) {
                                                playingVideoURL = url
                                            }
                                        } label: {
                                            VideoThumbnailCard(video: video)
                                        }
                                    }
                                }
                            }
                            .contentMargins(.horizontal, 0)
                        }
                    }

                    if let songLink = capsule.songLink, let url = URL(string: songLink) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("MUSIC")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.green)
                                    Text(songLink)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Label("Sealed \(capsule.createdDate, style: .date)", systemImage: "lock")
                        Spacer()
                        Label("Opened \(capsule.deliveryDate, style: .date)", systemImage: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Capsule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $photoViewer) { selection in
                PhotoViewerSheet(photoURLs: capsule.photoURLs, initialIndex: selection.index)
            }
            .fullScreenCover(item: $playingVideoURL) { url in
                VideoPlayerView(url: url)
            }
        }
    }
}
