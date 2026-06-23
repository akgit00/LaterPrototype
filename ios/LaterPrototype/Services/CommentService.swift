import Foundation

/// A comment row as stored in Supabase's `memory_comments` table.
nonisolated struct CloudCommentRow: Codable, Sendable, Identifiable {
    let id: UUID
    let memory_id: UUID
    let author_id: String
    let username: String
    let text: String
    let created_at: Date
}

/// High-level operations against the `memory_comments` table, which lets the
/// owner of a memory and everyone it's shared with comment on it.
nonisolated enum CommentService {
    private struct CommentInsert: Encodable {
        let memory_id: UUID
        let username: String
        let text: String
    }

    /// Fetches all comments for the given memories, oldest first. RLS already
    /// restricts rows to memories the user can see.
    static func fetch(memoryIDs: [UUID]) async throws -> [CloudCommentRow] {
        guard !memoryIDs.isEmpty else { return [] }
        let ids = memoryIDs.map { $0.uuidString }.joined(separator: ",")
        let data = try await SupabaseREST.request(
            path: "memory_comments",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "id,memory_id,author_id,username,text,created_at"),
                URLQueryItem(name: "memory_id", value: "in.(\(ids))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CloudCommentRow].self, from: data)
    }

    /// Posts a comment to a memory as the signed-in user. `author_id` defaults
    /// to `auth.uid()` server-side.
    @discardableResult
    static func post(memoryID: UUID, username: String, text: String) async throws -> CloudCommentRow? {
        let row = CommentInsert(memory_id: memoryID, username: username, text: text)
        let data = try await SupabaseREST.request(
            path: "memory_comments",
            method: "POST",
            body: try SupabaseREST.makeEncoder().encode(row),
            prefer: "return=representation"
        )
        return try SupabaseREST.makeDecoder().decode([CloudCommentRow].self, from: data).first
    }
}
