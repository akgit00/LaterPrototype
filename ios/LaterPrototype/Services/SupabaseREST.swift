import Foundation

/// Low-level Supabase REST (PostgREST) + Storage client.
///
/// Reads the current access token from the Keychain (written by `AuthManager`)
/// so every request is authenticated as the signed-in user. All work is
/// `nonisolated` so encoding/decoding and networking stay off the main actor.
nonisolated enum SupabaseREST {
    /// Keychain key under which `AuthManager` stores the Supabase access token.
    static let accessTokenKey = "sb_access_token"
    /// Public bucket that holds memory photos, videos, and thumbnails.
    static let mediaBucket = "memory-media"

    enum RESTError: LocalizedError {
        case notConfigured
        case notAuthenticated
        case http(status: Int, body: String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Cloud storage isn't configured yet."
            case .notAuthenticated: return "You need to be signed in to sync."
            case let .http(status, body): return "Server error (\(status)): \(body)"
            case .invalidResponse: return "Unexpected server response."
            }
        }
    }

    private static var baseURL: String { SupabaseConfig.url }
    private static var anonKey: String { SupabaseConfig.anonKey }

    static var hasSession: Bool { KeychainHelper.get(accessTokenKey) != nil }

    private static func accessToken() throws -> String {
        guard SupabaseConfig.isConfigured else { throw RESTError.notConfigured }
        guard let token = KeychainHelper.get(accessTokenKey) else { throw RESTError.notAuthenticated }
        return token
    }

    /// JSON coder configured to round-trip `Date` values as ISO-8601 strings.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - PostgREST

    /// Performs a PostgREST data request and returns the raw response body.
    @discardableResult
    static func request(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        let token = try accessToken()

        guard var components = URLComponents(string: "\(baseURL)/rest/v1/\(path)") else {
            throw RESTError.invalidResponse
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw RESTError.invalidResponse }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw RESTError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw RESTError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    // MARK: - Storage

    /// Uploads raw data to the public media bucket and returns its public URL.
    static func uploadMedia(_ data: Data, path: String, contentType: String) async throws -> String {
        let token = try accessToken()
        guard let url = URL(string: "\(baseURL)/storage/v1/object/\(mediaBucket)/\(path)") else {
            throw RESTError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")

        let (respData, response) = try await URLSession.shared.upload(for: req, from: data)
        guard let http = response as? HTTPURLResponse else { throw RESTError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw RESTError.http(status: http.statusCode, body: String(data: respData, encoding: .utf8) ?? "")
        }
        return "\(baseURL)/storage/v1/object/public/\(mediaBucket)/\(path)"
    }
}
