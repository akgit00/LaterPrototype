import Foundation

/// A song row as stored in Supabase's `memory_songs` table. The full
/// `PlaylistTrack` is kept in the `payload` jsonb column.
nonisolated struct CloudSongRow: Codable, Sendable, Identifiable {
    let id: UUID
    let memory_id: UUID
    let payload: PlaylistTrack
}

/// High-level operations against the `memory_songs` table, which lets the owner
/// of a memory and everyone it's shared with add individual songs and see each
/// other's.
nonisolated enum SongService {
    private struct SongInsert: Encodable {
        let id: UUID
        let memory_id: UUID
        let payload: PlaylistTrack
    }

    /// Fetches all songs for the given memories, oldest first. RLS already
    /// restricts rows to memories the user can see.
    static func fetch(memoryIDs: [UUID]) async throws -> [CloudSongRow] {
        guard !memoryIDs.isEmpty else { return [] }
        let ids = memoryIDs.map { $0.uuidString }.joined(separator: ",")
        let data = try await SupabaseREST.request(
            path: "memory_songs",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "id,memory_id,payload"),
                URLQueryItem(name: "memory_id", value: "in.(\(ids))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CloudSongRow].self, from: data)
    }

    /// Adds a song to a memory as the signed-in user. The row id matches the
    /// local `PlaylistTrack` id so the same song isn't duplicated when other
    /// devices pull it back.
    static func post(memoryID: UUID, song: PlaylistTrack) async throws {
        let row = SongInsert(id: song.id, memory_id: memoryID, payload: song)
        try await SupabaseREST.request(
            path: "memory_songs",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: try SupabaseREST.makeEncoder().encode(row),
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// Deletes a song row by its id (RLS limits this to your own rows).
    static func delete(id: UUID) async throws {
        try await SupabaseREST.request(
            path: "memory_songs",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            prefer: "return=minimal"
        )
    }
}
