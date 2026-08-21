import Foundation

/// A row in Supabase's `memory_extras` table — the shared home for story
/// entries, voice notes, sealed notes, polls, votes, prompts, answers, and
/// keepsakes. Like comments, these live in their own table so EVERYONE on a
/// memory can contribute (only the owner may update the memory payload).
nonisolated struct MemoryExtraRow: Codable, Sendable, Identifiable {
    let id: UUID
    let memory_id: UUID
    let author_id: String
    let author_name: String
    let kind: String
    /// JSON-encoded payload for this kind (see the payload structs in
    /// MemoryExtras.swift).
    let payload: String
    let created_at: Date

    /// A copy of this row carrying a different payload (fields are lets).
    func withPayload(_ newPayload: String) -> MemoryExtraRow {
        MemoryExtraRow(
            id: id,
            memory_id: memory_id,
            author_id: author_id,
            author_name: author_name,
            kind: kind,
            payload: newPayload,
            created_at: created_at
        )
    }
}

/// Row kinds stored in `memory_extras`.
nonisolated enum MemoryExtraKind {
    static let story = "story"
    static let voice = "voice"
    static let sealed = "sealed"
    static let poll = "poll"
    static let pollVote = "poll_vote"
    static let prompt = "prompt"
    static let promptAnswer = "prompt_answer"
    static let keepsake = "keepsake"
}

/// CRUD against the `memory_extras` table. RLS mirrors comments: anyone the
/// memory is shared with can read and add; authors manage their own rows and
/// the memory owner can moderate.
nonisolated enum MemoryExtrasService {
    private struct Insert: Encodable {
        let id: UUID
        let memory_id: UUID
        let author_name: String
        let kind: String
        let payload: String
    }

    private struct PayloadPatch: Encodable {
        let payload: String
    }

    /// Fetches all extras for the given memories, oldest first.
    static func fetch(memoryIDs: [UUID]) async throws -> [MemoryExtraRow] {
        guard !memoryIDs.isEmpty else { return [] }
        let ids = memoryIDs.map { $0.uuidString }.joined(separator: ",")
        let data = try await SupabaseREST.request(
            path: "memory_extras",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "id,memory_id,author_id,author_name,kind,payload,created_at"),
                URLQueryItem(name: "memory_id", value: "in.(\(ids))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([MemoryExtraRow].self, from: data)
    }

    /// Inserts a new extra as the signed-in user. The client supplies the row
    /// id so optimistic local state and the server row always agree.
    static func post(_ row: MemoryExtraRow) async throws {
        let insert = Insert(
            id: row.id,
            memory_id: row.memory_id,
            author_name: row.author_name,
            kind: row.kind,
            payload: row.payload
        )
        try await SupabaseREST.request(
            path: "memory_extras",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: try SupabaseREST.makeEncoder().encode(insert),
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// Replaces a row's payload (RLS limits this to your own rows) — used for
    /// editing a story entry, changing a vote, or rewriting an answer.
    static func updatePayload(id: UUID, payload: String) async throws {
        try await SupabaseREST.request(
            path: "memory_extras",
            method: "PATCH",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            body: try SupabaseREST.makeEncoder().encode(PayloadPatch(payload: payload)),
            prefer: "return=minimal"
        )
    }

    /// Deletes a row (RLS: your own rows, or any row on a memory you own).
    static func delete(id: UUID) async throws {
        try await SupabaseREST.request(
            path: "memory_extras",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            prefer: "return=minimal"
        )
    }
}
