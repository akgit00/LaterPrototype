import Foundation

/// A connection (friendship) row as stored in Supabase.
nonisolated struct ConnectionRow: Codable, Sendable, Identifiable {
    let id: UUID
    let requester_id: String
    let addressee_id: String
    let status: String

    /// The id of the other person, given the current user's id.
    func otherID(currentUserID: String) -> String {
        requester_id == currentUserID ? addressee_id : requester_id
    }
}

/// High-level operations against the `connections` table that back the
/// friends / connection-request system.
nonisolated enum ConnectionService {
    private struct RequestInsert: Encodable {
        let requester_id: String
        let addressee_id: String
        let status: String
    }

    private struct StatusUpdate: Encodable {
        let status: String
    }

    /// Sends a connection request from the signed-in user to `addresseeID`.
    static func sendRequest(from requesterID: String, to addresseeID: String) async throws {
        let row = RequestInsert(requester_id: requesterID, addressee_id: addresseeID, status: "pending")
        let body = try SupabaseREST.makeEncoder().encode(row)
        try await SupabaseREST.request(
            path: "connections",
            method: "POST",
            body: body,
            prefer: "return=minimal"
        )
    }

    /// Fetches every connection row involving the signed-in user (RLS scopes it).
    static func fetchConnections() async throws -> [ConnectionRow] {
        let data = try await SupabaseREST.request(
            path: "connections",
            method: "GET",
            query: [URLQueryItem(name: "select", value: "id,requester_id,addressee_id,status")]
        )
        return try SupabaseREST.makeDecoder().decode([ConnectionRow].self, from: data)
    }

    /// Marks a pending request as accepted (only the addressee may do this).
    static func accept(id: UUID) async throws {
        let body = try SupabaseREST.makeEncoder().encode(StatusUpdate(status: "accepted"))
        try await SupabaseREST.request(
            path: "connections",
            method: "PATCH",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            body: body,
            prefer: "return=minimal"
        )
    }

    /// Removes a connection row (declines a request or removes a friend).
    static func remove(id: UUID) async throws {
        try await SupabaseREST.request(
            path: "connections",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            prefer: "return=minimal"
        )
    }

    /// Bulk-fetches profiles for the given user ids (used to resolve names/usernames).
    static func profiles(ids: [String]) async throws -> [CloudProfile] {
        guard !ids.isEmpty else { return [] }
        let list = ids.joined(separator: ",")
        let data = try await SupabaseREST.request(
            path: "profiles",
            method: "GET",
            query: [
                URLQueryItem(name: "id", value: "in.(\(list))"),
                URLQueryItem(name: "select", value: "id,username,display_name,email"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CloudProfile].self, from: data)
    }
}
