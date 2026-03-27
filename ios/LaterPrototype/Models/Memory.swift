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
    let chatLog: [ChatMessage]
    let music: MusicAttachment?

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
        chatLog: [ChatMessage] = [],
        music: MusicAttachment? = nil
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
        self.chatLog = chatLog
        self.music = music
    }
}
