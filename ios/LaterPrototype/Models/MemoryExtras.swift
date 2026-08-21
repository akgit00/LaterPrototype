import Foundation
import SwiftUI

// MARK: - Story

/// One person's written version of what happened, shown in the Story section.
/// Everyone on the memory can add their own.
nonisolated struct StoryEntry: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var authorID: String
    var authorName: String
    var text: String
    var date: Date
}

// MARK: - Voice notes

/// A short audio recording attached to the memory.
nonisolated struct VoiceNote: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var authorID: String
    var authorName: String
    var title: String
    var audioURL: String
    /// Length in seconds.
    var duration: Double
    var date: Date
}

// MARK: - Sealed notes

/// A written note locked until its unlock date — a little time capsule
/// living inside the memory.
nonisolated struct SealedNote: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var authorID: String
    var authorName: String
    var text: String
    var unlockDate: Date
    var date: Date

    var isUnlocked: Bool { Date() >= unlockDate }
}

// MARK: - Polls

nonisolated struct PollOption: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// One person's pick on a poll. Rebuilt from the shared rows on every sync;
/// the newest vote per person wins.
nonisolated struct PollVote: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var voterID: String
    var voterName: String
    var optionID: UUID
}

nonisolated struct MemoryPoll: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var authorID: String
    var authorName: String
    var question: String
    var options: [PollOption]
    var votes: [PollVote]
    var date: Date

    func voteCount(for optionID: UUID) -> Int {
        votes.count { $0.optionID == optionID }
    }
}

// MARK: - Prompts

/// One person's answer to a prompt. One answer per person; editing replaces it.
nonisolated struct PromptAnswer: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var authorID: String
    var authorName: String
    var text: String
    var date: Date
}

/// A question card ("Best moment?") that everyone on the memory can answer.
nonisolated struct MemoryPrompt: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var authorID: String
    var authorName: String
    var question: String
    var answers: [PromptAnswer]
    var date: Date
}

/// Ready-made prompt ideas offered when creating one.
nonisolated enum PromptSuggestions {
    static let all: [String] = [
        "Best moment?",
        "Funniest thing that happened?",
        "One thing you'd relive?",
        "What surprised you most?",
        "Rate this day out of 10",
        "What do you want to remember in 10 years?",
    ]
}

// MARK: - Keepsakes

nonisolated enum KeepsakeKind: String, CaseIterable, Sendable, Codable {
    case ticket
    case receipt
    case letter
    case postcard
    case other

    var emoji: String {
        switch self {
        case .ticket: "🎟️"
        case .receipt: "🧾"
        case .letter: "💌"
        case .postcard: "📮"
        case .other: "✨"
        }
    }

    var label: String {
        switch self {
        case .ticket: "Ticket"
        case .receipt: "Receipt"
        case .letter: "Letter"
        case .postcard: "Postcard"
        case .other: "Keepsake"
        }
    }
}

/// A non-photo memento — a ticket stub, a receipt, a note someone passed you.
nonisolated struct Keepsake: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var authorID: String
    var authorName: String
    /// Raw `KeepsakeKind` value, kept as a string so unknown future kinds
    /// still decode.
    var kind: String
    var title: String
    var note: String
    var imageURL: String?
    var date: Date

    var kindValue: KeepsakeKind { KeepsakeKind(rawValue: kind) ?? .other }
}

// MARK: - Collections

/// A named sub-album grouping some of the memory's photos.
nonisolated struct MemoryCollection: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    var photoURLs: [String]
    var date: Date

    init(id: UUID = UUID(), name: String, emoji: String, photoURLs: [String] = [], date: Date = Date()) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.photoURLs = photoURLs
        self.date = date
    }
}

// MARK: - Weather & mood

/// A snapshot of that day's weather plus how it felt, shown as a chip in the
/// memory header ("72° Sunny · 😄").
nonisolated struct WeatherSnapshot: Sendable, Codable, Equatable {
    var temperatureCelsius: Double?
    /// WMO weather interpretation code from Open-Meteo.
    var weatherCode: Int?
    var mood: String?

    var hasContent: Bool {
        temperatureCelsius != nil || weatherCode != nil || mood != nil
    }

    /// "72°" in the user's locale unit.
    var temperatureText: String? {
        guard let temperatureCelsius else { return nil }
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .temperatureWithoutUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: temperatureCelsius, unit: UnitTemperature.celsius))
    }

    var conditionLabel: String? {
        weatherCode.map { WeatherSnapshot.label(forCode: $0) }
    }

    var symbolName: String {
        WeatherSnapshot.symbol(forCode: weatherCode)
    }

    /// "72° Sunny · 😄" — whichever parts exist.
    var chipText: String {
        var parts: [String] = []
        let weatherPart = [temperatureText, conditionLabel].compactMap { $0 }.joined(separator: " ")
        if !weatherPart.isEmpty { parts.append(weatherPart) }
        if let mood, !mood.isEmpty { parts.append(mood) }
        return parts.joined(separator: " · ")
    }

    static func label(forCode code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly sunny"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Foggy"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77: "Snow"
        case 80...82: "Showers"
        case 85, 86: "Snow showers"
        case 95...99: "Thunderstorms"
        default: "Weather"
        }
    }

    static func symbol(forCode code: Int?) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case .some(51...57): "cloud.drizzle.fill"
        case .some(61...67): "cloud.rain.fill"
        case .some(71...77), 85, 86: "cloud.snow.fill"
        case .some(80...82): "cloud.heavyrain.fill"
        case .some(95...99): "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    /// Emoji choices for how the day felt.
    static let moodOptions: [String] = ["😄", "🥰", "🤩", "😌", "🥳", "😭", "😅", "🫠"]
}

// MARK: - Pin style

/// Customizes how this memory's pin looks on the Explore globe.
nonisolated struct MemoryPinStyle: Sendable, Codable, Equatable {
    var emoji: String?
    var colorName: String

    static let defaultColorName = "orange"

    static let colorNames: [String] = [
        "orange", "red", "pink", "purple", "indigo", "blue", "teal", "green", "yellow",
    ]

    static let emojiOptions: [String] = [
        "📍", "❤️", "⭐️", "🎉", "✈️", "🏔️", "🌊", "🎂", "🎶", "🐾", "🍕", "🔥",
    ]

    static func color(named name: String?) -> Color {
        switch name {
        case "red": .red
        case "pink": .pink
        case "purple": .purple
        case "indigo": .indigo
        case "blue": .blue
        case "teal": .teal
        case "green": .green
        case "yellow": .yellow
        default: .orange
        }
    }
}

// MARK: - Shared extras payloads

/// What each `memory_extras` row's payload column carries, per kind. The row
/// itself supplies id, author, and creation date.
nonisolated struct StoryPayload: Sendable, Codable { var text: String }
nonisolated struct VoicePayload: Sendable, Codable { var title: String; var audioURL: String; var duration: Double }
nonisolated struct SealedPayload: Sendable, Codable { var text: String; var unlockDate: Date }
nonisolated struct PollPayload: Sendable, Codable { var question: String; var options: [PollOption] }
nonisolated struct VotePayload: Sendable, Codable { var pollID: UUID; var optionID: UUID }
nonisolated struct PromptPayload: Sendable, Codable { var question: String }
nonisolated struct AnswerPayload: Sendable, Codable { var promptID: UUID; var text: String }
nonisolated struct KeepsakePayload: Sendable, Codable { var kind: String; var title: String; var note: String; var imageURL: String? }

/// Encodes/decodes extras payloads as compact JSON strings with stable dates.
nonisolated enum ExtraPayloadCoder {
    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
