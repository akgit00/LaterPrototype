import Foundation
import CoreLocation
import SwiftUI
import MapKit

@Observable
final class LaterViewModel {
    var memories: [Memory] = []
    var selectedMemory: Memory?
    var globalPins: [MemoryPin] = []
    var timelineProgress: Double = 0.0
    var selectedTab: Tab = .explore

    var allConnections: [Connection] = []

    /// Sync / cloud state.
    var isSyncing = false
    var syncError: String?

    /// The signed-in user's id; nil when offline / unauthenticated.
    private(set) var currentUserID: String?
    private var currentEmail: String = ""
    private var currentDisplayName: String?
    /// Memory ids owned by the current user (vs shared with them by friends).
    private(set) var ownedMemoryIDs: Set<UUID> = []

    private let lastUserKey = "cloud_last_user_id"

    enum Tab: String {
        case explore
        case timeCapsules
        case profile
    }

    /// Outcome of attempting to share a memory with a friend.
    enum ShareResult {
        case shared(displayName: String)
        case notFound
        case alreadyShared
        case selfShare
        case failure(String)
    }

    init() {
        if let stored = MemoryStore.load() {
            memories = stored
            rebuildGlobalPins()
        }
    }

    // MARK: - Cloud configuration & sync

    /// Associates the view model with the signed-in account. If the account
    /// changed since the last session, the local cache is cleared so one user
    /// never sees another's cached memories.
    func configure(userID: String, email: String, displayName: String?) {
        currentEmail = email
        currentDisplayName = displayName

        let previous = UserDefaults.standard.string(forKey: lastUserKey)
        if previous != userID {
            memories = []
            ownedMemoryIDs = []
            MemoryStore.save([])
            rebuildGlobalPins()
            UserDefaults.standard.set(userID, forKey: lastUserKey)
        }
        currentUserID = userID
    }

    /// Pushes any local-only memories to the cloud, then pulls everything the
    /// user can see (their own plus memories shared with them).
    @MainActor
    func sync() async {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        await CloudMemoryService.ensureProfile(userID: userID, email: currentEmail, displayName: currentDisplayName)

        // Migrate / push local memories (all locally-created memories are mine).
        for memory in memories {
            let uploaded = await CloudMemoryService.uploadingLocalMedia(in: memory, userID: userID)
            if let index = memories.firstIndex(where: { $0.id == uploaded.id }) {
                memories[index] = uploaded
            }
            try? await CloudMemoryService.upsertMemory(uploaded, ownerID: userID)
        }
        persist()

        // Pull the full set the server says we can see.
        do {
            let rows = try await CloudMemoryService.fetchMemories()
            ownedMemoryIDs = Set(rows.filter { $0.owner_id == userID }.map { $0.id })
            memories = rows
                .map { $0.payload }
                .sorted { $0.date > $1.date }
            rebuildGlobalPins()
            persist()
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func isOwned(_ memoryID: UUID) -> Bool {
        currentUserID != nil && ownedMemoryIDs.contains(memoryID)
    }

    /// Uploads any local media then upserts an owned memory to the cloud.
    @MainActor
    private func pushMemory(_ memoryID: UUID) async {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        guard isOwned(memoryID), let memory = memoryByID(memoryID) else { return }
        let uploaded = await CloudMemoryService.uploadingLocalMedia(in: memory, userID: userID)
        if let index = memories.firstIndex(where: { $0.id == uploaded.id }) {
            memories[index] = uploaded
            rebuildGlobalPins()
            persist()
        }
        try? await CloudMemoryService.upsertMemory(uploaded, ownerID: userID)
    }

    // MARK: - Mutations

    private func persist() {
        MemoryStore.save(memories)
    }

    func addMemory(_ memory: Memory) {
        memories.insert(memory, at: 0)
        ownedMemoryIDs.insert(memory.id)
        rebuildGlobalPins()
        persist()
        Task { await pushMemory(memory.id) }
    }

    func updateMemory(_ memory: Memory) {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[index] = memory
        rebuildGlobalPins()
        persist()
        Task { await pushMemory(memory.id) }
    }

    func deleteMemory(_ id: UUID) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        let memory = memories[index]
        for url in memory.photoURLs {
            MediaStore.deleteFile(at: url)
        }
        for video in memory.videos {
            if let videoURL = video.videoURL {
                MediaStore.deleteFile(at: videoURL)
            }
            MediaStore.deleteFile(at: video.thumbnailURL)
        }
        let wasOwned = isOwned(id)
        memories.remove(at: index)
        ownedMemoryIDs.remove(id)
        if selectedMemory?.id == id {
            selectedMemory = nil
        }
        rebuildGlobalPins()
        persist()
        if wasOwned {
            Task { try? await CloudMemoryService.deleteMemory(id: id) }
        }
    }

    func removePhotoURL(from memoryID: UUID, url: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].photoURLs.removeAll { $0 == url }
        memories[index].pins.removeAll { $0.imageURL == url }
        MediaStore.deleteFile(at: url)
        rebuildGlobalPins()
        persist()
        Task { await pushMemory(memoryID) }
    }

    func removeVideo(from memoryID: UUID, video: VideoAttachment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].videos.removeAll { $0.id == video.id }
        if let videoURL = video.videoURL {
            MediaStore.deleteFile(at: videoURL)
        }
        MediaStore.deleteFile(at: video.thumbnailURL)
        persist()
        Task { await pushMemory(memoryID) }
    }

    func addComment(to memoryID: UUID, comment: Comment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].comments.append(comment)
        persist()
        Task { await pushMemory(memoryID) }
    }

    func addPhotoURL(to memoryID: UUID, url: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].photoURLs.append(url)
        persist()
        Task { await pushMemory(memoryID) }
    }

    func addVideo(to memoryID: UUID, video: VideoAttachment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].videos.append(video)
        persist()
        Task { await pushMemory(memoryID) }
    }

    func setPlaylist(for memoryID: UUID, playlist: PlaylistAttachment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].playlist = playlist
        persist()
        Task { await pushMemory(memoryID) }
    }

    func addConnection(to memoryID: UUID, connection: Connection) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        if !memories[index].connections.contains(where: { $0.id == connection.id }) {
            memories[index].connections.append(connection)
            if !memories[index].creators.contains(connection.username) {
                memories[index].creators.append(connection.username)
            }
            persist()
        }
    }

    func removeConnection(from memoryID: UUID, connection: Connection) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].connections.removeAll { $0.id == connection.id }
        memories[index].creators.removeAll { $0 == connection.username }
        persist()
        Task {
            try? await CloudMemoryService.unshareMemory(memoryID: memoryID, sharedWith: connection.id.uuidString)
            await pushMemory(memoryID)
        }
    }

    // MARK: - Sharing

    /// Shares an owned memory with a friend looked up by `@username` or email.
    @MainActor
    func shareMemory(memoryID: UUID, identifier: String) async -> ShareResult {
        guard let userID = currentUserID, SupabaseREST.hasSession else {
            return .failure("You need to be signed in to share.")
        }
        guard isOwned(memoryID) else {
            return .failure("You can only share memories you created.")
        }

        do {
            guard let profile = try await CloudMemoryService.findProfile(identifier: identifier) else {
                return .notFound
            }
            if profile.id == userID { return .selfShare }

            guard let friendUUID = UUID(uuidString: profile.id) else {
                return .failure("Couldn't read that account.")
            }
            if memoryByID(memoryID)?.connections.contains(where: { $0.id == friendUUID }) == true {
                return .alreadyShared
            }

            let name = profile.display_name?.isEmpty == false ? profile.display_name! : profile.username
            let connection = Connection(
                id: friendUUID,
                username: profile.username,
                displayName: name,
                avatarColor: ConnectionColor.allCases.randomElement() ?? .blue
            )
            addConnection(to: memoryID, connection: connection)

            try await CloudMemoryService.shareMemory(memoryID: memoryID, ownerID: userID, sharedWith: profile.id)
            await pushMemory(memoryID)
            return .shared(displayName: name)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - Lookups

    func memory(for pin: MemoryPin) -> Memory? {
        memories.first { memory in
            memory.pins.contains { $0.id == pin.id }
        }
    }

    func memoryByID(_ id: UUID) -> Memory? {
        memories.first { $0.id == id }
    }

    private func rebuildGlobalPins() {
        globalPins = memories.flatMap { memory in
            memory.pins.map { pin in
                MemoryPin(
                    id: pin.id,
                    coordinate: pin.coordinate,
                    title: memory.title,
                    date: pin.date,
                    imageURL: pin.imageURL,
                    intensity: pin.intensity
                )
            }
        }
    }
}
