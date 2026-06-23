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
    }

    private struct VideoInsert: Encodable {
        let id: UUID
        let memory_id: UUID
        let kind: String
        let url: String
        let thumbnail_url: String
        let duration: String
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
                URLQueryItem(name: "select", value: "id,memory_id,author_id,kind,url,thumbnail_url,duration,created_at"),
                URLQueryItem(name: "memory_id", value: "in.(\(ids))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CloudMediaRow].self, from: data)
    }

    /// Adds a photo to a memory as the signed-in user.
    static func postPhoto(memoryID: UUID, url: String) async throws {
        let row = PhotoInsert(memory_id: memoryID, kind: "photo", url: url)
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
    static func postVideo(memoryID: UUID, id: UUID, url: String, thumbnailURL: String, duration: String) async throws {
        let row = VideoInsert(
            id: id,
            memory_id: memoryID,
            kind: "video",
            url: url,
            thumbnail_url: thumbnailURL,
            duration: duration
        )
        try await SupabaseREST.request(
            path: "memory_media",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: try SupabaseREST.makeEncoder().encode(row),
            prefer: "resolution=merge-duplicates,return=minimal"
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
