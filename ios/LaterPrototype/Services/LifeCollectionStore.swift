import Foundation

/// Persists the user's top-level collections as JSON in the app's Documents
/// directory, so the Collections tab works instantly and offline.
nonisolated enum LifeCollectionStore {
    private static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("life_collections.json")
    }

    /// Loads persisted collections from disk, or nil if none exist or decoding fails.
    static func load() -> [LifeCollection]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([LifeCollection].self, from: data)
        } catch {
            return nil
        }
    }

    /// Persists the given collections to disk (best effort).
    static func save(_ collections: [LifeCollection]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(collections)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort; failures are non-fatal.
        }
    }
}
