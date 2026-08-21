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

nonisolated struct ChatMessage: Identifiable, Sendable, Codable, Equatable {
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

nonisolated struct MusicAttachment: Sendable, Codable, Equatable {
    let songTitle: String
    let artist: String
    let albumArtURL: String?
}

nonisolated struct PlaylistTrack: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    let title: String
    let artist: String
    let albumArtURL: String?
    let duration: String
    /// Direct URL of this song's short audio clip (e.g. Spotify's 30s preview)
    /// so playback always matches the listed song. When nil, the player falls
    /// back to an iTunes lookup by title + artist.
    let previewURL: String?
    /// External link (e.g. Spotify track URL) used to open the song.
    let externalURL: String?

    init(id: UUID = UUID(), title: String, artist: String, albumArtURL: String? = nil, duration: String = "", previewURL: String? = nil, externalURL: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.duration = duration
        self.previewURL = previewURL
        self.externalURL = externalURL
    }
}

nonisolated struct PlaylistAttachment: Sendable, Codable, Equatable {
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

nonisolated struct VideoAttachment: Identifiable, Sendable, Codable, Equatable {
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

nonisolated struct Comment: Identifiable, Sendable, Codable, Equatable {
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
    /// Public profile picture URL, when the person has set one.
    let avatarURL: String?

    init(id: UUID = UUID(), username: String, displayName: String = "", avatarColor: ConnectionColor = .blue, avatarURL: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName.isEmpty ? username : displayName
        self.avatarColor = avatarColor
        self.avatarURL = avatarURL
    }

    nonisolated static func == (lhs: Connection, rhs: Connection) -> Bool {
        lhs.id == rhs.id
            && lhs.username == rhs.username
            && lhs.displayName == rhs.displayName
            && lhs.avatarURL == rhs.avatarURL
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated enum ConnectionColor: String, CaseIterable, Sendable, Codable {
    case blue, purple, pink, orange, green, teal
}

/// A smaller memory pinned INSIDE another memory — a place you went or a
/// thing you did during the bigger moment (e.g. the fishing spot on a cabin
/// trip). It lives in the parent memory's payload, so it syncs to everyone
/// the memory is shared with. All media stays in the parent memory's pool;
/// a sub-memory just references the photos (by URL) and videos (by id)
/// that belong to its spot.
nonisolated struct SubMemory: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var title: String
    var date: Date
    /// When set, the pinned memory spans from `date` through this day (a
    /// weekend ride, a two-day hike). Nil means a single-day moment.
    var endDate: Date?
    var coordinate: CLLocationCoordinate2D
    var photoURLs: [String]
    var videoIDs: [UUID]

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        endDate: Date? = nil,
        coordinate: CLLocationCoordinate2D,
        photoURLs: [String] = [],
        videoIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.endDate = endDate
        self.coordinate = coordinate
        self.photoURLs = photoURLs
        self.videoIDs = videoIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, date, endDate, latitude, longitude, photoURLs, videoIDs
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(Date.self, forKey: .date)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        photoURLs = try container.decodeIfPresent([String].self, forKey: .photoURLs) ?? []
        videoIDs = try container.decodeIfPresent([UUID].self, forKey: .videoIDs) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(endDate, forKey: .endDate)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(photoURLs, forKey: .photoURLs)
        try container.encode(videoIDs, forKey: .videoIDs)
    }

    nonisolated static func == (lhs: SubMemory, rhs: SubMemory) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.date == rhs.date
            && lhs.endDate == rhs.endDate
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.photoURLs == rhs.photoURLs
            && lhs.videoIDs == rhs.videoIDs
    }
}

nonisolated extension SubMemory {
    /// Number of calendar days this pinned memory covers (1 = a single day).
    var durationDayCount: Int {
        guard let endDate else { return 1 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: endDate)
        let days = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return max(days, 1)
    }

    /// "Jun 5" for a single day, "Jun 5 – 7" or "Jun 28 – Jul 2" for a span.
    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        guard let endDate, durationDayCount > 1 else {
            return formatter.string(from: date)
        }
        if Calendar.current.isDate(date, equalTo: endDate, toGranularity: .month) {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "d"
            return "\(formatter.string(from: date)) – \(dayFormatter.string(from: endDate))"
        }
        return "\(formatter.string(from: date)) – \(formatter.string(from: endDate))"
    }

    /// "3 days" badge text, or nil for single-day pins.
    var durationBadgeText: String? {
        let days = durationDayCount
        return days > 1 ? "\(days) days" : nil
    }
}

nonisolated struct Memory: Identifiable, Sendable, Codable, Equatable {
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
    /// Smaller memories pinned inside this one, drawn as a red web on the map.
    var subMemories: [SubMemory]
    /// When true, the owner allows everyone the memory is shared with to add
    /// more people to it.
    var allowsGuestInvites: Bool
    /// When true, the owner allows everyone the memory is shared with to save
    /// its photos and videos to their own Photos library.
    var allowsMediaSaving: Bool
    /// Raw `MapThemeOption` value chosen just for this memory's map. Nil (or
    /// an unrecognized value) means the memory follows the app-wide theme the
    /// user picked in Settings, matching the Explore globe.
    var mapTheme: String?

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
        connections: [Connection] = [],
        subMemories: [SubMemory] = [],
        allowsGuestInvites: Bool = false,
        allowsMediaSaving: Bool = true,
        mapTheme: String? = nil
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
        self.subMemories = subMemories
        self.allowsGuestInvites = allowsGuestInvites
        self.allowsMediaSaving = allowsMediaSaving
        self.mapTheme = mapTheme
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, date, creators
        case centerLatitude, centerLongitude, spanDelta
        case pins, photoURLs, videos, chatLog, music, playlist, songs, comments, connections
        case subMemories
        case allowsGuestInvites, allowsMediaSaving
        case mapTheme
    }

    nonisolated static func == (lhs: Memory, rhs: Memory) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.date == rhs.date
            && lhs.creators == rhs.creators
            && lhs.centerCoordinate.latitude == rhs.centerCoordinate.latitude
            && lhs.centerCoordinate.longitude == rhs.centerCoordinate.longitude
            && lhs.spanDelta == rhs.spanDelta
            && lhs.pins == rhs.pins
            && lhs.photoURLs == rhs.photoURLs
            && lhs.videos == rhs.videos
            && lhs.music == rhs.music
            && lhs.playlist == rhs.playlist
            && lhs.songs == rhs.songs
            && lhs.comments == rhs.comments
            && lhs.connections == rhs.connections
            && lhs.subMemories == rhs.subMemories
            && lhs.allowsGuestInvites == rhs.allowsGuestInvites
            && lhs.allowsMediaSaving == rhs.allowsMediaSaving
            && lhs.mapTheme == rhs.mapTheme
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
        subMemories = try container.decodeIfPresent([SubMemory].self, forKey: .subMemories) ?? []
        allowsGuestInvites = try container.decodeIfPresent(Bool.self, forKey: .allowsGuestInvites) ?? false
        allowsMediaSaving = try container.decodeIfPresent(Bool.self, forKey: .allowsMediaSaving) ?? true
        mapTheme = try container.decodeIfPresent(String.self, forKey: .mapTheme)
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
        try container.encode(subMemories, forKey: .subMemories)
        try container.encode(allowsGuestInvites, forKey: .allowsGuestInvites)
        try container.encode(allowsMediaSaving, forKey: .allowsMediaSaving)
        try container.encodeIfPresent(mapTheme, forKey: .mapTheme)
    }
}
