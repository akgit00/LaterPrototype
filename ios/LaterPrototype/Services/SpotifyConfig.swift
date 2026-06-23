import Foundation

/// Public Spotify app configuration.
///
/// The Client ID is a **public** value (it's embedded in client apps and is not
/// a secret), so it's safe to commit. Get it from your Spotify app at
/// https://developer.spotify.com/dashboard → your app → Settings → Client ID.
///
/// In the Spotify dashboard you must also add this exact Redirect URI:
///   later://spotify-callback
/// and tick the "Web API" box under "Which API/SDKs are you planning to use?".
enum SpotifyConfig {
    /// Paste your Spotify app's **Client ID** here for standalone Xcode builds.
    private static let fallbackClientID = ""

    /// Resolves the injected env value first, then the committed fallback.
    static var clientID: String {
        let injected = (Config.allValues["EXPO_PUBLIC_SPOTIFY_CLIENT_ID"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return injected.isEmpty ? fallbackClientID : injected
    }

    /// Custom URL scheme Spotify redirects back to. Must match the dashboard
    /// Redirect URI **and** the URL scheme registered in the project.
    static let redirectURI = "later://spotify-callback"
    static let callbackScheme = "later"

    /// Read-only scopes needed to list the signed-in user's playlists.
    static let scopes = "playlist-read-private playlist-read-collaborative"

    /// True once a Client ID is available, so the UI can offer connecting.
    static var isConfigured: Bool { !clientID.isEmpty }
}
