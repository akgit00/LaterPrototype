import Foundation

/// A playlist row as stored in Supabase's `memory_playlists` table. The full
/// `PlaylistAttachment` is kept in the `payload` jsonb column.
nonisolated struct CloudPlaylistRow: Codable, Sendable {
    let memory_id: UUID
    let payload: PlaylistAttachment
}

/// High-level operations against the `memory_playlists` table, which lets the
/// owner of a memory and everyone it's shared with attach / update the linked
/// Spotify or Apple Music playlist and see each other's.
nonisolated enum PlaylistService {
    private struct PlaylistUpsert: Encodable {
        let memory_id: UUID
        let payload: PlaylistAttachment
    }

    /// Fetches the playlist for the given memories. RLS already restricts rows
    /// to memories the user can see.
    static func fetch(memoryIDs: [UUID]) async throws -> [CloudPlaylistRow] {
        guard !memoryIDs.isEmpty else { return [] }
        let ids = memoryIDs.map { $0.uuidString }.joined(separator: ",")
        let data = try await SupabaseREST.request(
            path: "memory_playlists",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "memory_id,payload"),
                URLQueryItem(name: "memory_id", value: "in.(\(ids))"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CloudPlaylistRow].self, from: data)
    }

    /// Upserts the playlist for a memory as the signed-in user, keyed by
    /// `memory_id` so there's a single shared playlist per memory.
    static func upsert(memoryID: UUID, playlist: PlaylistAttachment) async throws {
        let row = PlaylistUpsert(memory_id: memoryID, payload: playlist)
        try await SupabaseREST.request(
            path: "memory_playlists",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "memory_id")],
            body: try SupabaseREST.makeEncoder().encode(row),
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// Removes the playlist from a memory.
    static func remove(memoryID: UUID) async throws {
        try await SupabaseREST.request(
            path: "memory_playlists",
            method: "DELETE",
            query: [URLQueryItem(name: "memory_id", value: "eq.\(memoryID.uuidString)")],
            prefer: "return=minimal"
        )
    }
}
