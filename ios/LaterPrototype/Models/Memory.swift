import Foundation
import CoreLocation

nonisolated struct MemoryPin: Identifiable, Sendable, Hashable {
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

    nonisolated static func == (lhs: MemoryPin, rhs: MemoryPin) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
    /// File URL string of the actual playable video, when imported from the library.
    let videoURL: String?

    init(id: UUID = UUID(), thumbnailURL: String, title: String, duration: String = "", videoURL: String? = nil) {
        self.id = id
        self.thumbnailURL = thumbnailURL
        self.title = title
        self.duration = duration
        self.videoURL = videoURL
    }
}

nonisolated struct Comment: Identifiable, Sendable {
    let id: UUID
    let username: String
    let text: String
    let date: Date

    init(id: UUID = UUID(), username: String, text: String, date: Date = Date()) {
        self.id = id
        self.username = username
        self.text = text
        self.date = date
    }
}

nonisolated struct Connection: Identifiable, Sendable, Hashable {
    let id: UUID
    let username: String
    let displayName: String
    let avatarColor: ConnectionColor

    init(id: UUID = UUID(), username: String, displayName: String = "", avatarColor: ConnectionColor = .blue) {
        self.id = id
        self.username = username
        self.displayName = displayName.isEmpty ? username : displayName
        self.avatarColor = avatarColor
    }

    nonisolated static func == (lhs: Connection, rhs: Connection) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated enum ConnectionColor: String, CaseIterable, Sendable {
    case blue, purple, pink, orange, green, teal
}

nonisolated struct Memory: Identifiable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String
    var date: Date
    var creators: [String]
    var centerCoordinate: CLLocationCoordinate2D
    var spanDelta: Double
    var pins: [MemoryPin]
    var photoURLs: [String]
    var videos: [VideoAttachment]
    var chatLog: [ChatMessage]
    var music: MusicAttachment?
    var playlist: PlaylistAttachment?
    var comments: [Comment]
    var connections: [Connection]

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String = "",
        date: Date = Date(),
        creators: [String] = [],
        centerCoordinate: CLLocationCoordinate2D,
        spanDelta: Double = 0.5,
        pins: [MemoryPin] = [],
        photoURLs: [String] = [],
        videos: [VideoAttachment] = [],
        chatLog: [ChatMessage] = [],
        music: MusicAttachment? = nil,
        playlist: PlaylistAttachment? = nil,
        comments: [Comment] = [],
        connections: [Connection] = []
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
        self.comments = comments
        self.connections = connections
    }
}
