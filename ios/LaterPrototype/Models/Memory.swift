import Foundation
import CoreLocation

nonisolated struct MemoryPin: Identifiable, Sendable, Hashable, Codable {
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

    private enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, title, date, imageURL, intensity
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(Date.self, forKey: .date)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        intensity = try container.decode(Double.self, forKey: .intensity)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(title, forKey: .title)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encode(intensity, forKey: .intensity)
    }

    nonisolated static func == (lhs: MemoryPin, rhs: MemoryPin) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated struct ChatMessage: Identifiable, Sendable, Codable {
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

nonisolated struct MusicAttachment: Sendable, Codable {
    let songTitle: String
    let artist: String
    let albumArtURL: String?
}

nonisolated struct PlaylistTrack: Identifiable, Sendable, Codable {
    let id: UUID
    let title: String
    let artist: String
    let albumArtURL: String?
    let duration: String
    /// External link (e.g. Spotify track URL) used to open the song.
    let externalURL: String?

    init(id: UUID = UUID(), title: String, artist: String, albumArtURL: String? = nil, duration: String = "", externalURL: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.duration = duration
        self.externalURL = externalURL
    }
}

nonisolated struct PlaylistAttachment: Sendable, Codable {
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

nonisolated enum PlaylistSource: String, Sendable, Codable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
}

nonisolated struct VideoAttachment: Identifiable, Sendable, Codable {
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

nonisolated struct Comment: Identifiable, Sendable, Codable {
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

nonisolated struct Connection: Identifiable, Sendable, Hashable, Codable {
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

nonisolated enum ConnectionColor: String, CaseIterable, Sendable, Codable {
    case blue, purple, pink, orange, green, teal
}

nonisolated struct Memory: Identifiable, Sendable, Codable {
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
    var songs: [PlaylistTrack]
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
        songs: [PlaylistTrack] = [],
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
        self.songs = songs
        self.comments = comments
        self.connections = connections
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, date, creators
        case centerLatitude, centerLongitude, spanDelta
        case pins, photoURLs, videos, chatLog, music, playlist, songs, comments, connections
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        date = try container.decode(Date.self, forKey: .date)
        creators = try container.decode([String].self, forKey: .creators)
        let latitude = try container.decode(Double.self, forKey: .centerLatitude)
        let longitude = try container.decode(Double.self, forKey: .centerLongitude)
        centerCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        spanDelta = try container.decode(Double.self, forKey: .spanDelta)
        pins = try container.decode([MemoryPin].self, forKey: .pins)
        photoURLs = try container.decode([String].self, forKey: .photoURLs)
        videos = try container.decode([VideoAttachment].self, forKey: .videos)
        chatLog = try container.decode([ChatMessage].self, forKey: .chatLog)
        music = try container.decodeIfPresent(MusicAttachment.self, forKey: .music)
        playlist = try container.decodeIfPresent(PlaylistAttachment.self, forKey: .playlist)
        songs = try container.decodeIfPresent([PlaylistTrack].self, forKey: .songs) ?? []
        comments = try container.decode([Comment].self, forKey: .comments)
        connections = try container.decode([Connection].self, forKey: .connections)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(date, forKey: .date)
        try container.encode(creators, forKey: .creators)
        try container.encode(centerCoordinate.latitude, forKey: .centerLatitude)
        try container.encode(centerCoordinate.longitude, forKey: .centerLongitude)
        try container.encode(spanDelta, forKey: .spanDelta)
        try container.encode(pins, forKey: .pins)
        try container.encode(photoURLs, forKey: .photoURLs)
        try container.encode(videos, forKey: .videos)
        try container.encode(chatLog, forKey: .chatLog)
        try container.encodeIfPresent(music, forKey: .music)
        try container.encodeIfPresent(playlist, forKey: .playlist)
        try container.encode(songs, forKey: .songs)
        try container.encode(comments, forKey: .comments)
        try container.encode(connections, forKey: .connections)
    }
}
