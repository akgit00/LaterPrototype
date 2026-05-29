import Foundation

/// Public auth configuration with committed fallbacks.
///
/// `Config.swift` is auto-generated and its values are only injected during
/// Rork's build pipeline — in a standalone Xcode checkout those strings are
/// empty, which makes the auth base URL blank and produces an "unsupported URL"
/// error at sign-in. These values are public client keys (safe to embed), so we
/// provide them here as a fallback whenever `Config` resolves to an empty string.
enum AuthConfig {
    /// Rork's hosted auth API base URL.
    private static let fallbackAuthURL = "https://api.rork.com"
    /// Public client app key — safe to embed in client code.
    private static let fallbackAppKey = "rpk_5c2zsuspwqzv2rxnc7vlmn7mpvspfuv7"
    /// Project ID — used to derive the OAuth callback scheme.
    private static let fallbackProjectID = "chtag8o0fjw8t5c1fbvpx"

    static var authURL: String { resolve(Config.EXPO_PUBLIC_RORK_AUTH_URL, fallbackAuthURL) }
    static var appKey: String { resolve(Config.EXPO_PUBLIC_RORK_APP_KEY, fallbackAppKey) }
    static var projectID: String { resolve(Config.EXPO_PUBLIC_PROJECT_ID, fallbackProjectID) }

    private static func resolve(_ injected: String, _ fallback: String) -> String {
        let trimmed = injected.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
