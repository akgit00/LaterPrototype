import Foundation

/// A profile row used to look up friends and identify the current user.
nonisolated struct CloudProfile: Codable, Sendable, Identifiable {
    let id: String
    let username: String
    let display_name: String?
    let email: String?
    let bio: String?
    let avatar_url: String?

    /// Minimal projection used for existence checks (selects only `id`).
    nonisolated struct Stub: Codable, Sendable {
        let id: String
    }
}

/// A memory row as stored in Supabase: the encoded `Memory` plus its owner.
nonisolated struct CloudMemoryRow: Codable, Sendable {
    let id: UUID
    let owner_id: String
    let payload: Memory
}

/// High-level operations against the Supabase tables that back memory sharing.
nonisolated enum CloudMemoryService {
    private struct MemoryUpsert: Encodable {
        let id: UUID
        let owner_id: String
        let payload: Memory
        let updated_at: String
    }

    private struct ProfileUpsert: Encodable {
        let id: String
        let username: String
        let email: String
        let display_name: String
    }

    private struct ShareRow: Encodable {
        let memory_id: UUID
        let owner_id: String
        let shared_with: String
    }

    // MARK: - Profiles

    /// Ensures the signed-in user has a profile row so friends can find them,
    /// assigning a globally unique username. The `profiles.username` column has
    /// a unique constraint, so a collision surfaces as an HTTP 409; we keep
    /// generating fresh candidates until one is accepted.
    static func ensureProfile(userID: String, email: String, displayName: String?) async {
        if let existing = try? await fetchProfile(id: userID), existing != nil { return }

        let base = usernameBase(from: email, fallback: userID)
        let name = displayName?.isEmpty == false ? displayName! : base

        for candidate in usernameCandidates(base: base) {
            // Skip names we can already see are taken to reduce wasted inserts.
            if (try? await isUsernameTaken(candidate)) == true { continue }

            let row = ProfileUpsert(id: userID, username: candidate, email: email.lowercased(), display_name: name)
            guard let body = try? SupabaseREST.makeEncoder().encode(row) else { continue }
            do {
                try await SupabaseREST.request(
                    path: "profiles",
                    method: "POST",
                    body: body,
                    prefer: "return=minimal"
                )
                return
            } catch let SupabaseREST.RESTError.http(status, _) where status == 409 {
                // Username (or profile) taken between our check and insert — try the next candidate.
                continue
            } catch {
                continue
            }
        }
    }

    /// Returns true if a profile already uses the given username (case-insensitive).
    static func isUsernameTaken(_ username: String) async throws -> Bool {
        let normalized = username.lowercased()
        let data = try await SupabaseREST.request(
            path: "profiles",
            method: "GET",
            query: [
                URLQueryItem(name: "username", value: "eq.\(normalized)"),
                URLQueryItem(name: "select", value: "id"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return try !SupabaseREST.makeDecoder().decode([CloudProfile.Stub].self, from: data).isEmpty
    }

    /// An ordered, effectively-infinite sequence of unique-ish username
    /// candidates: the clean base first, then numbered, then random suffixes.
    private static func usernameCandidates(base: String) -> [String] {
        var candidates = [base]
        for n in 1...8 { candidates.append("\(base)\(n)") }
        for _ in 0..<16 {
            let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
            candidates.append("\(base)_\(suffix)")
        }
        return candidates
    }

    static func fetchProfile(id: String) async throws -> CloudProfile? {
        let data = try await SupabaseREST.request(
            path: "profiles",
            method: "GET",
            query: [
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "select", value: "id,username,display_name,email,bio,avatar_url"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CloudProfile].self, from: data).first
    }

    /// Persists the user's editable profile fields (name, bio, avatar) to their
    /// own profile row. Silently ignores failures so the local edit still stands.
    static func updateProfileDetails(userID: String, displayName: String?, bio: String?, avatarURL: String?) async {
        struct DetailsUpdate: Encodable {
            let display_name: String?
            let bio: String?
            let avatar_url: String?
        }
        let row = DetailsUpdate(display_name: displayName, bio: bio, avatar_url: avatarURL)
        guard let body = try? SupabaseREST.makeEncoder().encode(row) else { return }
        try? await SupabaseREST.request(
            path: "profiles",
            method: "PATCH",
            query: [URLQueryItem(name: "id", value: "eq.\(userID)")],
            body: body,
            prefer: "return=minimal"
        )
    }

    /// Uploads a locally-stored avatar image to Storage and returns its public
    /// URL. Returns nil for non-local or already-remote URLs.
    static func uploadAvatar(_ urlString: String, userID: String) async -> String? {
        guard let url = URL(string: urlString), url.isFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let path = "\(userID)/avatar/\(UUID().uuidString).jpg"
        return try? await SupabaseREST.uploadMedia(data, path: path, contentType: "image/jpeg")
    }

    /// Looks up a friend by `@username` or email address, case-insensitively,
    /// so "JohnDoe" finds "@johndoe" no matter how it was typed.
    static func findProfile(identifier rawIdentifier: String) async throws -> CloudProfile? {
        var identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if identifier.hasPrefix("@") { identifier.removeFirst() }
        guard !identifier.isEmpty else { return nil }

        let data = try await SupabaseREST.request(
            path: "profiles",
            method: "GET",
            query: [
                URLQueryItem(name: "or", value: "(username.ilike.\(identifier),email.ilike.\(identifier))"),
                URLQueryItem(name: "select", value: "id,username,display_name,email,avatar_url"),
                URLQueryItem(name: "limit", value: "1"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CloudProfile].self, from: data).first
    }

    // MARK: - Memories

    /// Fetches every memory the user can see: their own plus shared-with-them.
    static func fetchMemories() async throws -> [CloudMemoryRow] {
        let data = try await SupabaseREST.request(
            path: "memories",
            method: "GET",
            query: [URLQueryItem(name: "select", value: "id,owner_id,payload")]
        )
        return try SupabaseREST.makeDecoder().decode([CloudMemoryRow].self, from: data)
    }

    static func upsertMemory(_ memory: Memory, ownerID: String) async throws {
        let iso = ISO8601DateFormatter().string(from: Date())
        let row = MemoryUpsert(id: memory.id, owner_id: ownerID, payload: memory, updated_at: iso)
        let body = try SupabaseREST.makeEncoder().encode(row)
        try await SupabaseREST.request(
            path: "memories",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    static func deleteMemory(id: UUID) async throws {
        try await SupabaseREST.request(
            path: "memories",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            prefer: "return=minimal"
        )
    }

    // MARK: - Shares

    /// A share row as read back from the `memory_shares` table.
    nonisolated struct ShareReadRow: Codable, Sendable {
        let memory_id: UUID
        let shared_with: String
    }

    /// Fetches the share rows for the given memories, so every participant can
    /// see the full, live people list.
    static func fetchShares(memoryIDs: [UUID]) async throws -> [ShareReadRow] {
        guard !memoryIDs.isEmpty else { return [] }
        let ids = memoryIDs.map { $0.uuidString }.joined(separator: ",")
        let data = try await SupabaseREST.request(
            path: "memory_shares",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "memory_id,shared_with"),
                URLQueryItem(name: "memory_id", value: "in.(\(ids))"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([ShareReadRow].self, from: data)
    }

    static func shareMemory(memoryID: UUID, ownerID: String, sharedWith: String) async throws {
        let row = ShareRow(memory_id: memoryID, owner_id: ownerID, shared_with: sharedWith)
        let body = try SupabaseREST.makeEncoder().encode(row)
        try await SupabaseREST.request(
            path: "memory_shares",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "memory_id,shared_with")],
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    static func unshareMemory(memoryID: UUID, sharedWith: String) async throws {
        try await SupabaseREST.request(
            path: "memory_shares",
            method: "DELETE",
            query: [
                URLQueryItem(name: "memory_id", value: "eq.\(memoryID.uuidString)"),
                URLQueryItem(name: "shared_with", value: "eq.\(sharedWith)"),
            ],
            prefer: "return=minimal"
        )
    }

    // MARK: - Media upload

    /// Uploads a local file URL to Storage and returns its public URL. Remote
    /// URLs (already-uploaded or external) are returned unchanged.
    static func uploadIfLocal(_ urlString: String, userID: String, memoryID: UUID) async -> String {
        guard let url = URL(string: urlString), url.isFileURL,
              let data = try? Data(contentsOf: url) else {
            return urlString
        }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let contentType = ext.lowercased() == "mov" || ext.lowercased() == "mp4" ? "video/\(ext.lowercased())" : "image/jpeg"
        let path = "\(userID)/\(memoryID.uuidString)/\(UUID().uuidString).\(ext)"
        do {
            return try await SupabaseREST.uploadMedia(data, path: path, contentType: contentType)
        } catch {
            return urlString
        }
    }

    /// Replaces every local file URL inside a memory with an uploaded public URL.
    static func uploadingLocalMedia(in memory: Memory, userID: String) async -> Memory {
        var updated = memory

        var newPhotos: [String] = []
        for url in updated.photoURLs {
            newPhotos.append(await uploadIfLocal(url, userID: userID, memoryID: memory.id))
        }
        updated.photoURLs = newPhotos

        updated.pins = await withTaskMappedPins(updated.pins, userID: userID, memoryID: memory.id)

        var newVideos: [VideoAttachment] = []
        for video in updated.videos {
            let thumb = await uploadIfLocal(video.thumbnailURL, userID: userID, memoryID: memory.id)
            var uploadedVideo: String? = nil
            if let original = video.videoURL {
                uploadedVideo = await uploadIfLocal(original, userID: userID, memoryID: memory.id)
            }
            newVideos.append(
                VideoAttachment(
                    id: video.id,
                    thumbnailURL: thumb,
                    title: video.title,
                    duration: video.duration,
                    videoURL: uploadedVideo
                )
            )
        }
        updated.videos = newVideos

        return updated
    }

    private static func withTaskMappedPins(_ pins: [MemoryPin], userID: String, memoryID: UUID) async -> [MemoryPin] {
        var result: [MemoryPin] = []
        for pin in pins {
            let image: String?
            if let imageURL = pin.imageURL {
                image = await uploadIfLocal(imageURL, userID: userID, memoryID: memoryID)
            } else {
                image = nil
            }
            result.append(
                MemoryPin(
                    id: pin.id,
                    coordinate: pin.coordinate,
                    title: pin.title,
                    date: pin.date,
                    imageURL: image,
                    intensity: pin.intensity
                )
            )
        }
        return result
    }

    // MARK: - Helpers

    private static func usernameBase(from email: String, fallback: String) -> String {
        let prefix = email.split(separator: "@").first.map(String.init) ?? ""
        let cleaned = prefix.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        if cleaned.count >= 3 { return cleaned }
        return "user_\(fallback.replacingOccurrences(of: "-", with: "").prefix(6))"
    }
}
