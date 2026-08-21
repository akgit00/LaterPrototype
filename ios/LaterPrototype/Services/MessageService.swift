import Foundation

/// A direct message row as stored in Supabase.
nonisolated struct MessageRow: Codable, Sendable, Identifiable {
    let id: UUID
    let sender_id: String
    let recipient_id: String
    let body: String
    let created_at: Date
    /// When the recipient read this message; nil until then (or when the
    /// recipient keeps read receipts off).
    let read_at: Date?

    /// Whether this message was sent by the signed-in user.
    func isMine(currentUserID: String) -> Bool {
        sender_id == currentUserID
    }
}

/// High-level operations against the `messages` table that back 1:1 chat
/// between connected friends.
nonisolated enum MessageService {
    private struct MessageInsert: Encodable {
        let recipient_id: String
        let body: String
    }

    /// Sends a message from the signed-in user to `recipientID`.
    /// `sender_id` defaults to `auth.uid()` server-side.
    @discardableResult
    static func send(to recipientID: String, body: String) async throws -> MessageRow? {
        let row = MessageInsert(recipient_id: recipientID, body: body)
        let data = try await SupabaseREST.request(
            path: "messages",
            method: "POST",
            body: try SupabaseREST.makeEncoder().encode(row),
            prefer: "return=representation"
        )
        return try SupabaseREST.makeDecoder().decode([MessageRow].self, from: data).first
    }

    /// Fetches the conversation between the signed-in user and `otherID`,
    /// oldest first. RLS already restricts rows to ones involving the user, so
    /// we just filter to the messages exchanged with this specific person.
    /// Selects `*` so the app keeps working whether or not the `read_at`
    /// migration has run yet.
    static func conversation(with otherID: String, currentUserID: String) async throws -> [MessageRow] {
        let pair = "\(currentUserID),\(otherID)"
        let data = try await SupabaseREST.request(
            path: "messages",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "sender_id", value: "in.(\(pair))"),
                URLQueryItem(name: "recipient_id", value: "in.(\(pair))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([MessageRow].self, from: data)
    }

    private struct ReadPatch: Encodable {
        let read_at: Date
    }

    /// Marks every unread message from `senderID` to the signed-in user as
    /// read right now. Drives the sender's "Read" receipt; RLS restricts the
    /// update to the recipient's own received messages (read_at column only).
    static func markRead(from senderID: String, currentUserID: String) async throws {
        let body = try SupabaseREST.makeEncoder().encode(ReadPatch(read_at: Date()))
        try await SupabaseREST.request(
            path: "messages",
            method: "PATCH",
            query: [
                URLQueryItem(name: "sender_id", value: "eq.\(senderID)"),
                URLQueryItem(name: "recipient_id", value: "eq.\(currentUserID)"),
                URLQueryItem(name: "read_at", value: "is.null"),
            ],
            body: body,
            prefer: "return=minimal"
        )
    }

    /// Fetches the most recent messages involving the signed-in user in either
    /// direction, newest first. RLS already restricts rows to the user's own
    /// conversations. One fetch drives both the unread badges and the
    /// conversation previews on the Messages tab.
    static func recent(currentUserID: String) async throws -> [MessageRow] {
        let data = try await SupabaseREST.request(
            path: "messages",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "or", value: "(sender_id.eq.\(currentUserID),recipient_id.eq.\(currentUserID))"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "500"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([MessageRow].self, from: data)
    }
}
