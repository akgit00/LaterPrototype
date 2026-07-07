import Foundation
import CryptoKit
import AuthenticationServices

// MARK: - Web API DTOs

/// Minimal shapes decoded from Spotify's Web API responses. Marked
/// `nonisolated` so decoding can happen off the main actor.
nonisolated struct SpotifyImage: Codable, Sendable {
    let url: String
}

nonisolated struct SpotifyPlaylistRef: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let external_urls: [String: String]?
    let tracks: SpotifyTrackCount?

    nonisolated struct SpotifyTrackCount: Codable, Sendable {
        let total: Int
    }

    var coverURL: String? { images?.first?.url }
    var externalURL: String? { external_urls?["spotify"] }
    var trackTotal: Int { tracks?.total ?? 0 }
}

nonisolated private struct SpotifyPlaylistsPage: Codable, Sendable {
    let items: [SpotifyPlaylistRef]
}

nonisolated private struct SpotifySearchResponse: Codable, Sendable {
    let playlists: PlaylistsContainer?
    nonisolated struct PlaylistsContainer: Codable, Sendable {
        let items: [SpotifyPlaylistRef?]
    }
}

nonisolated private struct SpotifyTracksPage: Codable, Sendable {
    let items: [Item]
    nonisolated struct Item: Codable, Sendable {
        let track: Track?
    }
    nonisolated struct Track: Codable, Sendable {
        let name: String
        let duration_ms: Int?
        let artists: [Artist]?
        let album: Album?
    }
    nonisolated struct Artist: Codable, Sendable { let name: String }
    nonisolated struct Album: Codable, Sendable { let images: [SpotifyImage]? }
}

nonisolated private struct SpotifyTrackResponse: Codable, Sendable {
    let name: String
    let duration_ms: Int?
    let artists: [Artist]?
    let album: Album?
    let external_urls: [String: String]?
    nonisolated struct Artist: Codable, Sendable { let name: String }
    nonisolated struct Album: Codable, Sendable { let images: [SpotifyImage]? }
}

nonisolated private struct SpotifyTokenResponse: Codable, Sendable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

// MARK: - Service

/// Handles Spotify OAuth (Authorization Code + PKCE, no client secret) and the
/// read-only Web API calls used to browse and import the signed-in user's
/// playlists. Tokens are stored in the Keychain.
@MainActor
final class SpotifyService: NSObject {
    static let shared = SpotifyService()

    private let tokenKey = "spotify_access_token"
    private let refreshKey = "spotify_refresh_token"
    private let expiryKey = "spotify_token_expiry"

    private var webAuthSession: ASWebAuthenticationSession?

    nonisolated enum SpotifyError: LocalizedError {
        case notConfigured
        case notAuthenticated
        case noCode
        case http(status: Int, body: String)
        case invalidResponse

        nonisolated var errorDescription: String? {
            switch self {
            case .notConfigured: return "Spotify isn't set up yet. Add your Client ID."
            case .notAuthenticated: return "Connect your Spotify account first."
            case .noCode: return "Spotify didn't return an authorization code."
            case let .http(status, body): return "Spotify error (\(status)): \(body)"
            case .invalidResponse: return "Unexpected response from Spotify."
            }
        }
    }

    /// True when we currently hold a (possibly expired but refreshable) session.
    var isConnected: Bool { KeychainHelper.get(refreshKey) != nil }

    func disconnect() {
        KeychainHelper.delete(tokenKey)
        KeychainHelper.delete(refreshKey)
        KeychainHelper.delete(expiryKey)
    }

    // MARK: - OAuth (PKCE)

    /// Runs the full Authorization Code + PKCE flow in a web auth session and
    /// stores the resulting tokens.
    func connect() async throws {
        guard SpotifyConfig.isConfigured else { throw SpotifyError.notConfigured }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        guard var components = URLComponents(string: "https://accounts.spotify.com/authorize") else {
            throw SpotifyError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes),
        ]
        guard let authURL = components.url else { throw SpotifyError.invalidResponse }

        let callbackURL = try await runWebAuthSession(url: authURL)
        guard
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
            let code = items.first(where: { $0.name == "code" })?.value
        else {
            throw SpotifyError.noCode
        }

        try await exchangeCode(code, verifier: verifier)
    }

    private func runWebAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SpotifyConfig.callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: SpotifyError.noCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            self.webAuthSession = session
            session.presentationContextProvider = WebAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        let token = try await postToken(body: body)
        store(token)
    }

    private func refreshIfNeeded() async throws -> String {
        if let token = KeychainHelper.get(tokenKey), !isExpired() {
            return token
        }
        guard let refresh = KeychainHelper.get(refreshKey) else {
            throw SpotifyError.notAuthenticated
        }
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh),
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
        ]
        let token = try await postToken(body: body)
        store(token, fallbackRefresh: refresh)
        return token.access_token
    }

    private func postToken(body: URLComponents) async throws -> SpotifyTokenResponse {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            throw SpotifyError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    private func store(_ token: SpotifyTokenResponse, fallbackRefresh: String? = nil) {
        KeychainHelper.set(tokenKey, value: token.access_token)
        if let refresh = token.refresh_token ?? fallbackRefresh {
            KeychainHelper.set(refreshKey, value: refresh)
        }
        let expiry = Date().addingTimeInterval(TimeInterval(token.expires_in - 60))
        KeychainHelper.set(expiryKey, value: String(expiry.timeIntervalSince1970))
    }

    private func isExpired() -> Bool {
        guard
            let raw = KeychainHelper.get(expiryKey),
            let seconds = Double(raw)
        else { return true }
        return Date().timeIntervalSince1970 >= seconds
    }

    // MARK: - Web API

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        let token = try await refreshIfNeeded()
        guard var components = URLComponents(string: "https://api.spotify.com/v1/\(path)") else {
            throw SpotifyError.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SpotifyError.invalidResponse }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SpotifyError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SpotifyError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    /// The signed-in user's own playlists.
    func myPlaylists() async throws -> [SpotifyPlaylistRef] {
        let data = try await get("me/playlists", query: [URLQueryItem(name: "limit", value: "50")])
        return try JSONDecoder().decode(SpotifyPlaylistsPage.self, from: data).items
    }

    /// Searches public playlists by text.
    func searchPlaylists(_ term: String) async throws -> [SpotifyPlaylistRef] {
        let data = try await get("search", query: [
            URLQueryItem(name: "q", value: term),
            URLQueryItem(name: "type", value: "playlist"),
            URLQueryItem(name: "limit", value: "30"),
        ])
        let response = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
        return response.playlists?.items.compactMap { $0 } ?? []
    }

    /// Extracts a playlist ID from a Spotify share link or URI.
    /// Handles `https://open.spotify.com/playlist/ID?si=...` and `spotify:playlist:ID`.
    nonisolated static func playlistID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let uriPrefix = "spotify:playlist:"
        if trimmed.hasPrefix(uriPrefix) {
            let id = String(trimmed.dropFirst(uriPrefix.count))
            return id.isEmpty ? nil : id
        }

        guard let components = URLComponents(string: trimmed) else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "playlist"), index + 1 < parts.count else { return nil }
        let id = parts[index + 1]
        return id.isEmpty ? nil : id
    }

    /// Extracts a track ID from a Spotify share link or URI.
    /// Handles `https://open.spotify.com/track/ID?si=...` and `spotify:track:ID`.
    nonisolated static func trackID(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let uriPrefix = "spotify:track:"
        if trimmed.hasPrefix(uriPrefix) {
            let id = String(trimmed.dropFirst(uriPrefix.count))
            return id.isEmpty ? nil : id
        }

        guard let components = URLComponents(string: trimmed) else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "track"), index + 1 < parts.count else { return nil }
        let id = parts[index + 1]
        return id.isEmpty ? nil : id
    }

    /// Resolves a pasted track link/URI into a `PlaylistTrack`, pulling the real
    /// name, artist, and album art from Spotify.
    func importTrack(fromURL urlString: String) async throws -> PlaylistTrack {
        guard let id = Self.trackID(from: urlString) else { throw SpotifyError.invalidResponse }
        let data = try await get("tracks/\(id)")
        let track = try JSONDecoder().decode(SpotifyTrackResponse.self, from: data)
        return PlaylistTrack(
            title: track.name,
            artist: track.artists?.map { $0.name }.joined(separator: ", ") ?? "",
            albumArtURL: track.album?.images?.first?.url,
            duration: Self.formatDuration(track.duration_ms),
            externalURL: track.external_urls?["spotify"]
        )
    }

    /// Resolves a pasted playlist link/URI into a full `PlaylistAttachment`,
    /// pulling the real name, cover, and tracks from Spotify.
    func importPlaylist(fromURL urlString: String) async throws -> PlaylistAttachment {
        guard let id = Self.playlistID(from: urlString) else { throw SpotifyError.invalidResponse }
        let data = try await get("playlists/\(id)", query: [
            URLQueryItem(name: "fields", value: "id,name,images,external_urls,tracks(total)"),
        ])
        let ref = try JSONDecoder().decode(SpotifyPlaylistRef.self, from: data)
        return try await importPlaylist(ref)
    }

    /// Resolves a chosen playlist into a full `PlaylistAttachment` with tracks.
    func importPlaylist(_ ref: SpotifyPlaylistRef) async throws -> PlaylistAttachment {
        let data = try await get("playlists/\(ref.id)/tracks", query: [
            URLQueryItem(name: "limit", value: "50"),
            URLQueryItem(name: "fields", value: "items(track(name,duration_ms,artists(name),album(images)))"),
        ])
        let page = try JSONDecoder().decode(SpotifyTracksPage.self, from: data)
        let tracks: [PlaylistTrack] = page.items.compactMap { item in
            guard let track = item.track else { return nil }
            return PlaylistTrack(
                title: track.name,
                artist: track.artists?.map { $0.name }.joined(separator: ", ") ?? "",
                albumArtURL: track.album?.images?.first?.url,
                duration: Self.formatDuration(track.duration_ms)
            )
        }
        return PlaylistAttachment(
            name: ref.name,
            source: .spotify,
            coverURL: ref.coverURL,
            tracks: tracks,
            externalURL: ref.externalURL
        )
    }

    // MARK: - oEmbed (no sign-in required)

    /// Minimal metadata Spotify exposes publicly for any shared link.
    nonisolated struct OEmbedInfo: Codable, Sendable {
        let title: String
        let thumbnail_url: String?
    }

    /// Fetches a link's public title and cover art via Spotify's oEmbed
    /// endpoint. Works without any Spotify account or API credentials, so a
    /// pasted playlist link always resolves to its real name.
    nonisolated static func fetchOEmbed(for urlString: String) async throws -> OEmbedInfo {
        var components = URLComponents(string: "https://open.spotify.com/oembed")
        components?.queryItems = [URLQueryItem(name: "url", value: urlString)]
        guard let url = components?.url else { throw SpotifyError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpotifyError.invalidResponse
        }
        return try JSONDecoder().decode(OEmbedInfo.self, from: data)
    }

    // MARK: - Helpers

    private static func formatDuration(_ ms: Int?) -> String {
        guard let ms else { return "" }
        let totalSeconds = ms / 1000
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(hash))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
