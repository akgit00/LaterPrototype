import Foundation

/// What travels inside a collection share link — enough to rebuild the
/// collection on the recipient's device. Memory IDs only resolve to memories
/// the recipient can actually see (their own, or ones shared with them).
nonisolated struct SharedCollectionPayload: Codable, Sendable, Equatable, Identifiable {
    let name: String
    let emoji: String
    let colorName: String
    let memoryIDs: [UUID]

    var id: String {
        "\(name)|\(memoryIDs.count)|\(memoryIDs.first?.uuidString ?? "empty")"
    }

    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case emoji = "e"
        case colorName = "c"
        case memoryIDs = "m"
    }
}

/// Encodes collections into `laterprototype://collection?d=...` deep links
/// and back. The payload is fully self-contained (base64url JSON), so links
/// work offline, never expire, and need no server round trip.
nonisolated enum CollectionShareCodec {
    static let scheme = "laterprototype"
    private static let host = "collection"

    /// The tappable deep link for one collection.
    static func shareURL(for collection: LifeCollection) -> URL? {
        let payload = SharedCollectionPayload(
            name: collection.name,
            emoji: collection.emoji,
            colorName: collection.colorName,
            memoryIDs: collection.memoryIDs
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "d", value: base64URLEncode(data))]
        return components.url
    }

    /// The share-sheet message wrapping the link, so recipients know what to
    /// do with it even where the link isn't tappable.
    static func shareMessage(for collection: LifeCollection) -> String? {
        guard let url = shareURL(for: collection) else { return nil }
        return "Import my \"\(collection.name)\" collection in Later — open the link (or copy this message and tap Import on the Collections tab):\n\(url.absoluteString)"
    }

    /// Decodes a tapped deep link back into a payload.
    static func decode(url: URL) -> SharedCollectionPayload? {
        guard url.scheme?.lowercased() == scheme,
              url.host()?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "d" })?.value,
              let data = base64URLDecode(encoded) else { return nil }
        return try? JSONDecoder().decode(SharedCollectionPayload.self, from: data)
    }

    /// Finds and decodes a share link pasted anywhere inside free text (the
    /// clipboard import path for chats where the link isn't tappable).
    static func decode(text: String) -> SharedCollectionPayload? {
        for raw in text.split(whereSeparator: \.isWhitespace) {
            if let url = URL(string: String(raw)), let payload = decode(url: url) {
                return payload
            }
        }
        return nil
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
