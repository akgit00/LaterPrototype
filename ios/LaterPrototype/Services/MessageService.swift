import Foundation

/// A direct message row as stored in Supabase.
nonisolated struct MessageRow: Codable, Sendable, Identifiable {
    let id: UUID
    let sender_id: String
    let recipient_id: String
    let body: String
    let created_at: Date

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
    static func conversation(with otherID: String, currentUserID: String) async throws -> [MessageRow] {
        let pair = "\(currentUserID),\(otherID)"
        let data = try await SupabaseREST.request(
            path: "messages",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "id,sender_id,recipient_id,body,created_at"),
                URLQueryItem(name: "sender_id", value: "in.(\(pair))"),
                URLQueryItem(name: "recipient_id", value: "in.(\(pair))"),
                URLQueryItem(name: "order", value: "created_at.asc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([MessageRow].self, from: data)
    }

    /// Fetches every message the signed-in user has received, newest first.
    /// Used to compute per-conversation unread badges. RLS already restricts
    /// rows to ones involving the user.
    static func received(currentUserID: String) async throws -> [MessageRow] {
        let data = try await SupabaseREST.request(
            path: "messages",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "id,sender_id,recipient_id,body,created_at"),
                URLQueryItem(name: "recipient_id", value: "eq.\(currentUserID)"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([MessageRow].self, from: data)
    }
}
