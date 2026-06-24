import Foundation

/// Persists the user's time capsules as JSON in the app's Documents directory.
/// All work is `nonisolated` so encoding/decoding stays off the main actor.
nonisolated enum CapsuleStore {
    private static var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("time_capsules.json")
    }

    /// Loads persisted capsules from disk, or nil if none exist or decoding fails.
    static func load() -> [TimeCapsule]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([TimeCapsule].self, from: data)
        } catch {
            return nil
        }
    }

    /// Persists the given capsules to disk.
    static func save(_ capsules: [TimeCapsule]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(capsules)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Persistence is best-effort; failures are non-fatal.
        }
    }
}
