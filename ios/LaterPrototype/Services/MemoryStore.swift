import Foundation

/// Persists the user's memories as JSON in the app's Documents directory.
/// All work is `nonisolated` so encoding/decoding stays off the main actor.
nonisolated enum MemoryStore {
    private static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("memories.json")
    }

    /// Tracks whether the app has seeded its initial sample data.
    static var hasSeeded: Bool {
        get { UserDefaults.standard.bool(forKey: "hasSeededMemories") }
        set { UserDefaults.standard.set(newValue, forKey: "hasSeededMemories") }
    }

    /// Loads persisted memories from disk, or nil if none exist or decoding fails.
    static func load() -> [Memory]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Memory].self, from: data)
        } catch {
            return nil
        }
    }

    /// Persists the given memories to disk.
    static func save(_ memories: [Memory]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(memories)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort; failures are non-fatal.
        }
    }
}
