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

    /// The `connections` table row id for each accepted friend, so a friend
    /// can be removed from their profile.
    private(set) var friendRowIDs: [UUID: UUID] = [:]

    /// Unread message count per friend (by connection id), used to drive the
    /// badges next to each conversation and the tab badge. Computed against a
    /// per-conversation last-read timestamp stored locally on this device.
    var unreadByFriend: [UUID: Int] = [:]

    /// The newest message exchanged with each friend (by connection id),
    /// driving the conversation previews on the Messages tab.
    var conversationPreviews: [UUID: ConversationPreview] = [:]

    /// The friend whose chat is currently open on screen. Their messages are
    /// never counted as unread, so opening a conversation reliably clears its
    /// notification badge.
    var activeChatFriendID: UUID? {
        didSet { NotificationCenterDelegate.shared.activeThreadID = activeChatFriendID?.uuidString.lowercased() }
    }

    /// Whether this user reports read receipts to their friends. When off,
    /// conversations they open are never marked as read for the other person.
    var readReceiptsEnabled: Bool = UserDefaults.standard.object(forKey: "read_receipts_enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(readReceiptsEnabled, forKey: "read_receipts_enabled") }
    }

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
    /// Owner id for every visible memory, so guests can record shares correctly.
    private var ownerByMemoryID: [UUID: String] = [:]

    private let lastUserKey = "cloud_last_user_id"
    private let lastReadPrefix = "msg_last_read_"

    /// Optimistic comments that have been shown locally but not yet confirmed by
    /// the server, keyed by memory id. Kept so a background poll landing in the
    /// middle of a post never wipes a just-typed comment off screen.
    private var pendingComments: [UUID: [Comment]] = [:]

    /// Media rows whose local-file repair has already been attempted this
    /// session, so the healing pass doesn't re-upload on every poll.
    private var healedMediaRowIDs: Set<UUID> = []

    /// Memory ids with a payload push currently in flight. While a push is
    /// pending, a background poll (whose fetch may predate the push) keeps the
    /// local sub-memories instead of the server's, so a just-created pin can't
    /// be wiped off screen by stale data.
    private var pendingPayloadPushes: [UUID: Int] = [:]

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
            if let name = profile.display_name, !name.isEmpty {
                currentDisplayName = name
            }
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

    /// Pulls everything the user can see (own + shared memories), merges in the
    /// latest shares, comments, media, playlists and songs, then publishes AT
    /// MOST ONE state change. Merging before publishing is what stops the old
    /// flicker: buttons glitching and photo counts jumping (e.g. 11 → 9 → 11)
    /// on every background poll while intermediate states landed one by one.
    @MainActor
    private func pullCloudState(userID: String) async {
        do {
            let rows = try await CloudMemoryService.fetchMemories()
            ownedMemoryIDs = Set(rows.filter { $0.owner_id == userID }.map { $0.id })
            ownerByMemoryID = Dictionary(rows.map { ($0.id, $0.owner_id) }, uniquingKeysWith: { first, _ in first })
            // Cloud payloads carry a stale/empty comments array (comments live in
            // their own table). Carry over the comments we already have in memory
            // so a poll never blanks a just-posted comment before the merge runs.
            let existingComments = Dictionary(
                memories.map { ($0.id, $0.comments) },
                uniquingKeysWith: { first, _ in first }
            )
            let existingSubMemories = Dictionary(
                memories.map { ($0.id, $0.subMemories) },
                uniquingKeysWith: { first, _ in first }
            )
            var updated = rows
                .map { $0.payload }
                .sorted { $0.date > $1.date }
            for index in updated.indices {
                if let carried = existingComments[updated[index].id] {
                    updated[index].comments = carried
                }
                // Keep local sub-memories while their payload push is in
                // flight (the fetched payload may predate the edit).
                if pendingPayloadPushes[updated[index].id] != nil,
                   let localSubs = existingSubMemories[updated[index].id] {
                    updated[index].subMemories = localSubs
                }
                Self.stripUnreadableLocalMedia(from: &updated[index])
            }

            let ids = updated.map { $0.id }
            let shareRows = await fetchRows("People") { try await CloudMemoryService.fetchShares(memoryIDs: ids) }
            let commentRows = await fetchRows("Comments") { try await CommentService.fetch(memoryIDs: ids) }
            let mediaRows = await fetchRows("Media") { try await MediaService.fetch(memoryIDs: ids) }
            let playlistRows = await fetchRows("Playlists") { try await PlaylistService.fetch(memoryIDs: ids) }
            let songRows = await fetchRows("Songs") { try await SongService.fetch(memoryIDs: ids) }

            // One profile lookup covering share recipients, comment authors, and
            // the owners of memories shared with me (so guests can show them).
            var profileIDs = Set(shareRows.map { $0.shared_with })
            profileIDs.formUnion(commentRows.map { $0.author_id })
            for (memoryID, ownerID) in ownerByMemoryID where !ownedMemoryIDs.contains(memoryID) {
                profileIDs.insert(ownerID)
            }
            var profileByUUID: [UUID: CloudProfile] = [:]
            if !profileIDs.isEmpty,
               let profiles = try? await ConnectionService.profiles(ids: Array(profileIDs)) {
                for profile in profiles {
                    if let uuid = UUID(uuidString: profile.id) { profileByUUID[uuid] = profile }
                }
            }

            mergeShares(into: &updated, rows: shareRows, profileByUUID: profileByUUID, userID: userID)
            mergeComments(into: &updated, rows: commentRows, profileByUUID: profileByUUID)
            mergeMedia(into: &updated, rows: mediaRows)
            mergePlaylists(into: &updated, rows: playlistRows)
            mergeSongs(into: &updated, rows: songRows)

            if updated != memories {
                memories = updated
                rebuildGlobalPins()
                persist()
            }

            healLocalMediaRows(mediaRows, userID: userID)
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// Fetches feature-table rows, surfacing (but never failing on) errors so
    /// one broken table can't block the rest of the pull.
    @MainActor
    private func fetchRows<T>(_ label: String, _ operation: () async throws -> [T]) async -> [T] {
        do {
            return try await operation()
        } catch {
            syncError = "\(label): \(error.localizedDescription)"
            return []
        }
    }

    /// Removes photo / video references that point at local files on ANOTHER
    /// device (they can never be displayed here). The shared, uploaded copies
    /// are merged back in from the cloud media table by the media merge.
    nonisolated private static func stripUnreadableLocalMedia(from memory: inout Memory) {
        func isUnreadable(_ urlString: String) -> Bool {
            guard let url = URL(string: urlString), url.isFileURL else { return false }
            return !FileManager.default.fileExists(atPath: url.path)
        }

        memory.photoURLs.removeAll { isUnreadable($0) }
        memory.pins = memory.pins.map { pin in
            guard let imageURL = pin.imageURL, isUnreadable(imageURL) else { return pin }
            return MemoryPin(
                id: pin.id,
                coordinate: pin.coordinate,
                title: pin.title,
                date: pin.date,
                imageURL: nil,
                intensity: pin.intensity
            )
        }
        memory.videos = memory.videos.compactMap { video in
            let videoUnreadable = video.videoURL.map(isUnreadable) ?? true
            let thumbUnreadable = isUnreadable(video.thumbnailURL)
            if videoUnreadable && thumbUnreadable { return nil }
            guard videoUnreadable else { return video }
            return VideoAttachment(
                id: video.id,
                thumbnailURL: video.thumbnailURL,
                title: video.title,
                duration: video.duration,
                videoURL: nil
            )
        }
    }

    /// Merges share rows into each memory's people list, so the number of
    /// people stays accurate for everyone — including the owner of a memory
    /// shared with me, and people added by someone other than the owner.
    private func mergeShares(
        into updated: inout [Memory],
        rows: [CloudMemoryService.ShareReadRow],
        profileByUUID: [UUID: CloudProfile],
        userID: String
    ) {
        let selfUUID = UUID(uuidString: userID)
        let grouped = Dictionary(grouping: rows, by: { $0.memory_id })
        for index in updated.indices {
            let memoryID = updated[index].id
            var connections = updated[index].connections
            // Refresh names / avatars of people we already list.
            connections = connections.map { existing in
                guard let profile = profileByUUID[existing.id] else { return existing }
                let name = profile.display_name?.isEmpty == false ? profile.display_name! : profile.username
                return Connection(
                    id: existing.id,
                    username: profile.username,
                    displayName: name,
                    avatarColor: existing.avatarColor,
                    avatarURL: profile.avatar_url
                )
            }
            // On memories shared WITH me, the owner belongs in the people list.
            if !ownedMemoryIDs.contains(memoryID),
               let ownerID = ownerByMemoryID[memoryID],
               let ownerUUID = UUID(uuidString: ownerID),
               ownerUUID != selfUUID,
               !connections.contains(where: { $0.id == ownerUUID }),
               let profile = profileByUUID[ownerUUID] {
                let name = profile.display_name?.isEmpty == false ? profile.display_name! : profile.username
                connections.insert(
                    Connection(
                        id: ownerUUID,
                        username: profile.username,
                        displayName: name,
                        avatarColor: Self.color(for: ownerID),
                        avatarURL: profile.avatar_url
                    ),
                    at: 0
                )
            }
            // Merge in share recipients missing from the payload.
            for row in grouped[memoryID] ?? [] {
                guard let uuid = UUID(uuidString: row.shared_with),
                      uuid != selfUUID,
                      !connections.contains(where: { $0.id == uuid }),
                      let profile = profileByUUID[uuid] else { continue }
                let name = profile.display_name?.isEmpty == false ? profile.display_name! : profile.username
                connections.append(
                    Connection(
                        id: uuid,
                        username: profile.username,
                        displayName: name,
                        avatarColor: Self.color(for: profile.id),
                        avatarURL: profile.avatar_url
                    )
                )
            }
            if connections != updated[index].connections {
                updated[index].connections = connections
            }
        }
    }

    /// Merges photos and videos from the media table, skipping rows that point
    /// at files on another person's device — those can never load here, and
    /// showing them produced "photo added but can't view it" placeholder tiles
    /// plus photo counts that differed from person to person.
    private func mergeMedia(into updated: inout [Memory], rows: [CloudMediaRow]) {
        let grouped = Dictionary(grouping: rows, by: { $0.memory_id })
        for index in updated.indices {
            let mediaRows = grouped[updated[index].id] ?? []

            var photos = updated[index].photoURLs
            for row in mediaRows where row.kind == "photo" {
                guard !Self.isUnreadableLocalURL(row.url) else { continue }
                if !photos.contains(row.url) { photos.append(row.url) }
            }
            if photos != updated[index].photoURLs {
                updated[index].photoURLs = photos
            }

            var videos = updated[index].videos
            for row in mediaRows where row.kind == "video" {
                let playable = !Self.isUnreadableLocalURL(row.url)
                let thumb = row.thumbnail_url.flatMap { Self.isUnreadableLocalURL($0) ? nil : $0 }
                if let existing = videos.firstIndex(where: { $0.id == row.id }) {
                    // Backfill a playable cloud URL onto a video whose local
                    // file lives on another device.
                    if videos[existing].videoURL == nil, playable {
                        videos[existing] = VideoAttachment(
                            id: row.id,
                            thumbnailURL: thumb ?? videos[existing].thumbnailURL,
                            title: videos[existing].title,
                            duration: row.duration ?? videos[existing].duration,
                            videoURL: row.url
                        )
                    }
                } else if playable, !videos.contains(where: { $0.videoURL == row.url }) {
                    videos.append(
                        VideoAttachment(
                            id: row.id,
                            thumbnailURL: thumb ?? "",
                            title: "Video",
                            duration: row.duration ?? "",
                            videoURL: row.url
                        )
                    )
                }
            }
            if videos != updated[index].videos {
                updated[index].videos = videos
            }

            // Re-apply sub-memory placements recorded on the shared media rows
            // (this is how a guest's pins reach everyone: the memory payload is
            // owner-only, but media rows are writable by the whole memory).
            var subs = updated[index].subMemories
            if !subs.isEmpty {
                for row in mediaRows {
                    guard let subID = row.sub_memory_id,
                          let target = subs.firstIndex(where: { $0.id == subID }) else { continue }
                    if row.kind == "photo" {
                        for i in subs.indices where i != target {
                            subs[i].photoURLs.removeAll { $0 == row.url }
                        }
                        if !subs[target].photoURLs.contains(row.url) {
                            subs[target].photoURLs.append(row.url)
                        }
                    } else {
                        for i in subs.indices where i != target {
                            subs[i].videoIDs.removeAll { $0 == row.id }
                        }
                        if !subs[target].videoIDs.contains(row.id) {
                            subs[target].videoIDs.append(row.id)
                        }
                    }
                }
                if subs != updated[index].subMemories {
                    updated[index].subMemories = subs
                }
            }
        }
    }

    /// True when the string is a `file://` URL that can't be read on this
    /// device (it lives on someone else's phone).
    nonisolated private static func isUnreadableLocalURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), url.isFileURL else { return false }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// True when the string is a `file://` URL whose file exists on THIS device.
    nonisolated private static func isReadableLocalFile(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), url.isFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Repairs media rows that were stored with a path on THIS device (an
    /// upload that failed at post time, before uploads were made strict).
    /// Rows I authored on memories I don't own are re-uploaded and patched so
    /// everyone can finally see them; rows on my own memories are removed
    /// because the memory payload already carries (and re-uploads) that media.
    private func healLocalMediaRows(_ rows: [CloudMediaRow], userID: String) {
        let work = rows.filter { row in
            row.author_id.lowercased() == userID.lowercased()
                && !healedMediaRowIDs.contains(row.id)
                && (Self.isReadableLocalFile(row.url)
                    || (row.thumbnail_url.map(Self.isReadableLocalFile) ?? false))
        }
        guard !work.isEmpty else { return }
        healedMediaRowIDs.formUnion(work.map { $0.id })
        let owned = ownedMemoryIDs
        Task {
            for row in work {
                if owned.contains(row.memory_id) {
                    if row.kind == "photo" {
                        try? await MediaService.deletePhoto(memoryID: row.memory_id, url: row.url)
                    } else {
                        try? await MediaService.deleteVideo(id: row.id)
                    }
                    continue
                }
                var newURL: String?
                var newThumb: String?
                if Self.isReadableLocalFile(row.url) {
                    newURL = try? await CloudMemoryService.uploadLocalFile(row.url, userID: userID, memoryID: row.memory_id)
                }
                if let thumb = row.thumbnail_url, Self.isReadableLocalFile(thumb) {
                    newThumb = try? await CloudMemoryService.uploadLocalFile(thumb, userID: userID, memoryID: row.memory_id)
                }
                if newURL != nil || newThumb != nil {
                    try? await MediaService.updateURLs(id: row.id, url: newURL, thumbnailURL: newThumb)
                }
            }
        }
    }

    /// Merges comments from the comments table, showing each author's current
    /// chosen name (falling back to the stored @username for accounts that
    /// never picked one).
    private func mergeComments(
        into updated: inout [Memory],
        rows: [CloudCommentRow],
        profileByUUID: [UUID: CloudProfile]
    ) {
        let grouped = Dictionary(grouping: rows, by: { $0.memory_id })
        for index in updated.indices {
            let memoryID = updated[index].id
            var comments = (grouped[memoryID] ?? []).map { row in
                var shown = row.username
                if let authorUUID = UUID(uuidString: row.author_id),
                   let profile = profileByUUID[authorUUID],
                   let displayName = profile.display_name, !displayName.isEmpty {
                    shown = displayName
                }
                return Comment(id: row.id, username: shown, text: row.text, date: row.created_at)
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
            for comment in updated[index].comments
            where !comments.contains(where: { $0.id == comment.id }) {
                comments.append(comment)
            }
            let sorted = comments.sorted { $0.date < $1.date }
            if sorted != updated[index].comments {
                updated[index].comments = sorted
            }
        }
    }

    /// Merges individual songs from the songs table, so the owner and shared
    /// connections all see the same songs — no matter who added them.
    private func mergeSongs(into updated: inout [Memory], rows: [CloudSongRow]) {
        let grouped = Dictionary(grouping: rows, by: { $0.memory_id })
        for index in updated.indices {
            let songRows = grouped[updated[index].id] ?? []
            var songs = updated[index].songs
            for row in songRows where !songs.contains(where: { $0.id == row.id }) {
                songs.append(row.payload)
            }
            if songs != updated[index].songs {
                updated[index].songs = songs
            }
        }
    }

    /// Merges the linked playlist from the playlists table, so the owner and
    /// shared connections all see the same playlist — no matter who linked it.
    private func mergePlaylists(into updated: inout [Memory], rows: [CloudPlaylistRow]) {
        let byMemory = Dictionary(rows.map { ($0.memory_id, $0.payload) }, uniquingKeysWith: { first, _ in first })
        for index in updated.indices {
            if let playlist = byMemory[updated[index].id], playlist != updated[index].playlist {
                updated[index].playlist = playlist
            }
        }
    }

    private func isOwned(_ memoryID: UUID) -> Bool {
        currentUserID != nil && ownedMemoryIDs.contains(memoryID)
    }

    /// Whether the signed-in user created (owns) the given memory.
    func isOwner(of memoryID: UUID) -> Bool {
        isOwned(memoryID)
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

    /// Pushes an owned memory's payload while marking the push as in flight,
    /// so a concurrent poll can't overwrite just-edited sub-memories with a
    /// stale server copy fetched before the push landed.
    private func schedulePayloadPush(_ memoryID: UUID) {
        pendingPayloadPushes[memoryID, default: 0] += 1
        Task { @MainActor in
            await pushMemory(memoryID)
            if let count = pendingPayloadPushes[memoryID], count > 1 {
                pendingPayloadPushes[memoryID] = count - 1
            } else {
                pendingPayloadPushes.removeValue(forKey: memoryID)
            }
        }
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

    /// Edits a memory's core details (title, description, date, location).
    /// Only the owner can do this; changes sync to everyone it's shared with.
    func updateMemoryDetails(
        memoryID: UUID,
        title: String,
        subtitle: String,
        date: Date,
        coordinate: CLLocationCoordinate2D?
    ) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        var memory = memories[index]
        memory.title = title
        memory.subtitle = subtitle
        memory.date = date
        if let coordinate {
            let movedFromCenter = memory.centerCoordinate.latitude != coordinate.latitude
                || memory.centerCoordinate.longitude != coordinate.longitude
            memory.centerCoordinate = coordinate
            // A single-pin memory keeps its pin anchored to the memory location.
            if movedFromCenter && memory.pins.count == 1 {
                let pin = memory.pins[0]
                memory.pins = [
                    MemoryPin(
                        id: pin.id,
                        coordinate: coordinate,
                        title: title,
                        date: date,
                        imageURL: pin.imageURL,
                        intensity: pin.intensity
                    )
                ]
            }
        }
        // Keep pin labels in sync with the new title.
        memory.pins = memory.pins.map {
            MemoryPin(
                id: $0.id,
                coordinate: $0.coordinate,
                title: title,
                date: $0.date,
                imageURL: $0.imageURL,
                intensity: $0.intensity
            )
        }
        memories[index] = memory
        rebuildGlobalPins()
        persist()
        Task { await pushMemory(memoryID) }
    }

    /// Owner-only toggle: lets everyone a memory is shared with add more people.
    func setGuestInvites(for memoryID: UUID, allowed: Bool) {
        guard isOwned(memoryID),
              let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].allowsGuestInvites = allowed
        persist()
        Task { await pushMemory(memoryID) }
    }

    /// Owner-only privacy toggle: lets everyone a memory is shared with save
    /// its photos and videos to their own Photos library.
    func setMediaSaving(for memoryID: UUID, allowed: Bool) {
        guard isOwned(memoryID),
              let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].allowsMediaSaving = allowed
        persist()
        Task { await pushMemory(memoryID) }
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
        for i in memories[index].subMemories.indices {
            memories[index].subMemories[i].photoURLs.removeAll { $0 == url }
        }
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
        for i in memories[index].subMemories.indices {
            memories[index].subMemories[i].videoIDs.removeAll { $0 == video.id }
        }
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

    // MARK: - Memories inside a memory

    /// Pins a smaller memory inside a bigger one. Owner-only: sub-memories
    /// live in the memory payload, which only the owner may update.
    func addSubMemory(to memoryID: UUID, title: String, coordinate: CLLocationCoordinate2D, date: Date, endDate: Date? = nil) {
        guard isOwned(memoryID),
              let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        let sub = SubMemory(title: title, date: date, endDate: endDate, coordinate: coordinate)
        memories[index].subMemories.append(sub)
        persist()
        schedulePayloadPush(memoryID)
    }

    /// Edits a pinned memory's title, spot, date, or duration (owner-only).
    func updateSubMemoryDetails(memoryID: UUID, subMemoryID: UUID, title: String, coordinate: CLLocationCoordinate2D, date: Date, endDate: Date? = nil) {
        guard isOwned(memoryID),
              let index = memories.firstIndex(where: { $0.id == memoryID }),
              let subIndex = memories[index].subMemories.firstIndex(where: { $0.id == subMemoryID }) else { return }
        memories[index].subMemories[subIndex].title = title
        memories[index].subMemories[subIndex].coordinate = coordinate
        memories[index].subMemories[subIndex].date = date
        memories[index].subMemories[subIndex].endDate = endDate
        persist()
        schedulePayloadPush(memoryID)
    }

    /// Removes a pinned memory (owner-only). Its photos and videos stay in
    /// the main memory — only the pin and its placements go away.
    func deleteSubMemory(memoryID: UUID, subMemoryID: UUID) {
        guard isOwned(memoryID),
              let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].subMemories.removeAll { $0.id == subMemoryID }
        persist()
        schedulePayloadPush(memoryID)
        // Clear row placements so stale rows can't re-link media to the
        // deleted pin on other devices.
        Task { try? await MediaService.clearSubMemory(memoryID: memoryID, subMemoryID: subMemoryID) }
    }

    /// Pins a photo to a memory inside the memory (or back to the whole
    /// memory with nil). Anyone on the memory can do it: the placement is
    /// written onto the photo's shared media row, and the owner's payload
    /// copy is updated too.
    func assignPhoto(memoryID: UUID, url: String, to subMemoryID: UUID?) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        for i in memories[index].subMemories.indices {
            memories[index].subMemories[i].photoURLs.removeAll { $0 == url }
        }
        if let subMemoryID,
           let subIndex = memories[index].subMemories.firstIndex(where: { $0.id == subMemoryID }) {
            memories[index].subMemories[subIndex].photoURLs.append(url)
        }
        persist()
        Task { try? await MediaService.setPhotoSubMemory(memoryID: memoryID, url: url, subMemoryID: subMemoryID) }
        if isOwned(memoryID) { schedulePayloadPush(memoryID) }
    }

    /// Pins a video to a memory inside the memory (or back to the whole
    /// memory with nil).
    func assignVideo(memoryID: UUID, videoID: UUID, to subMemoryID: UUID?) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        for i in memories[index].subMemories.indices {
            memories[index].subMemories[i].videoIDs.removeAll { $0 == videoID }
        }
        if let subMemoryID,
           let subIndex = memories[index].subMemories.firstIndex(where: { $0.id == subMemoryID }) {
            memories[index].subMemories[subIndex].videoIDs.append(videoID)
        }
        persist()
        Task { try? await MediaService.setVideoSubMemory(id: videoID, subMemoryID: subMemoryID) }
        if isOwned(memoryID) { schedulePayloadPush(memoryID) }
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
        // The username may not be resolved yet right after launch — fetch it so
        // comments are never posted under a placeholder name.
        if currentUsername == nil, let userID = currentUserID, SupabaseREST.hasSession,
           let profile = (try? await CloudMemoryService.fetchProfile(id: userID)) ?? nil {
            currentUsername = profile.username
            if let fetched = profile.display_name, !fetched.isEmpty {
                currentDisplayName = fetched
            }
        }
        let emailFallback = currentEmail.split(separator: "@").first.map(String.init)
        // Comments show the user's chosen name, not their @username.
        let chosenName = currentDisplayName?.isEmpty == false ? currentDisplayName : nil
        let name = chosenName ?? currentUsername ?? emailFallback ?? "You"
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
            notifyMemoryParticipants(
                memoryID: memoryID,
                title: memoryByID(memoryID)?.title ?? "New comment",
                body: "\(name): \(trimmed)"
            )
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
    func addPhotoURL(to memoryID: UUID, url localURL: String, subMemoryID: UUID? = nil) async {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        // Show the local file immediately while it uploads.
        memories[index].photoURLs.append(localURL)
        if let subMemoryID,
           let subIndex = memories[index].subMemories.firstIndex(where: { $0.id == subMemoryID }) {
            memories[index].subMemories[subIndex].photoURLs.append(localURL)
        }
        persist()

        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        do {
            let publicURL = try await CloudMemoryService.uploadLocalFile(localURL, userID: userID, memoryID: memoryID)
            if let i = memories.firstIndex(where: { $0.id == memoryID }) {
                if let p = memories[i].photoURLs.firstIndex(of: localURL) {
                    memories[i].photoURLs[p] = publicURL
                }
                // Keep any sub-memory reference pointing at the uploaded copy.
                for s in memories[i].subMemories.indices {
                    if let r = memories[i].subMemories[s].photoURLs.firstIndex(of: localURL) {
                        memories[i].subMemories[s].photoURLs[r] = publicURL
                    }
                }
                persist()
            }
            try await MediaService.postPhoto(memoryID: memoryID, url: publicURL, subMemoryID: subMemoryID)
        } catch {
            // Never record a device-local path in the shared media table — other
            // people would count the photo but couldn't display it. Keep the
            // local copy on screen and surface what went wrong.
            syncError = "Photo upload failed: \(error.localizedDescription)"
        }
        if isOwned(memoryID) { await pushMemory(memoryID) }
    }

    /// Adds a video to a memory. Works for the owner and any connection the
    /// memory is shared with.
    @MainActor
    func addVideo(to memoryID: UUID, video: VideoAttachment, subMemoryID: UUID? = nil) async {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        // Show the local video immediately while it uploads.
        memories[index].videos.append(video)
        if let subMemoryID,
           let subIndex = memories[index].subMemories.firstIndex(where: { $0.id == subMemoryID }) {
            memories[index].subMemories[subIndex].videoIDs.append(video.id)
        }
        persist()

        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        do {
            let thumb = try await CloudMemoryService.uploadLocalFile(video.thumbnailURL, userID: userID, memoryID: memoryID)
            var publicVideoURL: String?
            if let original = video.videoURL {
                publicVideoURL = try await CloudMemoryService.uploadLocalFile(original, userID: userID, memoryID: memoryID)
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
                try await MediaService.postVideo(
                    memoryID: memoryID,
                    id: video.id,
                    url: publicVideoURL,
                    thumbnailURL: thumb,
                    duration: video.duration,
                    subMemoryID: subMemoryID
                )
            }
        } catch {
            // Same rule as photos: never share a device-local path. Keep the
            // local copy playable here and surface the failure.
            syncError = "Video upload failed: \(error.localizedDescription)"
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

    // MARK: - Push notifications

    /// The name other users see in push notifications triggered by this user.
    private var pushSenderName: String {
        if let name = currentDisplayName, !name.isEmpty { return name }
        if let username = currentUsername, !username.isEmpty { return "@\(username)" }
        if let emailName = currentEmail.split(separator: "@").first, !emailName.isEmpty {
            return String(emailName)
        }
        return "Someone"
    }

    /// Notifies everyone else on a memory (its owner plus everyone it's shared
    /// with) about new activity, e.g. a comment.
    private func notifyMemoryParticipants(memoryID: UUID, title: String, body: String) {
        guard let userID = currentUserID, let memory = memoryByID(memoryID) else { return }
        var recipients = Set(memory.connections.map { $0.id.uuidString.lowercased() })
        if let ownerID = ownerByMemoryID[memoryID] {
            recipients.insert(ownerID.lowercased())
        }
        recipients.remove(userID.lowercased())
        guard !recipients.isEmpty else { return }
        PushSender.send(to: Array(recipients), title: title, body: body, threadID: memoryID.uuidString)
    }

    // MARK: - Sharing

    /// Shares a memory with a friend looked up by `@username` or email. The
    /// owner can always do this; other people on the memory can too when the
    /// owner has enabled guest invites.
    @MainActor
    func shareMemory(memoryID: UUID, identifier: String) async -> ShareResult {
        guard let userID = currentUserID, SupabaseREST.hasSession else {
            return .failure("You need to be signed in to share.")
        }
        let isOwnerShare = isOwned(memoryID)
        guard isOwnerShare || memoryByID(memoryID)?.allowsGuestInvites == true else {
            return .failure("The memory's creator hasn't allowed others to add people yet.")
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
                avatarColor: Self.color(for: profile.id),
                avatarURL: profile.avatar_url
            )
            addConnection(to: memoryID, connection: connection)

            let ownerID = ownerByMemoryID[memoryID] ?? userID
            try await CloudMemoryService.shareMemory(memoryID: memoryID, ownerID: ownerID, sharedWith: profile.id)
            let memoryTitle = memoryByID(memoryID)?.title ?? "a memory"
            PushSender.send(
                to: [profile.id],
                title: "New shared memory",
                body: "\(pushSenderName) shared \"\(memoryTitle)\" with you",
                threadID: memoryID.uuidString
            )
            if isOwnerShare { await pushMemory(memoryID) }
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
            var rowIDs: [UUID: UUID] = [:]

            for row in rows {
                let otherID = row.otherID(currentUserID: userID)
                guard let profile = profileByID[otherID],
                      let otherUUID = UUID(uuidString: profile.id) else { continue }
                let name = profile.display_name?.isEmpty == false ? profile.display_name! : profile.username
                let connection = Connection(
                    id: otherUUID,
                    username: profile.username,
                    displayName: name,
                    avatarColor: Self.color(for: profile.id),
                    avatarURL: profile.avatar_url
                )
                if row.status == "accepted" {
                    friends.append(connection)
                    rowIDs[connection.id] = row.id
                } else if row.addressee_id == userID {
                    incoming.append(FriendRequest(rowID: row.id, connection: connection))
                } else {
                    outgoing.append(FriendRequest(rowID: row.id, connection: connection))
                }
            }

            allConnections = friends.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            incomingRequests = incoming
            outgoingRequests = outgoing
            friendRowIDs = rowIDs
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
            PushSender.send(
                to: [profile.id],
                title: "New friend request",
                body: "\(pushSenderName) sent you a friend request"
            )
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
            PushSender.send(
                to: [request.connection.id.uuidString],
                title: "Friend request accepted",
                body: "\(pushSenderName) accepted your friend request"
            )
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

    /// Removes an accepted friend connection entirely.
    @MainActor
    func removeFriend(_ connection: Connection) async {
        guard let rowID = friendRowIDs[connection.id] else { return }
        do {
            try await ConnectionService.remove(id: rowID)
            await loadConnections()
        } catch {
            syncError = error.localizedDescription
        }
    }

    /// The signed-in user's relationship with another user.
    enum Relationship {
        case friend
        case incomingRequest(FriendRequest)
        case outgoingRequest(FriendRequest)
        case notConnected
    }

    /// How the signed-in user currently relates to the given user id.
    func relationship(with connectionID: UUID) -> Relationship {
        if allConnections.contains(where: { $0.id == connectionID }) { return .friend }
        if let request = incomingRequests.first(where: { $0.connection.id == connectionID }) {
            return .incomingRequest(request)
        }
        if let request = outgoingRequests.first(where: { $0.connection.id == connectionID }) {
            return .outgoingRequest(request)
        }
        return .notConnected
    }

    // MARK: - Messaging

    /// A direct message resolved for display in a conversation.
    struct ChatBubble: Identifiable {
        let id: UUID
        let body: String
        let isMine: Bool
        let date: Date
        /// When the other person read this message (meaningful for mine only).
        let readAt: Date?
    }

    /// The latest message exchanged with a friend, shown as the row preview
    /// in the Messages tab conversation list.
    struct ConversationPreview {
        let body: String
        let date: Date
        let isMine: Bool
    }

    /// Loads the conversation between the signed-in user and a connection,
    /// oldest message first.
    @MainActor
    func loadConversation(with friend: Connection) async -> [ChatBubble] {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return [] }
        do {
            let rows = try await MessageService.conversation(with: friend.id.uuidString, currentUserID: userID)
            return rows.map { row in
                ChatBubble(
                    id: row.id,
                    body: row.body,
                    isMine: row.isMine(currentUserID: userID),
                    date: row.created_at,
                    readAt: row.read_at
                )
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
            PushSender.send(
                to: [friend.id.uuidString],
                title: pushSenderName,
                body: trimmed,
                threadID: userID
            )
            return ChatBubble(
                id: row.id,
                body: row.body,
                isMine: row.isMine(currentUserID: userID),
                date: row.created_at,
                readAt: row.read_at
            )
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

    /// Marks a conversation as read up to now, clearing its unread badge. When
    /// read receipts are enabled, the friend's messages are also stamped read
    /// in the cloud so they see a "Read" receipt.
    @MainActor
    func markConversationRead(with friend: Connection) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastReadPrefix + friend.id.uuidString)
        if unreadByFriend[friend.id] != nil {
            unreadByFriend[friend.id] = 0
        }
        guard readReceiptsEnabled, let userID = currentUserID, SupabaseREST.hasSession else { return }
        let friendID = friend.id.uuidString
        // Best-effort: receipts are cosmetic, so failures are silent (e.g.
        // before the read_at migration has been run).
        Task { try? await MessageService.markRead(from: friendID, currentUserID: userID) }
    }

    /// Recomputes how many messages from each friend have arrived since the last
    /// time the signed-in user opened that conversation on this device, and
    /// refreshes the latest-message previews for the Messages tab — both from
    /// a single fetch.
    @MainActor
    func loadUnreadCounts() async {
        guard let userID = currentUserID, SupabaseREST.hasSession else { return }
        do {
            let rows = try await MessageService.recent(currentUserID: userID)
            var counts: [UUID: Int] = [:]
            var previews: [UUID: ConversationPreview] = [:]
            for row in rows {
                let mine = row.isMine(currentUserID: userID)
                guard let friendUUID = UUID(uuidString: mine ? row.recipient_id : row.sender_id) else { continue }
                // Rows arrive newest first, so the first row per friend wins.
                if previews[friendUUID] == nil {
                    previews[friendUUID] = ConversationPreview(body: row.body, date: row.created_at, isMine: mine)
                }
                // Only received messages can be unread.
                guard !mine else { continue }
                // A conversation that's open on screen is read by definition.
                if friendUUID == activeChatFriendID { continue }
                // Cross-device: anything stamped read in the cloud stays read.
                if row.read_at != nil { continue }
                if row.created_at > lastRead(for: friendUUID) {
                    counts[friendUUID, default: 0] += 1
                }
            }
            unreadByFriend = counts
            conversationPreviews = previews
        } catch {
            // Non-fatal: leave the previous counts in place on a transient failure.
        }
    }

    /// Public helper so views building `Connection`s (e.g. search results) get
    /// the same deterministic avatar color everywhere.
    static func avatarColor(for id: String) -> ConnectionColor {
        color(for: id)
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

    /// Every visible memory that includes the given person (as owner or guest).
    func memoriesInvolving(_ connectionID: UUID) -> [Memory] {
        memories.filter { memory in
            memory.connections.contains { $0.id == connectionID }
        }
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
