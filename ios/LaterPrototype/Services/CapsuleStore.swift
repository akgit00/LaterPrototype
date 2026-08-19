import Foundation

/// Persists time capsules as JSON in the app's Documents directory, scoped
/// per user id so different accounts on the same device never see each
/// other's capsules. All work is `nonisolated` so encoding/decoding stays off
/// the main actor.
nonisolated enum CapsuleStore {
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Per-user capsule cache. User ids are UUIDs, so they're path-safe.
    private static func fileURL(userID: String) -> URL {
        documents.appendingPathComponent("time_capsules_\(userID).json")
    }

    /// The old shared file that every account on this device could read.
    private static var legacyFileURL: URL {
        documents.appendingPathComponent("time_capsules.json")
    }

    /// Per-user file recording capsules the user removed from their list, so
    /// a cloud sync can't bring them back.
    private static func hiddenFileURL(userID: String) -> URL {
        documents.appendingPathComponent("hidden_capsules_\(userID).json")
    }

    /// Loads the ids of capsules this user has removed from their list.
    static func loadHiddenIDs(userID: String) -> Set<UUID> {
        let url = hiddenFileURL(userID: userID)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) else { return [] }
        return ids
    }

    /// Persists the ids of capsules this user has removed from their list.
    static func saveHiddenIDs(_ ids: Set<UUID>, userID: String) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        try? data.write(to: hiddenFileURL(userID: userID), options: .atomic)
    }

    /// Loads the given user's persisted capsules, or nil if none exist.
    static func load(userID: String) -> [TimeCapsule]? {
        load(from: fileURL(userID: userID))
    }

    /// Persists the given user's capsules to their own file.
    static func save(_ capsules: [TimeCapsule], userID: String) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(capsules)
            try data.write(to: fileURL(userID: userID), options: .atomic)
        } catch {
            // Persistence is best-effort; failures are non-fatal.
        }
    }

    /// One-time migration: adopts capsules from the legacy shared file into
    /// the given user's store, then deletes the shared file so other accounts
    /// on this device can no longer see them. Returns the adopted capsules.
    static func migrateLegacyCapsules(to userID: String) -> [TimeCapsule] {
        guard let legacy = load(from: legacyFileURL), !legacy.isEmpty else {
            try? FileManager.default.removeItem(at: legacyFileURL)
            return []
        }
        try? FileManager.default.removeItem(at: legacyFileURL)
        return legacy.map { $0.adopted(by: userID) }
    }

    private static func load(from url: URL) -> [TimeCapsule]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([TimeCapsule].self, from: data)
        } catch {
            return nil
        }
    }
}
