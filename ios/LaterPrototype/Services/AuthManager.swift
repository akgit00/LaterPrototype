import SwiftUI
import AuthenticationServices
import CryptoKit

/// Authentication backed by Supabase Auth (GoTrue).
///
/// - Sign in with Apple uses the native flow: Apple returns an identity token
///   on-device, which we exchange with Supabase for a session (no web browser).
/// - Sign in with Google uses Supabase's hosted OAuth flow via
///   `ASWebAuthenticationSession`.
///
/// Sessions persist in the Keychain and are refreshed automatically.
@Observable
class AuthManager {
    var user: User?
    var isLoading = true
    var isSigningIn = false
    var showError = false
    var errorMessage = ""
    /// Informational (non-error) message, e.g. "Check your email to confirm."
    var notice: String?

    private let baseURL = SupabaseConfig.url
    private let anonKey = SupabaseConfig.anonKey
    private var currentNonce: String?
    private var webAuthSession: ASWebAuthenticationSession?

    private let accessKey = "sb_access_token"
    private let refreshKey = "sb_refresh_token"

    struct User: Codable {
        let id: String
        let email: String
        let name: String?
        let picture: String?
    }

    init() {
        Task { await checkAuth() }
    }

    /// Synchronous access token for authenticated Supabase data requests.
    func getAccessToken() -> String? {
        KeychainHelper.get(accessKey)
    }

    // MARK: - Session restore

    @MainActor
    func checkAuth() async {
        defer { isLoading = false }

        if let accessToken = KeychainHelper.get(accessKey),
           let user = userFromToken(accessToken) {
            self.user = user
            return
        }

        if KeychainHelper.get(refreshKey) != nil {
            await refreshSession()
        }
    }

    // MARK: - Apple

    /// Configures the Apple authorization request: scopes + a hashed nonce.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = sha256(nonce)
    }

    @MainActor
    func signInWithApple(_ authorization: ASAuthorization) async {
        guard SupabaseConfig.isConfigured else {
            setError("Supabase isn't configured yet. Add your project URL and anon key.")
            return
        }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            setError("Couldn't read your Apple credentials. Please try again.")
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        // Apple only sends the full name on the very first sign-in.
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        var body: [String: String] = ["provider": "apple", "id_token": idToken]
        if let nonce = currentNonce { body["nonce"] = nonce }
        currentNonce = nil

        await exchangeIDToken(body: body, fallbackName: fullName.isEmpty ? nil : fullName)
    }

    // MARK: - Email + Password

    @MainActor
    func signUpWithEmail(email: String, password: String) async {
        await emailAuth(
            path: "/auth/v1/signup",
            email: email,
            body: ["email": email, "password": password],
            isSignUp: true
        )
    }

    @MainActor
    func signInWithEmail(email: String, password: String) async {
        await emailAuth(
            path: "/auth/v1/token?grant_type=password",
            email: email,
            body: ["email": email, "password": password],
            isSignUp: false
        )
    }

    private func emailAuth(path: String, email: String, body: [String: String], isSignUp: Bool) async {
        guard SupabaseConfig.isConfigured else {
            setError("Supabase isn't configured yet. Add your project URL and anon key.")
            return
        }
        guard let url = URL(string: "\(baseURL)\(path)") else {
            setError("Invalid Supabase URL")
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let (data, http) = try await postRaw(url: url, body: body)
            guard http.statusCode == 200 else {
                throw decodeError(from: data, statusCode: http.statusCode)
            }
            if let session = try? JSONDecoder().decode(SupabaseSession.self, from: data),
               !session.access_token.isEmpty {
                storeSession(accessToken: session.access_token, refreshToken: session.refresh_token)
                user = makeUser(from: session, fallbackName: nil)
            } else if isSignUp {
                // Email confirmation is enabled: no session is returned yet.
                notice = "We sent a confirmation link to \(email). Confirm it, then sign in."
            } else {
                setError("Sign in failed: incomplete session.")
            }
        } catch let error as AuthError {
            setError(error.errorDescription ?? "Sign in failed")
        } catch {
            setError("Sign in failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Email one-time code (magic link / OTP)

    /// Sends a one-time login code / magic link to the given email.
    /// Returns `true` if the email was dispatched successfully.
    @MainActor
    func sendEmailCode(email: String) async -> Bool {
        guard SupabaseConfig.isConfigured else {
            setError("Supabase isn't configured yet. Add your project URL and anon key.")
            return false
        }
        guard let url = URL(string: "\(baseURL)/auth/v1/otp") else {
            setError("Invalid Supabase URL")
            return false
        }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            // `create_user` must be a real JSON boolean — sending it as the
            // string "true" makes GoTrue reject the request with a 400.
            let (data, http) = try await postJSON(
                url: url,
                json: ["email": email, "create_user": true]
            )
            guard http.statusCode == 200 else {
                throw decodeError(from: data, statusCode: http.statusCode)
            }
            return true
        } catch let error as AuthError {
            setError(error.errorDescription ?? "Couldn't send the code")
            return false
        } catch {
            setError("Couldn't send the code: \(error.localizedDescription)")
            return false
        }
    }

    /// Verifies the 6-digit code the user received by email.
    @MainActor
    func verifyEmailCode(email: String, code: String) async {
        guard let url = URL(string: "\(baseURL)/auth/v1/verify") else {
            setError("Invalid Supabase URL")
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let (data, http) = try await postRaw(
                url: url,
                body: ["email": email, "token": code, "type": "email"]
            )
            guard http.statusCode == 200 else {
                throw decodeError(from: data, statusCode: http.statusCode)
            }
            let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
            storeSession(accessToken: session.access_token, refreshToken: session.refresh_token)
            user = makeUser(from: session, fallbackName: nil)
        } catch let error as AuthError {
            setError(error.errorDescription ?? "Invalid or expired code")
        } catch {
            setError("Invalid or expired code. Please try again.")
        }
    }

    // MARK: - Google

    @MainActor
    func signIn(provider: String) async {
        // Apple has its own native entry point; this handles Google (and any
        // other browser-based provider).
        guard SupabaseConfig.isConfigured else {
            setError("Supabase isn't configured yet. Add your project URL and anon key.")
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        guard var components = URLComponents(string: "\(baseURL)/auth/v1/authorize") else {
            setError("Invalid Supabase URL")
            return
        }
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: SupabaseConfig.redirectURL),
        ]

        guard let authURL = components.url else {
            setError("Invalid Supabase URL")
            return
        }

        do {
            let callbackURL = try await runWebAuthSession(url: authURL)
            await handleOAuthCallback(callbackURL)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            setError(error.localizedDescription)
        }
    }

    private func runWebAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SupabaseConfig.callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AuthError.noCode)
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

    /// Supabase returns tokens in the URL fragment (implicit flow).
    @MainActor
    private func handleOAuthCallback(_ url: URL) async {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            setError("Sign in failed: no session returned.")
            return
        }

        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            }
        }

        if let errorDescription = params["error_description"] {
            setError(errorDescription.replacingOccurrences(of: "+", with: " "))
            return
        }

        guard let accessToken = params["access_token"],
              let refreshToken = params["refresh_token"] else {
            setError("Sign in failed: incomplete session.")
            return
        }

        storeSession(accessToken: accessToken, refreshToken: refreshToken)
        user = userFromToken(accessToken)
    }

    // MARK: - Token exchange & refresh

    @MainActor
    private func exchangeIDToken(body: [String: String], fallbackName: String?) async {
        guard let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=id_token") else {
            setError("Invalid Supabase URL")
            return
        }

        do {
            let session = try await postSession(url: url, body: body)
            storeSession(accessToken: session.access_token, refreshToken: session.refresh_token)
            user = makeUser(from: session, fallbackName: fallbackName)
        } catch let error as AuthError {
            setError(error.errorDescription ?? "Sign in failed")
        } catch {
            setError("Sign in failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshSession() async {
        guard let refreshToken = KeychainHelper.get(refreshKey),
              let url = URL(string: "\(baseURL)/auth/v1/token?grant_type=refresh_token") else {
            await signOut()
            return
        }

        do {
            let session = try await postSession(url: url, body: ["refresh_token": refreshToken])
            storeSession(accessToken: session.access_token, refreshToken: session.refresh_token)
            user = makeUser(from: session, fallbackName: nil)
        } catch {
            await signOut()
        }
    }

    private func postSession(url: URL, body: [String: String]) async throws -> SupabaseSession {
        let (data, http) = try await postRaw(url: url, body: body)
        guard http.statusCode == 200 else {
            throw decodeError(from: data, statusCode: http.statusCode)
        }
        return try JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    /// Performs a POST to a Supabase auth endpoint and returns the raw response.
    private func postRaw(url: URL, body: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.serverError(statusCode: -1)
        }
        return (data, http)
    }

    /// POSTs an arbitrary JSON object (preserving value types such as Bool)
    /// to a Supabase auth endpoint and returns the raw response.
    private func postJSON(url: URL, json: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.serverError(statusCode: -1)
        }
        return (data, http)
    }

    private func decodeError(from data: Data, statusCode: Int) -> AuthError {
        if let err = try? JSONDecoder().decode(SupabaseError.self, from: data),
           let message = err.displayMessage {
            return .message(message)
        }
        return .serverError(statusCode: statusCode)
    }

    // MARK: - Sign out

    @MainActor
    func signOut() async {
        if let token = KeychainHelper.get(accessKey),
           let url = URL(string: "\(baseURL)/auth/v1/logout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainHelper.delete(accessKey)
        KeychainHelper.delete(refreshKey)
        user = nil
    }

    // MARK: - Helpers

    private func storeSession(accessToken: String, refreshToken: String) {
        KeychainHelper.set(accessKey, value: accessToken)
        KeychainHelper.set(refreshKey, value: refreshToken)
    }

    private func makeUser(from session: SupabaseSession, fallbackName: String?) -> User? {
        if let sessionUser = session.user {
            let meta = sessionUser.user_metadata
            let name = meta?.full_name ?? meta?.name ?? fallbackName
            let picture = meta?.picture ?? meta?.avatar_url
            return User(id: sessionUser.id, email: sessionUser.email ?? "", name: name, picture: picture)
        }
        return userFromToken(session.access_token)
    }

    /// Decode the JWT payload to extract user info and check expiration.
    private func userFromToken(_ token: String) -> User? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }

        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }

        guard let data = Data(base64Encoded: base64) else { return nil }

        struct JWTPayload: Codable {
            let sub: String
            let email: String?
            let exp: TimeInterval?
            let user_metadata: SupabaseUser.Metadata?
        }

        guard let payload = try? JSONDecoder().decode(JWTPayload.self, from: data) else { return nil }

        if let exp = payload.exp, Date(timeIntervalSince1970: exp) < Date() {
            return nil
        }

        let meta = payload.user_metadata
        let name = meta?.full_name ?? meta?.name
        let picture = meta?.picture ?? meta?.avatar_url
        return User(id: payload.sub, email: payload.email ?? "", name: name, picture: picture)
    }

    private func setError(_ message: String) {
        errorMessage = message
        showError = true
    }

    // MARK: - Nonce / hashing

    private func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Response Types

nonisolated private struct SupabaseSession: Codable, Sendable {
    let access_token: String
    let refresh_token: String
    let user: SupabaseUser?
}

nonisolated private struct SupabaseUser: Codable, Sendable {
    let id: String
    let email: String?
    let user_metadata: Metadata?

    struct Metadata: Codable, Sendable {
        let full_name: String?
        let name: String?
        let picture: String?
        let avatar_url: String?
    }
}

nonisolated private struct SupabaseError: Codable, Sendable {
    let error: String?
    let error_description: String?
    let msg: String?
    let message: String?

    var displayMessage: String? {
        error_description ?? msg ?? error
    }
}

enum AuthError: LocalizedError {
    case noCode
    case invalidURL
    case serverError(statusCode: Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .noCode: return "No session returned"
        case .invalidURL: return "Invalid URL"
        case .serverError(let code): return "Sign in failed (\(code))"
        case .message(let text): return text
        }
    }
}

// MARK: - ASWebAuthenticationSession Helper

class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
