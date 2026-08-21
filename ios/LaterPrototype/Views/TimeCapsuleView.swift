import SwiftUI
import PhotosUI
import AVKit

/// The two faces of the Capsules tab: capsules still waiting to unlock, and
/// the history of everything that has already opened.
private enum CapsuleSegment: Hashable {
    case sealed
    case history
}

struct TimeCapsuleView: View {
    let viewModel: LaterViewModel
    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    @State private var capsules: [TimeCapsule] = []
    @State private var showCreateSheet: Bool = false
    @State private var openedCapsule: TimeCapsule?
    @State private var isSyncing: Bool = false
    @State private var capsuleToDelete: TimeCapsule?
    @State private var lockedCapsule: TimeCapsule?
    @State private var hiddenIDs: Set<UUID> = []
    @State private var segment: CapsuleSegment = .sealed
    @State private var autoPickedSegmentForUserID: String?
    @State private var router = NotificationRouter.shared

    private var userID: String? { auth.user?.id }

    var body: some View {
        NavigationStack {
            Group {
                if capsules.isEmpty {
                    CapsuleEmptyState(onCreate: { showCreateSheet = true })
                } else {
                    VStack(spacing: 0) {
                        Picker("View", selection: $segment) {
                            Text("Sealed (\(sealedCapsules.count))").tag(CapsuleSegment.sealed)
                            Text("History (\(deliveredCapsules.count))").tag(CapsuleSegment.history)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 10)

                        if segment == .sealed && sealedCapsules.isEmpty {
                            ContentUnavailableView {
                                Label("Nothing sealed", systemImage: "lock.open")
                            } description: {
                                Text("Every capsule has unlocked. Seal a new one for a future day.")
                            } actions: {
                                Button("New Capsule") { showCreateSheet = true }
                            }
                        } else if segment == .history && deliveredCapsules.isEmpty {
                            ContentUnavailableView {
                                Label("No history yet", systemImage: "envelope.open")
                            } description: {
                                Text("When a capsule reaches its delivery date, it unlocks and lands here.")
                            }
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    if segment == .sealed {
                                        ForEach(sealedCapsules) { capsule in
                                            capsuleRow(capsule)
                                        }
                                    } else {
                                        ForEach(historyGroups, id: \.month) { group in
                                            VStack(alignment: .leading, spacing: 12) {
                                                Text(group.month.formatted(.dateTime.month(.wide).year()))
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(.secondary)
                                                    .textCase(.uppercase)
                                                    .padding(.leading, 4)

                                                ForEach(group.capsules) { capsule in
                                                    capsuleRow(capsule)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            }
                            .refreshable { await sync() }
                        }
                    }
                }
            }
            .navigationTitle("Time Capsules")
            .toolbar {
                if isSyncing {
                    ToolbarItem(placement: .topBarLeading) {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
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
                CreateCapsuleSheet(
                    friends: viewModel.allConnections,
                    currentUserID: userID,
                    currentUserName: senderDisplayName
                ) { newCapsule in
                    capsules.insert(newCapsule, at: 0)
                    segment = newCapsule.isDelivered ? .history : .sealed
                    persistLocal()
                    Task { await pushCapsule(newCapsule) }
                }
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
            }
            .sheet(item: $openedCapsule) { capsule in
                CapsuleDetailSheet(capsule: capsule, currentUserID: userID) {
                    deleteCapsule(capsule)
                }
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
            }
            .confirmationDialog(
                capsuleToDelete.map { "\($0.isReceived(by: userID) ? "Remove" : "Delete") \"\($0.title)\"?" } ?? "",
                isPresented: Binding(
                    get: { capsuleToDelete != nil },
                    set: { if !$0 { capsuleToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: capsuleToDelete
            ) { capsule in
                Button(capsule.isReceived(by: userID) ? "Remove Capsule" : "Delete Capsule", role: .destructive) {
                    deleteCapsule(capsule)
                }
                Button("Cancel", role: .cancel) {}
            } message: { capsule in
                Text(deleteWarning(for: capsule))
            }
            .confirmationDialog(
                lockedCapsule.map { "\"\($0.title)\" is still sealed" } ?? "",
                isPresented: Binding(
                    get: { lockedCapsule != nil },
                    set: { if !$0 { lockedCapsule = nil } }
                ),
                titleVisibility: .visible,
                presenting: lockedCapsule
            ) { capsule in
                Button("Delete Capsule", role: .destructive) {
                    deleteCapsule(capsule)
                }
                Button("Keep Sealed", role: .cancel) {}
            } message: { capsule in
                Text("It opens \(capsule.deliveryDate.formatted(date: .abbreviated, time: .omitted)). Deleting it now can't be undone.")
            }
        }
        .task(id: auth.user?.id) {
            loadLocal()
            consumeHistoryRequest()
            await sync()
        }
        // Re-check the cloud whenever the tab is opened or the app returns to
        // the foreground, so capsules that unlocked in the meantime (and were
        // announced by a push) appear immediately.
        .onAppear {
            Task { await sync() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await sync() }
        }
        // A tapped capsule-unlock notification requests the History segment,
        // where the freshly unlocked capsule now lives.
        .onChange(of: router.showCapsuleHistory) { _, requested in
            guard requested else { return }
            consumeHistoryRequest()
        }
    }

    /// Capsules still locked, ordered so the next one to open is on top.
    private var sealedCapsules: [TimeCapsule] {
        capsules.filter { !$0.isDelivered }.sorted { $0.deliveryDate < $1.deliveryDate }
    }

    /// Capsules whose delivery date has passed.
    private var deliveredCapsules: [TimeCapsule] {
        capsules.filter(\.isDelivered)
    }

    /// History timeline: unlocked capsules grouped by the month they opened,
    /// most recent month (and capsule) first.
    private var historyGroups: [(month: Date, capsules: [TimeCapsule])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: deliveredCapsules) { capsule in
            calendar.dateInterval(of: .month, for: capsule.deliveryDate)?.start ?? capsule.deliveryDate
        }
        return grouped
            .map { (month: $0.key, capsules: $0.value.sorted { $0.deliveryDate > $1.deliveryDate }) }
            .sorted { $0.month > $1.month }
    }

    /// A tappable capsule card with its delete context menu, shared by both segments.
    private func capsuleRow(_ capsule: TimeCapsule) -> some View {
        Button {
            if capsule.isDelivered {
                openedCapsule = capsule
            } else {
                lockedCapsule = capsule
            }
        } label: {
            TimeCapsuleCard(capsule: capsule, currentUserID: userID)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                capsuleToDelete = capsule
            } label: {
                Label(
                    capsule.isReceived(by: userID) ? "Remove Capsule" : "Delete Capsule",
                    systemImage: "trash"
                )
            }
        }
    }

    /// Jumps to the History segment when a capsule-unlock notification was
    /// tapped, so the freshly unlocked capsule is immediately visible.
    private func consumeHistoryRequest() {
        guard router.showCapsuleHistory else { return }
        router.showCapsuleHistory = false
        segment = .history
    }

    /// The name attached to sealed capsules so recipients know who they're from.
    private var senderDisplayName: String? {
        if let name = auth.user?.name, !name.isEmpty { return name }
        if let username = viewModel.currentUsername, !username.isEmpty { return "@\(username)" }
        return nil
    }

    /// Loads this user's cached capsules, adopting any from the legacy shared
    /// file (which is then deleted so other accounts can't see them).
    private func loadLocal() {
        guard let userID else {
            capsules = []
            hiddenIDs = []
            segment = .sealed
            autoPickedSegmentForUserID = nil
            return
        }
        hiddenIDs = CapsuleStore.loadHiddenIDs(userID: userID)
        var stored = CapsuleStore.load(userID: userID) ?? []
        let adopted = CapsuleStore.migrateLegacyCapsules(to: userID)
        if !adopted.isEmpty {
            stored.append(contentsOf: adopted)
        }
        capsules = stored
            .filter { !hiddenIDs.contains($0.id) }
            .sorted { $0.createdDate > $1.createdDate }
        // First look for this account: land on History when everything has
        // already unlocked, otherwise show what's still sealed.
        if autoPickedSegmentForUserID != userID {
            autoPickedSegmentForUserID = userID
            segment = capsules.isEmpty || capsules.contains { !$0.isDelivered } ? .sealed : .history
        }
        if !adopted.isEmpty {
            persistLocal()
        }
    }

    private func persistLocal() {
        guard let userID else { return }
        CapsuleStore.save(capsules, userID: userID)
    }

    /// Pulls capsules from the cloud (sealed by me + delivered to me), keeps
    /// any not-yet-uploaded local ones, and re-pushes those so they survive
    /// reinstalls and reach their recipients.
    private func sync() async {
        guard let userID, SupabaseREST.hasSession, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let rows = try await CapsuleService.fetchCapsules()
            let cloudIDs = Set(rows.map(\.id))

            // Merge in removals made on other devices, and forget hides whose
            // rows no longer exist (the capsule was fully deleted).
            if let remoteHides = try? await CapsuleService.fetchHiddenCapsuleIDs() {
                hiddenIDs.formUnion(remoteHides)
            }
            hiddenIDs = Set(hiddenIDs.filter { cloudIDs.contains($0) })
            CapsuleStore.saveHiddenIDs(hiddenIDs, userID: userID)

            let localOnly = capsules.filter {
                !cloudIDs.contains($0.id) && ($0.senderID == nil || $0.senderID == userID)
            }
            var merged = rows.filter { !hiddenIDs.contains($0.id) }.map(\.payload) + localOnly
            merged.sort { $0.createdDate > $1.createdDate }
            capsules = merged
            persistLocal()

            for capsule in localOnly {
                await pushCapsule(capsule)
            }
        } catch {
            // Offline is fine — the local cache still shows.
        }
    }

    /// Uploads a capsule's local media, then upserts the capsule row.
    private func pushCapsule(_ capsule: TimeCapsule) async {
        guard let userID, SupabaseREST.hasSession else { return }
        let uploaded = await CapsuleService.uploadingLocalMedia(in: capsule, userID: userID)
        if let index = capsules.firstIndex(where: { $0.id == uploaded.id }) {
            capsules[index] = uploaded
            persistLocal()
        }
        try? await CapsuleService.upsertCapsule(
            uploaded,
            senderID: uploaded.senderID ?? userID,
            recipientID: uploaded.recipientID ?? userID
        )
    }

    /// Explains what deleting the given capsule will do, based on the user's role.
    private func deleteWarning(for capsule: TimeCapsule) -> String {
        if capsule.isReceived(by: userID) {
            return "This removes the capsule from your list. \(capsule.senderName ?? "The sender") keeps their copy."
        }
        if let recipientID = capsule.recipientID, let senderID = capsule.senderID, recipientID != senderID {
            return "This permanently deletes the capsule for both you and \(capsule.recipient). This can't be undone."
        }
        return "This permanently deletes the capsule. This can't be undone."
    }

    /// Deletes a capsule the user sealed (removing the cloud row for everyone),
    /// or removes a received capsule from this user's list without touching
    /// the sender's copy. The id is remembered so a sync can't resurrect it.
    private func deleteCapsule(_ capsule: TimeCapsule) {
        guard let userID else { return }

        hiddenIDs.insert(capsule.id)
        CapsuleStore.saveHiddenIDs(hiddenIDs, userID: userID)

        withAnimation(.snappy) {
            capsules.removeAll { $0.id == capsule.id }
        }
        persistLocal()

        for url in capsule.photoURLs { MediaStore.deleteFile(at: url) }
        for video in capsule.videos {
            if let videoURL = video.videoURL { MediaStore.deleteFile(at: videoURL) }
            MediaStore.deleteFile(at: video.thumbnailURL)
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if capsule.isReceived(by: userID) {
            // Recipients can't delete the sender's row — record a synced hide.
            Task { try? await CapsuleService.hideCapsule(id: capsule.id, userID: userID) }
        } else {
            Task { try? await CapsuleService.deleteCapsule(id: capsule.id) }
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

struct TimeCapsuleCard: View {
    let capsule: TimeCapsule
    let currentUserID: String?

    private var isReceived: Bool {
        capsule.isReceived(by: currentUserID)
    }

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
                        Image(systemName: isReceived ? "gift.fill" : "person.fill")
                            .font(.caption2)
                        Text(isReceived ? "From: \(capsule.senderName ?? "A friend")" : "To: \(capsule.recipient)")
                            .font(.caption)
                    }
                    .foregroundStyle(isReceived ? AnyShapeStyle(.blue) : AnyShapeStyle(.secondary))
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
                    Text("\(capsule.isDelivered ? "Opened" : "Opens") \(capsule.deliveryDate, style: .date)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if capsule.isDelivered {
                        Text("Unlocked")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    } else if daysUntilDelivery > 0 {
                        Text("\(daysUntilDelivery) days left")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
                    } else {
                        Text("Opens today")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.blue)
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
    let friends: [Connection]
    let currentUserID: String?
    let currentUserName: String?
    let onSeal: (TimeCapsule) -> Void

    @State private var title: String = ""
    @State private var message: String = ""
    @State private var selectedFriend: Connection?
    @State private var friendSearch: String = ""
    @State private var deliveryDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
    @State private var songLink: String = ""
    @State private var photoURLs: [String] = []
    @State private var videos: [VideoAttachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting: Bool = false

    /// Friends filtered by the search text (all friends when it's empty).
    private var filteredFriends: [Connection] {
        let query = friendSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return friends }
        return friends.filter {
            $0.displayName.lowercased().contains(query)
                || $0.username.lowercased().contains(query)
        }
    }

    private func seal() {
        let trimmedLink = songLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let capsule = TimeCapsule(
            title: title.trimmingCharacters(in: .whitespaces),
            message: message,
            recipient: selectedFriend?.displayName ?? "Future me",
            deliveryDate: deliveryDate,
            createdDate: Date(),
            senderID: currentUserID,
            senderName: currentUserName,
            recipientID: selectedFriend?.id.uuidString.lowercased() ?? currentUserID,
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
                    DatePicker("Delivery Date", selection: $deliveryDate, in: Date()..., displayedComponents: .date)
                }

                Section {
                    Button {
                        selectedFriend = nil
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.clock.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 32)
                            Text("Future me")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedFriend == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    if !friends.isEmpty {
                        TextField("Search friends", text: $friendSearch)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        ForEach(filteredFriends) { friend in
                            Button {
                                selectedFriend = friend
                            } label: {
                                HStack(spacing: 10) {
                                    ConnectionAvatarView(connection: friend, size: 32)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(friend.displayName)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text("@\(friend.username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedFriend?.id == friend.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }

                        if filteredFriends.isEmpty {
                            Text("No friends match \"\(friendSearch)\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Deliver To")
                } footer: {
                    if friends.isEmpty {
                        Text("To send a capsule to a friend, add them from the Search tab first.")
                    } else {
                        Text("Capsules sent to a friend stay completely invisible to them until the delivery date.")
                    }
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
    let currentUserID: String?
    var onDelete: (() -> Void)? = nil
    @State private var photoViewer: PhotoViewerSelection?
    @State private var playingVideoURL: URL?
    @State private var showDeleteConfirm: Bool = false

    private var isReceived: Bool {
        capsule.isReceived(by: currentUserID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: isReceived ? "gift.fill" : "envelope.open.fill")
                            .font(.title2)
                            .foregroundStyle(isReceived ? .blue : .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(capsule.title)
                                .font(.title3.weight(.bold))
                            Text(isReceived ? "From: \(capsule.senderName ?? "A friend")" : "To: \(capsule.recipient)")
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
                                        photoViewer = PhotoViewerSelection(urls: capsule.photoURLs, index: index)
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
                if onDelete != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                isReceived ? "Remove this capsule?" : "Delete this capsule?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(isReceived ? "Remove Capsule" : "Delete Capsule", role: .destructive) {
                    dismiss()
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isReceived
                    ? "It disappears from your list; \(capsule.senderName ?? "the sender") keeps their copy."
                    : "This can't be undone.")
            }
            .sheet(item: $photoViewer) { selection in
                PhotoViewerSheet(photoURLs: selection.urls, initialIndex: selection.index, canSave: true)
            }
            .fullScreenCover(item: $playingVideoURL) { url in
                VideoPlayerView(url: url, canSave: true)
            }
        }
    }
}
