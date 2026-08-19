import Foundation

/// A time-capsule row as stored in Supabase.
nonisolated struct CapsuleRow: Codable, Sendable {
    let id: UUID
    let sender_id: String
    let recipient_id: String
    let payload: TimeCapsule
}

/// Cloud operations for time capsules. Rows are protected by row-level
/// security: the sender always sees their own capsules, while a recipient can
/// only fetch a capsule once its delivery date has passed — sealed contents
/// never leave the server early.
nonisolated enum CapsuleService {
    private struct CapsuleUpsert: Encodable {
        let id: UUID
        let sender_id: String
        let recipient_id: String
        let deliver_at: Date
        let payload: TimeCapsule
    }

    /// Fetches every capsule the user is allowed to see: ones they sealed
    /// plus ones delivered to them (RLS scopes the rows).
    static func fetchCapsules() async throws -> [CapsuleRow] {
        let data = try await SupabaseREST.request(
            path: "time_capsules",
            method: "GET",
            query: [
                URLQueryItem(name: "select", value: "id,sender_id,recipient_id,payload"),
                URLQueryItem(name: "order", value: "created_at.desc"),
            ]
        )
        return try SupabaseREST.makeDecoder().decode([CapsuleRow].self, from: data)
    }

    /// Creates or updates a capsule row (only the sender may do this).
    static func upsertCapsule(_ capsule: TimeCapsule, senderID: String, recipientID: String) async throws {
        let row = CapsuleUpsert(
            id: capsule.id,
            sender_id: senderID,
            recipient_id: recipientID,
            deliver_at: capsule.deliveryDate,
            payload: capsule
        )
        let body = try SupabaseREST.makeEncoder().encode(row)
        try await SupabaseREST.request(
            path: "time_capsules",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: body,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// Deletes a capsule (row-level security only allows the sender to).
    static func deleteCapsule(id: UUID) async throws {
        try await SupabaseREST.request(
            path: "time_capsules",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")],
            prefer: "return=minimal"
        )
    }

    /// Replaces every local file URL inside a capsule with an uploaded public
    /// URL so the recipient's device can load the media. Falls back to the
    /// original URL when an upload fails (retried on the next sync).
    static func uploadingLocalMedia(in capsule: TimeCapsule, userID: String) async -> TimeCapsule {
        var newPhotos: [String] = []
        for url in capsule.photoURLs {
            newPhotos.append(await uploadIfLocal(url, userID: userID, capsuleID: capsule.id))
        }

        var newVideos: [VideoAttachment] = []
        for video in capsule.videos {
            let thumb = await uploadIfLocal(video.thumbnailURL, userID: userID, capsuleID: capsule.id)
            var uploadedVideo: String? = video.videoURL
            if let original = video.videoURL {
                uploadedVideo = await uploadIfLocal(original, userID: userID, capsuleID: capsule.id)
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

        return capsule.withMedia(photoURLs: newPhotos, videos: newVideos)
    }

    private static func uploadIfLocal(_ urlString: String, userID: String, capsuleID: UUID) async -> String {
        guard let url = URL(string: urlString), url.isFileURL,
              let data = try? Data(contentsOf: url) else { return urlString }
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let lowered = ext.lowercased()
        let contentType = (lowered == "mov" || lowered == "mp4") ? "video/\(lowered)" : "image/jpeg"
        let path = "\(userID)/capsules/\(capsuleID.uuidString)/\(UUID().uuidString).\(ext)"
        return (try? await SupabaseREST.uploadMedia(data, path: path, contentType: contentType)) ?? urlString
    }
}
