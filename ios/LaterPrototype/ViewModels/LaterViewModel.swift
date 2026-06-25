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

    /// Unread message count per friend (by connection id), used to drive the
    /// badges next to each conversation and the tab badge. Computed against a
    /// per-conversation last-read timestamp stored locally on this device.
    var unreadByFriend: [UUID: Int] = [:]

    /// Connection (friends) state.
    var incomingRequests: [FriendRequest] = []
    var outgoingRequests: [FriendRequest] = []
    var isLoadingConnections = false

    /// Sync / cloud state.
    var isSyncing = false
    var syncError: String?

    /// Surfaced to the comment UI when posting a comment fails, so the failure
    /// isn't silent. Cleared whenever a new comment attempt starts.
    var commentError: String?

    /// The signed-in user's id; nil when offline / unauthenticated.
    private(set) var currentUserID: String?
    /// The signed-in user's @username, resolved from their cloud profile.
    private(set) var currentUsername: String?
    private var currentEmail: String = ""
    private var currentDisplayName: String?
    /// Memory ids owned by the current user (vs shared with them by friends).
    private(set) var ownedMemoryIDs: Set<UUID> = []

    private let lastUserKey = "cloud_last_user_id"
    private let lastReadPrefix = "msg_last_read_"

    /// Optimistic comments that have been shown locally but not yet confirmed by
    /// the server, keyed by memory id. Kept so a background poll landing in the
    /// middle of a post never wipes a just-typed comment off screen.
    private var pendingComments: [UUID: [Comment]] = [:]

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

    /// A pending connection request paired with the other person's identity.
    struct FriendRequest: Identifiable {
        let rowID: UUID
        let connection: Connection
        var id: UUID { rowID }
    }

    /// Outcome of attempting to send a connection request.
    enum ConnectionRequestResult {
        case sent(displayName: String)
        case notFound
        case alreadyConnected
        case requestPending
        case selfRequest
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
        if let profile = try? await CloudMemoryService.fetchProfile(id: userID) {
            currentUsername = profile.username
        }
        await loadConnections()

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
        await pullCloudState(userID: userID)
    }

    /// Lightweight refresh used for foreground/periodic polling. Re-pulls
    /// connections (friend requests), shared memories, comments, media and
    /// playlists so changes made by other people show up without restarting
    /// the app. Unlike `sync()` it doesn't re-upload local memories.
    @MainActor
    func refresh() async {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        guard !isSyncing else { return }
        await loadConnections()
        await pullCloudState(userID: userID)
    }

    /// Pulls everything the user can see (own + shared memories) and merges in
    /// the latest comments, media and playlists.
    @MainActor
    private func pullCloudState(userID: String) async {
        do {
            let rows = try await CloudMemoryService.fetchMemories()
            ownedMemoryIDs = Set(rows.filter { $0.owner_id == userID }.map { $0.id })
            // Cloud payloads carry a stale/empty comments array (comments live in
            // their own table). Carry over the comments we already have in memory
            // so a poll never blanks a just-posted comment before loadComments runs.
            let existingComments = Dictionary(
                memories.map { ($0.id, $0.comments) },
                uniquingKeysWith: { first, _ in first }
            )
            memories = rows
                .map { $0.payload }
                .sorted { $0.date > $1.date }
            for index in memories.indices {
                if let carried = existingComments[memories[index].id] {
                    memories[index].comments = carried
                }
            }
            rebuildGlobalPins()
            persist()
            await loadComments()
            await loadMedia()
            await loadPlaylists()
            await loadSongs()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Pulls photos and videos for every visible memory from the dedicated
    /// media table and merges them in, so the owner and shared connections all
    /// see the same media — no matter who added it.
    @MainActor
    private func loadMedia() async {
        guard SupabaseREST.hasSession else { return }
        let ids = memories.map { $0.id }
        guard !ids.isEmpty else { return }
        do {
            let rows = try await MediaService.fetch(memoryIDs: ids)
            let grouped = Dictionary(grouping: rows, by: { $0.memory_id })
            for index in memories.indices {
                let mediaRows = grouped[memories[index].id] ?? []

                var photos = memories[index].photoURLs
                for row in mediaRows where row.kind == "photo" {
                    if !photos.contains(row.url) { photos.append(row.url) }
                }
                memories[index].photoURLs = photos

                var videos = memories[index].videos
                for row in mediaRows where row.kind == "video" {
                    if !videos.contains(where: { $0.id == row.id || $0.videoURL == row.url }) {
                        videos.append(
                            VideoAttachment(
                                id: row.id,
                                thumbnailURL: row.thumbnail_url ?? "",
                                title: "Video",
                                duration: row.duration ?? "",
                                videoURL: row.url
                            )
                        )
                    }
                }
                memories[index].videos = videos
            }
            persist()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Pulls comments for every visible memory from the dedicated comments
    /// table and merges them in, so the owner and shared connections all see
    /// the same conversation.
    @MainActor
    private func loadComments() async {
        guard SupabaseREST.hasSession else { return }
        let ids = memories.map { $0.id }
        guard !ids.isEmpty else { return }
        do {
            let rows = try await CommentService.fetch(memoryIDs: ids)
            let grouped = Dictionary(grouping: rows, by: { $0.memory_id })
            for index in memories.indices {
                let memoryID = memories[index].id
                var comments = (grouped[memoryID] ?? []).map {
                    Comment(id: $0.id, username: $0.username, text: $0.text, date: $0.created_at)
                }
                // Re-add any optimistic comments the server hasn't confirmed yet,
                // so a poll mid-post never makes a fresh comment vanish.
                if let pending = pendingComments[memoryID] {
                    for comment in pending where !comments.contains(where: { $0.id == comment.id }) {
                        comments.append(comment)
                    }
                }
                // Merge in any comment we already display that the server didn't
                // return yet (eventual consistency right after posting), so a
                // confirmed comment never flickers out between polls.
                for comment in memories[index].comments
                where !comments.contains(where: { $0.id == comment.id }) {
                    comments.append(comment)
                }
                memories[index].comments = comments.sorted { $0.date < $1.date }
            }
            persist()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Pulls individual songs for every visible memory from the dedicated songs
    /// table and merges them in, so the owner and shared connections all see the
    /// same songs — no matter who added them.
    @MainActor
    private func loadSongs() async {
        guard SupabaseREST.hasSession else { return }
        let ids = memories.map { $0.id }
        guard !ids.isEmpty else { return }
        do {
            let rows = try await SongService.fetch(memoryIDs: ids)
            let grouped = Dictionary(grouping: rows, by: { $0.memory_id })
            for index in memories.indices {
                let songRows = grouped[memories[index].id] ?? []
                var songs = memories[index].songs
                for row in songRows where !songs.contains(where: { $0.id == row.id }) {
                    songs.append(row.payload)
                }
                memories[index].songs = songs
            }
            persist()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Pulls the linked playlist for every visible memory from the dedicated
    /// playlists table and merges it in, so the owner and shared connections all
    /// see the same playlist — no matter who linked it.
    @MainActor
    private func loadPlaylists() async {
        guard SupabaseREST.hasSession else { return }
        let ids = memories.map { $0.id }
        guard !ids.isEmpty else { return }
        do {
            let rows = try await PlaylistService.fetch(memoryIDs: ids)
            let byMemory = Dictionary(rows.map { ($0.memory_id, $0.payload) }, uniquingKeysWith: { first, _ in first })
            for index in memories.indices {
                if let playlist = byMemory[memories[index].id] {
                    memories[index].playlist = playlist
                }
            }
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
        Task {
            try? await MediaService.deletePhoto(memoryID: memoryID, url: url)
            await pushMemory(memoryID)
        }
    }

    func removeVideo(from memoryID: UUID, video: VideoAttachment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].videos.removeAll { $0.id == video.id }
        if let videoURL = video.videoURL {
            MediaStore.deleteFile(at: videoURL)
        }
        MediaStore.deleteFile(at: video.thumbnailURL)
        persist()
        Task {
            try? await MediaService.deleteVideo(id: video.id)
            await pushMemory(memoryID)
        }
    }

    /// Adds a comment to a memory. Works for the owner and any connection the
    /// memory is shared with; the comment is stored in the dedicated comments
    /// table so everyone on the memory sees it.
    @MainActor
    func addComment(to memoryID: UUID, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }

        commentError = nil
        let name = currentUsername ?? "You"
        // Optimistically show the comment immediately, and track it as pending so
        // a concurrent poll can't wipe it before the server confirms.
        let local = Comment(username: name, text: trimmed)
        pendingComments[memoryID, default: []].append(local)
        memories[index].comments.append(local)
        persist()

        guard SupabaseREST.hasSession else { return }
        do {
            let row = try await CommentService.post(memoryID: memoryID, username: name, text: trimmed)
            pendingComments[memoryID]?.removeAll { $0.id == local.id }
            guard let row else { return }
            let confirmed = Comment(id: row.id, username: row.username, text: row.text, date: row.created_at)
            if let memoryIndex = memories.firstIndex(where: { $0.id == memoryID }) {
                if let commentIndex = memories[memoryIndex].comments.firstIndex(where: { $0.id == local.id }) {
                    // Replace the optimistic comment with the server-stored one.
                    memories[memoryIndex].comments[commentIndex] = confirmed
                } else if !memories[memoryIndex].comments.contains(where: { $0.id == confirmed.id }) {
                    // A poll already cleared the optimistic copy — add the real one.
                    memories[memoryIndex].comments.append(confirmed)
                    memories[memoryIndex].comments.sort { $0.date < $1.date }
                }
                persist()
            }
        } catch {
            // Roll back the optimistic comment if the server rejected it.
            pendingComments[memoryID]?.removeAll { $0.id == local.id }
            if let memoryIndex = memories.firstIndex(where: { $0.id == memoryID }) {
                memories[memoryIndex].comments.removeAll { $0.id == local.id }
                persist()
            }
            commentError = error.localizedDescription
            syncError = error.localizedDescription
        }
    }

    /// Adds a photo to a memory. Works for the owner and any connection the
    /// memory is shared with: the file is uploaded to storage and recorded in
    /// the dedicated media table so everyone on the memory sees it.
    @MainActor
    func addPhotoURL(to memoryID: UUID, url localURL: String) async {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        // Show the local file immediately while it uploads.
        memories[index].photoURLs.append(localURL)
        persist()

        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        let publicURL = await CloudMemoryService.uploadIfLocal(localURL, userID: userID, memoryID: memoryID)
        if let i = memories.firstIndex(where: { $0.id == memoryID }),
           let p = memories[i].photoURLs.firstIndex(of: localURL) {
            memories[i].photoURLs[p] = publicURL
            persist()
        }
        try? await MediaService.postPhoto(memoryID: memoryID, url: publicURL)
        if isOwned(memoryID) { await pushMemory(memoryID) }
    }

    /// Adds a video to a memory. Works for the owner and any connection the
    /// memory is shared with.
    @MainActor
    func addVideo(to memoryID: UUID, video: VideoAttachment) async {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        // Show the local video immediately while it uploads.
        memories[index].videos.append(video)
        persist()

        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        let thumb = await CloudMemoryService.uploadIfLocal(video.thumbnailURL, userID: userID, memoryID: memoryID)
        var publicVideoURL: String?
        if let original = video.videoURL {
            publicVideoURL = await CloudMemoryService.uploadIfLocal(original, userID: userID, memoryID: memoryID)
        }
        let uploaded = VideoAttachment(
            id: video.id,
            thumbnailURL: thumb,
            title: video.title,
            duration: video.duration,
            videoURL: publicVideoURL
        )
        if let i = memories.firstIndex(where: { $0.id == memoryID }),
           let v = memories[i].videos.firstIndex(where: { $0.id == video.id }) {
            memories[i].videos[v] = uploaded
            persist()
        }
        if let publicVideoURL {
            try? await MediaService.postVideo(
                memoryID: memoryID,
                id: video.id,
                url: publicVideoURL,
                thumbnailURL: thumb,
                duration: video.duration
            )
        }
        if isOwned(memoryID) { await pushMemory(memoryID) }
    }

    /// Links a playlist to a memory. Works for the owner and any connection the
    /// memory is shared with: the playlist is stored in the dedicated playlists
    /// table so everyone on the memory sees it.
    func setPlaylist(for memoryID: UUID, playlist: PlaylistAttachment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].playlist = playlist
        persist()
        Task {
            try? await PlaylistService.upsert(memoryID: memoryID, playlist: playlist)
            if isOwned(memoryID) { await pushMemory(memoryID) }
        }
    }

    /// Adds an individual song to a memory. Stored in the memory payload and
    /// synced to the cloud for memories the current user owns.
    func addSong(to memoryID: UUID, song: PlaylistTrack) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        guard !memories[index].songs.contains(where: { $0.id == song.id }) else { return }
        memories[index].songs.append(song)
        persist()
        Task { @MainActor in
            do {
                try await SongService.post(memoryID: memoryID, song: song)
            } catch {
                // Surface the failure instead of swallowing it, so a song that
                // never reaches the cloud (e.g. a missing table grant) isn't silent.
                syncError = error.localizedDescription
            }
            if isOwned(memoryID) { await pushMemory(memoryID) }
        }
    }

    /// Removes an individual song from a memory.
    func removeSong(from memoryID: UUID, song: PlaylistTrack) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].songs.removeAll { $0.id == song.id }
        persist()
        Task {
            try? await SongService.delete(id: song.id)
            if isOwned(memoryID) { await pushMemory(memoryID) }
        }
    }

    /// Removes the linked playlist from a memory for everyone on it.
    func removePlaylist(from memoryID: UUID) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].playlist = nil
        persist()
        Task {
            try? await PlaylistService.remove(memoryID: memoryID)
            if isOwned(memoryID) { await pushMemory(memoryID) }
        }
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

    // MARK: - Connections (friends)

    /// Loads all connection rows and resolves them into friends + pending requests.
    @MainActor
    func loadConnections() async {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        isLoadingConnections = true
        defer { isLoadingConnections = false }

        do {
            let rows = try await ConnectionService.fetchConnections()
            let otherIDs = Array(Set(rows.map { $0.otherID(currentUserID: userID) }))
            let profiles = try await ConnectionService.profiles(ids: otherIDs)
            let profileByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

            var friends: [Connection] = []
            var incoming: [FriendRequest] = []
            var outgoing: [FriendRequest] = []

            for row in rows {
                let otherID = row.otherID(currentUserID: userID)
                guard let profile = profileByID[otherID],
                      let otherUUID = UUID(uuidString: profile.id) else { continue }
                let name = profile.display_name?.isEmpty == false ? profile.display_name! : profile.username
                let connection = Connection(
                    id: otherUUID,
                    username: profile.username,
                    displayName: name,
                    avatarColor: Self.color(for: profile.id)
                )
                if row.status == "accepted" {
                    friends.append(connection)
                } else if row.addressee_id == userID {
                    incoming.append(FriendRequest(rowID: row.id, connection: connection))
                } else {
                    outgoing.append(FriendRequest(rowID: row.id, connection: connection))
                }
            }

            allConnections = friends.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            incomingRequests = incoming
            outgoingRequests = outgoing
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Sends a connection request to someone looked up by `@username` or email.
    @MainActor
    func sendConnectionRequest(identifier: String) async -> ConnectionRequestResult {
        guard let userID = currentUserID, SupabaseREST.hasSession else {
            return .failure("You need to be signed in to add connections.")
        }
        do {
            guard let profile = try await CloudMemoryService.findProfile(identifier: identifier) else {
                return .notFound
            }
            if profile.id == userID { return .selfRequest }
            guard let otherUUID = UUID(uuidString: profile.id) else {
                return .failure("Couldn't read that account.")
            }

            if allConnections.contains(where: { $0.id == otherUUID }) {
                return .alreadyConnected
            }
            if incomingRequests.contains(where: { $0.connection.id == otherUUID })
                || outgoingRequests.contains(where: { $0.connection.id == otherUUID }) {
                return .requestPending
            }

            try await ConnectionService.sendRequest(from: userID, to: profile.id)
            await loadConnections()
            let name = profile.display_name?.isEmpty == false ? profile.display_name! : profile.username
            return .sent(displayName: name)
        } catch let SupabaseREST.RESTError.http(status, _) where status == 409 {
            return .requestPending
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Accepts an incoming connection request.
    @MainActor
    func acceptRequest(_ request: FriendRequest) async {
        do {
            try await ConnectionService.accept(id: request.rowID)
            await loadConnections()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Declines an incoming request or cancels an outgoing one.
    @MainActor
    func removeRequest(_ request: FriendRequest) async {
        do {
            try await ConnectionService.remove(id: request.rowID)
            await loadConnections()
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Messaging

    /// A direct message resolved for display in a conversation.
    struct ChatBubble: Identifiable {
        let id: UUID
        let body: String
        let isMine: Bool
        let date: Date
    }

    /// Loads the conversation between the signed-in user and a connection,
    /// oldest message first.
    @MainActor
    func loadConversation(with friend: Connection) async -> [ChatBubble] {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return [] }
        do {
            let rows = try await MessageService.conversation(with: friend.id.uuidString, currentUserID: userID)
            return rows.map { row in
                ChatBubble(id: row.id, body: row.body, isMine: row.isMine(currentUserID: userID), date: row.created_at)
            }
        } catch {
            syncError = error.localizedDescription
            return []
        }
    }

    /// Sends a message to a connection and returns the stored bubble on success.
    @MainActor
    func sendMessage(to friend: Connection, body: String) async -> ChatBubble? {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            guard let row = try await MessageService.send(to: friend.id.uuidString, body: trimmed) else { return nil }
            return ChatBubble(id: row.id, body: row.body, isMine: row.isMine(currentUserID: userID), date: row.created_at)
        } catch {
            syncError = error.localizedDescription
            return nil
        }
    }

    /// Total number of unread messages across all conversations.
    var totalUnread: Int {
        unreadByFriend.values.reduce(0, +)
    }

    private func lastRead(for friendID: UUID) -> Date {
        let stored = UserDefaults.standard.double(forKey: lastReadPrefix + friendID.uuidString)
        return stored > 0 ? Date(timeIntervalSince1970: stored) : .distantPast
    }

    /// Marks a conversation as read up to now, clearing its unread badge.
    @MainActor
    func markConversationRead(with friend: Connection) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastReadPrefix + friend.id.uuidString)
        if unreadByFriend[friend.id] != nil {
            unreadByFriend[friend.id] = 0
        }
    }

    /// Recomputes how many messages from each friend have arrived since the last
    /// time the signed-in user opened that conversation on this device.
    @MainActor
    func loadUnreadCounts() async {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        do {
            let rows = try await MessageService.received(currentUserID: userID)
            var counts: [UUID: Int] = [:]
            for row in rows {
                guard let senderUUID = UUID(uuidString: row.sender_id) else { continue }
                if row.created_at > lastRead(for: senderUUID) {
                    counts[senderUUID, default: 0] += 1
                }
            }
            unreadByFriend = counts
        } catch {
            // Non-fatal: leave the previous counts in place on a transient failure.
        }
    }

    /// Deterministically assigns an avatar color from a user id so the same
    /// friend always shows the same color across sessions and devices.
    private static func color(for id: String) -> ConnectionColor {
        let colors = ConnectionColor.allCases
        let hash = abs(id.hashValue)
        return colors[hash % colors.count]
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
