import Foundation

/// A media row as stored in Supabase's `memory_media` table.
nonisolated struct CloudMediaRow: Codable, Sendable, Identifiable {
    let id: UUID
    let memory_id: UUID
    let author_id: String
    let kind: String
    let url: String
    let thumbnail_url: String?
    let duration: String?
    /// The memory-inside-a-memory this media is pinned to, when any. Stored on
    /// the shared row so everyone on the memory sees the same placement — no
    /// matter who pinned it.
    let sub_memory_id: UUID?
    let created_at: Date
}

/// High-level operations against the `memory_media` table, which lets the owner
/// of a memory and everyone it's shared with add photos / videos and see each
/// other's.
nonisolated enum MediaService {
    private struct PhotoInsert: Encodable {
        let memory_id: UUID
        let kind: String
        let url: String
        let sub_memory_id: UUID?
    }

    private struct VideoInsert: Encodable {
        let id: UUID
        let memory_id: UUID
        let kind: String
        let url: String
        let thumbnail_url: String
        let duration: String
        let sub_memory_id: UUID?
    }

    /// Patch that always writes `sub_memory_id` — including an explicit null
    /// when unpinning (a synthesized encoder would just omit the nil key).
    private struct SubMemoryPatch: Encodable {
        let sub_memory_id: UUID?

        private enum CodingKeys: String, CodingKey { case sub_memory_id }

        nonisolated func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let sub_memory_id {
                try container.encode(sub_memory_id, forKey: .sub_memory_id)
            } else {
                try container.encodeNil(forKey: .sub_memory_id)
            }
        }
    }

    /// Fetches all media for the given memories, oldest first. RLS already
    /// restricts rows to memories the user can see.
    static func fetch(memoryIDs: [UUID]) async throws -> [CloudMediaRow] {
        guard !memoryIDs.isEmpty else { return [] }
        let ids = memoryIDs.map { $0.uuidString }.joined(separator: ",")
        let data = try await SupabaseREST.request(
            path: "memory_media",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "id,memory_id,author_id,kind,url,thumbnail_url,duration,sub_memory_id,created_at"),
                URLQueryItem(name: "memory_id", value: "in.(\(ids))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CloudMediaRow].self, from: data)
    }

    /// Adds a photo to a memory as the signed-in user, optionally pinned to a
    /// memory inside it.
    static func postPhoto(memoryID: UUID, url: String, subMemoryID: UUID? = nil) async throws {
        let row = PhotoInsert(memory_id: memoryID, kind: "photo", url: url, sub_memory_id: subMemoryID)
        try await SupabaseREST.request(
            path: "memory_media",
            method: "POST",
            body: try SupabaseREST.makeEncoder().encode(row),
            prefer: "return=minimal"
        )
    }

    /// Adds a video to a memory as the signed-in user. The row id matches the
    /// local `VideoAttachment` id so the same video isn't duplicated when other
    /// devices pull it back.
    static func postVideo(memoryID: UUID, id: UUID, url: String, thumbnailURL: String, duration: String, subMemoryID: UUID? = nil) async throws {
        let row = VideoInsert(
            id: id,
            memory_id: memoryID,
            kind: "video",
            url: url,
            thumbnail_url: thumbnailURL,
            duration: duration,
            sub_memory_id: subMemoryID
        )
        try await SupabaseREST.request(
            path: "memory_media",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: try SupabaseREST.makeEncoder().encode(row),
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    private struct MediaURLPatch: Encodable {
        let url: String?
        let thumbnail_url: String?
    }

    /// Repairs a row that was stored with a device-local file path: points it
    /// at the uploaded public URL so everyone on the memory can load it.
    static func updateURLs(id: UUID, url: String?, thumbnailURL: String?) async throws {
        let patch = MediaURLPatch(url: url, thumbnail_url: thumbnailURL)
        try await SupabaseREST.request(
            path: "memory_media",
            method: "PATCH",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            body: try SupabaseREST.makeEncoder().encode(patch),
            prefer: "return=minimal"
        )
    }

    /// Pins / unpins a photo to a memory inside the memory, by updating its
    /// shared media row. Anyone on the memory may do this (same RLS rule that
    /// lets everyone add media).
    static func setPhotoSubMemory(memoryID: UUID, url: String, subMemoryID: UUID?) async throws {
        try await SupabaseREST.request(
            path: "memory_media",
            method: "PATCH",
            query: [
                URLQueryItem(name: "memory_id", value: "eq.\(memoryID.uuidString)"),
                URLQueryItem(name: "kind", value: "eq.photo"),
                URLQueryItem(name: "url", value: "eq.\(url)"),
            ],
            body: try SupabaseREST.makeEncoder().encode(SubMemoryPatch(sub_memory_id: subMemoryID)),
            prefer: "return=minimal"
        )
    }

    /// Pins / unpins a video to a memory inside the memory (row id == the
    /// local `VideoAttachment` id).
    static func setVideoSubMemory(id: UUID, subMemoryID: UUID?) async throws {
        try await SupabaseREST.request(
            path: "memory_media",
            method: "PATCH",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            body: try SupabaseREST.makeEncoder().encode(SubMemoryPatch(sub_memory_id: subMemoryID)),
            prefer: "return=minimal"
        )
    }

    /// Clears every media assignment pointing at a deleted memory-inside so
    /// stale rows can't re-link media to it later.
    static func clearSubMemory(memoryID: UUID, subMemoryID: UUID) async throws {
        try await SupabaseREST.request(
            path: "memory_media",
            method: "PATCH",
            query: [
                URLQueryItem(name: "memory_id", value: "eq.\(memoryID.uuidString)"),
                URLQueryItem(name: "sub_memory_id", value: "eq.\(subMemoryID.uuidString)"),
            ],
            body: try SupabaseREST.makeEncoder().encode(SubMemoryPatch(sub_memory_id: nil)),
            prefer: "return=minimal"
        )
    }

    /// Deletes a photo row by its url (RLS limits this to your own rows).
    static func deletePhoto(memoryID: UUID, url: String) async throws {
        try await SupabaseREST.request(
            path: "memory_media",
            method: "DELETE",
            query: [
                URLQueryItem(name: "memory_id", value: "eq.\(memoryID.uuidString)"),
                URLQueryItem(name: "kind", value: "eq.photo"),
                URLQueryItem(name: "url", value: "eq.\(url)"),
            ],
            prefer: "return=minimal"
        )
    }

    /// Deletes a video row by its id (RLS limits this to your own rows).
    static func deleteVideo(id: UUID) async throws {
        try await SupabaseREST.request(
            path: "memory_media",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            prefer: "return=minimal"
        )
    }
}
