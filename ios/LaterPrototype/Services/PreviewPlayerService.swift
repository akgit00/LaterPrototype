import Foundation
import AVFoundation

/// Plays short in-app song clips for the songs and playlist tracks attached to
/// a memory. Preview clips are resolved through the iTunes Search API (30s
/// streams, no account needed) by matching the track's title + artist.
@Observable
final class PreviewPlayerService {
    static let shared = PreviewPlayerService()

    /// The track currently playing (or loading), keyed by `PlaylistTrack.id`.
    private(set) var activeTrackID: UUID?
    private(set) var isLoading = false
    var errorMessage: String?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    /// Cache of resolved preview URLs so repeat plays start instantly.
    private var previewURLCache: [UUID: URL] = [:]

    private init() {}

    func isPlaying(_ trackID: UUID) -> Bool {
        activeTrackID == trackID
    }

    /// Starts, or stops, a clip for the given track.
    func toggle(_ track: PlaylistTrack) async {
        if activeTrackID == track.id {
            stop()
            return
        }
        stop()
        errorMessage = nil
        activeTrackID = track.id
        isLoading = true
        defer { isLoading = false }

        do {
            guard let url = try await previewURL(for: track) else {
                errorMessage = "No clip available for \"\(track.title)\""
                activeTrackID = nil
                return
            }
            // Bail out if the user tapped another track while we were searching.
            guard activeTrackID == track.id else { return }

            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)

            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            self.player = player
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
            player.play()
        } catch {
            errorMessage = "Couldn't play a clip right now."
            activeTrackID = nil
        }
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        activeTrackID = nil
    }

    // MARK: - Preview lookup

    private struct ITunesSearchResponse: Codable {
        let results: [ITunesTrack]
    }

    private struct ITunesTrack: Codable {
        let previewUrl: String?
    }

    private func previewURL(for track: PlaylistTrack) async throws -> URL? {
        if let cached = previewURLCache[track.id] { return cached }

        let term = track.artist.isEmpty ? track.title : "\(track.title) \(track.artist)"
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "3"),
        ]
        guard let url = components?.url else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        guard
            let preview = response.results.compactMap({ $0.previewUrl }).first,
            let previewURL = URL(string: preview)
        else { return nil }

        previewURLCache[track.id] = previewURL
        return previewURL
    }
}
