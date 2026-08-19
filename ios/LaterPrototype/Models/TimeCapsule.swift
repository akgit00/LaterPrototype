import Foundation

/// A sealed message (plus media) delivered on a chosen date, either to the
/// creator's future self or to a friend. Capsules sync through the cloud,
/// where row-level security keeps a capsule invisible to its recipient until
/// the delivery date arrives.
nonisolated struct TimeCapsule: Identifiable, Sendable, Codable {
    let id: UUID
    let title: String
    let message: String
    /// Display name of who the capsule is for ("Future me" or a friend's name).
    let recipient: String
    let deliveryDate: Date
    let createdDate: Date
    /// User id of the creator. Nil only for legacy capsules sealed before
    /// capsules were attached to accounts.
    let senderID: String?
    /// Display name of the creator, shown on received capsules.
    let senderName: String?
    /// User id the capsule is addressed to (the sender's own id for "Future me").
    let recipientID: String?
    /// Sealed-in photos (local file URLs, or public URLs once uploaded).
    let photoURLs: [String]
    /// Sealed-in videos.
    let videos: [VideoAttachment]
    /// An optional song / playlist link sealed with the capsule.
    let songLink: String?

    /// A capsule is delivered once its delivery date has arrived.
    var isDelivered: Bool {
        deliveryDate <= Date()
    }

    /// Number of attachments sealed inside (shown while locked).
    var attachmentCount: Int {
        photoURLs.count + videos.count + (songLink == nil ? 0 : 1)
    }

    /// True when this capsule was sealed by someone else for the given user.
    func isReceived(by userID: String?) -> Bool {
        guard let senderID, let userID else { return false }
        return senderID != userID
    }

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        recipient: String,
        deliveryDate: Date,
        createdDate: Date,
        senderID: String? = nil,
        senderName: String? = nil,
        recipientID: String? = nil,
        photoURLs: [String] = [],
        videos: [VideoAttachment] = [],
        songLink: String? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.recipient = recipient
        self.deliveryDate = deliveryDate
        self.createdDate = createdDate
        self.senderID = senderID
        self.senderName = senderName
        self.recipientID = recipientID
        self.photoURLs = photoURLs
        self.videos = videos
        self.songLink = songLink
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, message, recipient, deliveryDate, createdDate
        case senderID, senderName, recipientID
        case photoURLs, videos, songLink
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        recipient = try container.decode(String.self, forKey: .recipient)
        deliveryDate = try container.decode(Date.self, forKey: .deliveryDate)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        senderID = try container.decodeIfPresent(String.self, forKey: .senderID)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName)
        recipientID = try container.decodeIfPresent(String.self, forKey: .recipientID)
        photoURLs = try container.decodeIfPresent([String].self, forKey: .photoURLs) ?? []
        videos = try container.decodeIfPresent([VideoAttachment].self, forKey: .videos) ?? []
        songLink = try container.decodeIfPresent(String.self, forKey: .songLink)
    }

    /// A copy of this capsule with its media replaced (used after uploads).
    func withMedia(photoURLs: [String], videos: [VideoAttachment]) -> TimeCapsule {
        TimeCapsule(
            id: id,
            title: title,
            message: message,
            recipient: recipient,
            deliveryDate: deliveryDate,
            createdDate: createdDate,
            senderID: senderID,
            senderName: senderName,
            recipientID: recipientID,
            photoURLs: photoURLs,
            videos: videos,
            songLink: songLink
        )
    }

    /// A copy of this capsule attributed to the given user. Used to migrate
    /// legacy capsules (sealed before accounts were attached) into a specific
    /// user's store, addressed to themselves.
    func adopted(by userID: String) -> TimeCapsule {
        TimeCapsule(
            id: id,
            title: title,
            message: message,
            recipient: recipient,
            deliveryDate: deliveryDate,
            createdDate: createdDate,
            senderID: senderID ?? userID,
            senderName: senderName,
            recipientID: recipientID ?? userID,
            photoURLs: photoURLs,
            videos: videos,
            songLink: songLink
        )
    }
}
