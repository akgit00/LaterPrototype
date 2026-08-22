import Foundation

/// Cloud operations for top-level collections. Rows live in the
/// `user_collections` table and are private to their owner (RLS scoped), so
/// fetching simply returns everything the signed-in user owns.
nonisolated enum LifeCollectionService {
    private struct CollectionReadRow: Codable {
        let id: UUID
        let payload: LifeCollection
    }

    private struct CollectionUpsert: Encodable {
        let id: UUID
        let owner_id: String
        let payload: LifeCollection
        let updated_at: Date
    }

    /// Fetches every collection the user owns, newest first.
    static func fetchAll() async throws -> [LifeCollection] {
        let data = try await SupabaseREST.request(
            path: "user_collections",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "id,payload"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        let rows = try SupabaseREST.makeDecoder().decode([CollectionReadRow].self, from: data)
        return rows.map { $0.payload }
    }

    /// Creates or updates a collection row.
    static func upsert(_ collection: LifeCollection, ownerID: String) async throws {
        let row = CollectionUpsert(
            id: collection.id,
            owner_id: ownerID,
            payload: collection,
            updated_at: Date()
        )
        let body = try SupabaseREST.makeEncoder().encode(row)
        try await SupabaseREST.request(
            path: "user_collections",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// Deletes a collection row (RLS restricts this to the owner).
    static func delete(id: UUID) async throws {
        try await SupabaseREST.request(
            path: "user_collections",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            prefer: "return=minimal"
        )
    }
}
