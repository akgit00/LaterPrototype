import Foundation
import CoreLocation

nonisolated struct MemoryPin: Identifiable, Sendable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
    let date: Date
    let imageURL: String?
    let intensity: Double

    init(id: UUID = UUID(), coordinate: CLLocationCoordinate2D, title: String, date: Date, imageURL: String? = nil, intensity: Double = 0.5) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.date = date
        self.imageURL = imageURL
        self.intensity = intensity
    }
}

nonisolated struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let time: String
    let username: String
    let message: String

    init(id: UUID = UUID(), time: String, username: String, message: String) {
        self.id = id
        self.time = time
        self.username = username
        self.message = message
    }
}

nonisolated struct MusicAttachment: Sendable {
    let songTitle: String
    let artist: String
    let albumArtURL: String?
}

nonisolated struct PlaylistTrack: Identifiable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let albumArtURL: String?
    let duration: String

    init(id: UUID = UUID(), title: String, artist: String, albumArtURL: String? = nil, duration: String = "") {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.duration = duration
    }
}

nonisolated struct PlaylistAttachment: Sendable {
    let name: String
    let source: PlaylistSource
    let coverURL: String?
    let tracks: [PlaylistTrack]
    let externalURL: String?

    init(name: String, source: PlaylistSource = .spotify, coverURL: String? = nil, tracks: [PlaylistTrack] = [], externalURL: String? = nil) {
        self.name = name
        self.source = source
        self.coverURL = coverURL
        self.tracks = tracks
        self.externalURL = externalURL
    }
}

nonisolated enum PlaylistSource: String, Sendable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
}

nonisolated struct VideoAttachment: Identifiable, Sendable {
    let id: UUID
    let thumbnailURL: String
    let title: String
    let duration: String

    init(id: UUID = UUID(), thumbnailURL: String, title: String, duration: String = "") {
        self.id = id
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.duration = duration
    }
}

nonisolated struct Memory: Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let date: Date
    let creators: [String]
    let centerCoordinate: CLLocationCoordinate2D
    let spanDelta: Double
    let pins: [MemoryPin]
    let photoURLs: [String]
    let videos: [VideoAttachment]
    let chatLog: [ChatMessage]
    let music: MusicAttachment?
    let playlist: PlaylistAttachment?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        date: Date,
        creators: [String] = [],
        centerCoordinate: CLLocationCoordinate2D,
        spanDelta: Double = 0.5,
        pins: [MemoryPin] = [],
        photoURLs: [String] = [],
        videos: [VideoAttachment] = [],
        chatLog: [ChatMessage] = [],
        music: MusicAttachment? = nil,
        playlist: PlaylistAttachment? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.date = date
        self.creators = creators
        self.centerCoordinate = centerCoordinate
        self.spanDelta = spanDelta
        self.pins = pins
        self.photoURLs = photoURLs
        self.videos = videos
        self.chatLog = chatLog
        self.music = music
        self.playlist = playlist
    }
}
