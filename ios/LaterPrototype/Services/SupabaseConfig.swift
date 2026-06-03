import Foundation

/// Public Supabase configuration with committed fallbacks.
///
/// `Config.swift` only has real values when the app is built by the managed
/// build pipeline — in a standalone Xcode checkout those strings are empty. The
/// Supabase project URL and the **anon** key are public client values (safe to
/// embed in client code), so paste them into the two fallbacks below to make
/// local device builds work without depending on the injected `Config`.
///
/// Find both in your Supabase dashboard → Project Settings → API:
/// - Project URL  →  `fallbackURL`     (e.g. https://abcdxyz.supabase.co)
/// - anon public  →  `fallbackAnonKey`
enum SupabaseConfig {
    /// Paste your Supabase Project URL here for standalone Xcode builds.
    private static let fallbackURL = "https://idpqqafwmjbbfyxxbaur.supabase.co"
    /// Paste your Supabase anon (publishable) key here for standalone Xcode builds.
    private static let fallbackAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlkcHFxYWZ3bWpiYmZ5eHhiYXVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAwNzc5NDgsImV4cCI6MjA5NTY1Mzk0OH0.o8N9ToBRsiFoy7bKzVPzMt1K4HZPfRU59zTjRLceGmo"
    /// Project ID — used to derive the OAuth callback scheme.
    private static let fallbackProjectID = "chtag8o0fjw8t5c1fbvpx"

    // Prioritize the committed fallbacks (your own Supabase project) over the
    // injected values, which point at the auto-provisioned project.
    static var url: String { resolve(fallbackURL, Config.EXPO_PUBLIC_SUPABASE_URL) }
    static var anonKey: String { resolve(fallbackAnonKey, Config.EXPO_PUBLIC_SUPABASE_ANON_KEY) }
    static var projectID: String { resolve(Config.EXPO_PUBLIC_PROJECT_ID, fallbackProjectID) }

    /// The custom URL scheme Supabase redirects back to after web OAuth.
    static var callbackScheme: String { "rork-\(projectID)" }
    static var redirectURL: String { "\(callbackScheme)://auth/callback" }

    /// True when we actually have somewhere to send auth requests.
    static var isConfigured: Bool { !url.isEmpty && !anonKey.isEmpty }

    private static func resolve(_ injected: String, _ fallback: String) -> String {
        let trimmed = injected.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
