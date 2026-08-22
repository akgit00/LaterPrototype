import Foundation
import CoreLocation

// MARK: - Life collections

/// A top-level, personal collection grouping whole memories together — an era
/// of your life ("College years"), a trip series, or anything else. Private to
/// its owner and synced through the `user_collections` table. Distinct from
/// `MemoryCollection`, which is a photo sub-album INSIDE one memory.
nonisolated struct LifeCollection: Identifiable, Sendable, Codable, Equatable {
    let id: UUID
    var name: String
    var emoji: String
    var colorName: String
    var memoryIDs: [UUID]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "✨",
        colorName: String = "purple",
        memoryIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorName = colorName
        self.memoryIDs = memoryIDs
        self.createdAt = createdAt
    }

    /// Emoji choices offered when creating or editing a collection.
    static let emojiOptions: [String] = [
        "✨", "🌅", "❤️", "🎓", "🏔️", "🌊", "🎶", "🧭", "🏙️", "👶", "🎉", "📚", "🛣️", "☀️", "❄️", "🍂",
    ]
}

// MARK: - Auto year-end wraps

/// The automatic end-of-year collection: every calendar year that holds
/// memories becomes one, built on device from the memories themselves so it
/// is always up to date and appears the moment a year completes.
nonisolated struct YearWrap: Identifiable, Sendable {
    let year: Int
    /// That year's memories, oldest first.
    let memories: [Memory]
    /// True once the calendar year has fully passed — the wrap is "delivered".
    let isComplete: Bool

    var id: Int { year }

    /// Groups memories into per-year wraps, newest year first. The current
    /// (in-progress) year is always included so its card can tease the
    /// upcoming wrap, even before it holds any memories.
    static func build(from memories: [Memory], now: Date = Date()) -> [YearWrap] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        var grouped: [Int: [Memory]] = Dictionary(grouping: memories) {
            calendar.component(.year, from: $0.date)
        }
        if grouped[currentYear] == nil {
            grouped[currentYear] = []
        }
        return grouped
            .filter { $0.key <= currentYear }
            .map { year, items in
                YearWrap(
                    year: year,
                    memories: items.sorted { $0.date < $1.date },
                    isComplete: year < currentYear
                )
            }
            .sorted { $0.year > $1.year }
    }

    /// Fraction of the year elapsed (0…1), for the in-progress card.
    static func yearProgress(now: Date = Date()) -> Double {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return 0 }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    /// Whole days remaining until the wrap unlocks on Jan 1.
    static func daysUntilUnlock(now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        guard let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0
        return max(days, 0)
    }
}

// MARK: - Unified display payload

/// What the collection detail screen renders — either a custom collection or
/// an auto year wrap, resolved to concrete memories.
nonisolated struct CollectionDisplay: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let emoji: String
    let colorName: String
    /// Member memories, in display order (chronological for year wraps,
    /// the user's own arrangement for custom collections).
    let memories: [Memory]
    /// Set for auto year wraps.
    let year: Int?
    /// True when this is the still-running current year (early peek).
    let isInProgressYear: Bool
    /// Set for custom collections, enabling edit from the detail screen.
    let customID: UUID?
    /// When true, the detail screen opens on the Wrapped story.
    let opensInWrapped: Bool

    static func from(_ collection: LifeCollection, memories: [Memory]) -> CollectionDisplay {
        // The caller's order IS the collection's order — never re-sort, so
        // drag-and-drop arrangements survive.
        CollectionDisplay(
            id: "custom-\(collection.id.uuidString)",
            title: collection.name,
            subtitle: Self.rangeText(for: memories) ?? "No memories yet",
            emoji: collection.emoji,
            colorName: collection.colorName,
            memories: memories,
            year: nil,
            isInProgressYear: false,
            customID: collection.id,
            opensInWrapped: false
        )
    }

    static func from(_ wrap: YearWrap, opensInWrapped: Bool) -> CollectionDisplay {
        CollectionDisplay(
            id: "year-\(wrap.year)-\(opensInWrapped ? "wrapped" : "web")",
            title: String(wrap.year),
            subtitle: wrap.isComplete ? "Your year, wrapped" : "Your year so far",
            emoji: "🎁",
            colorName: wrap.isComplete ? "indigo" : "teal",
            memories: wrap.memories,
            year: wrap.year,
            isInProgressYear: !wrap.isComplete,
            customID: nil,
            opensInWrapped: opensInWrapped
        )
    }

    /// "Jun 2024 – Mar 2025" from the members' date span (order-independent).
    private static func rangeText(for memories: [Memory]) -> String? {
        let dates = memories.map { $0.date }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        let start = formatter.string(from: first)
        let end = formatter.string(from: last)
        return start == end ? start : "\(start) – \(end)"
    }
}

// MARK: - Wrapped stats

/// How often one person shows up across a collection's memories.
nonisolated struct CompanionStat: Identifiable, Sendable, Equatable {
    let connection: Connection
    let count: Int
    var id: UUID { connection.id }
}

/// How often one song shows up across a collection's memories.
nonisolated struct SongStat: Identifiable, Sendable, Equatable {
    let title: String
    let artist: String
    let count: Int
    var id: String { "\(title)|\(artist)" }
}

/// Everything the Wrapped story needs, computed once from a collection's
/// memories (plus the full memory list, to know which places were brand new).
nonisolated struct WrappedStats: Sendable {
    let memoryCount: Int
    let photoCount: Int
    let videoCount: Int
    let voiceCount: Int
    /// Distinct ~25 km map cells visited within the collection.
    let placeCount: Int
    /// Cells whose first-ever visit (across ALL memories) happened here.
    let newPlaceCount: Int
    /// Great-circle distance hopping memory to memory in date order.
    let totalDistanceKm: Double
    /// The single longest hop between consecutive memories.
    let farthestHopKm: Double
    /// Memory count per calendar month, January first.
    let monthCounts: [Int]
    /// 0-based index into `monthCounts` of the busiest month, if any.
    let busiestMonthIndex: Int?
    let topCompanions: [CompanionStat]
    let topSongs: [SongStat]
    let topMood: String?
    let topMoodCount: Int
    /// Visits to the single most-pinned cell — the "home base".
    let homeBaseVisits: Int
    /// Distinct calendar days holding at least one memory.
    let activeDayCount: Int
    let firstDate: Date?
    let lastDate: Date?
    let personaEmoji: String
    let personaTitle: String
    let personaLine: String

    /// Rounds a coordinate onto a ~25 km grid so nearby pins count as one place.
    private static func cellKey(_ coordinate: CLLocationCoordinate2D) -> String {
        let lat = Int((coordinate.latitude / 0.25).rounded())
        let lon = Int((coordinate.longitude / 0.25).rounded())
        return "\(lat):\(lon)"
    }

    /// Distinct ~25 km places across the given memories (for card subtitles).
    static func placeCount(of memories: [Memory]) -> Int {
        Set(memories.map { cellKey($0.centerCoordinate) }).count
    }

    /// Great-circle distance between two coordinates in kilometers.
    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let to = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return from.distance(from: to) / 1000
    }

    static func compute(memories: [Memory], allMemories: [Memory]) -> WrappedStats {
        let calendar = Calendar.current
        let sorted = memories.sorted { $0.date < $1.date }

        let photoCount = sorted.reduce(0) { $0 + $1.photoURLs.count }
        let videoCount = sorted.reduce(0) { $0 + $1.videos.count }
        let voiceCount = sorted.reduce(0) { $0 + $1.voiceNotes.count }

        // Places: distinct grid cells, and which of them were first-ever visits.
        let cells = Set(sorted.map { cellKey($0.centerCoordinate) })
        var firstVisitByCell: [String: Date] = [:]
        for memory in allMemories {
            let key = cellKey(memory.centerCoordinate)
            if let existing = firstVisitByCell[key] {
                if memory.date < existing { firstVisitByCell[key] = memory.date }
            } else {
                firstVisitByCell[key] = memory.date
            }
        }
        let startDate = sorted.first?.date
        let newPlaceCount = cells.count { cell in
            guard let start = startDate, let firstVisit = firstVisitByCell[cell] else { return true }
            return firstVisit >= start
        }

        // Distance hopping memory to memory, in date order.
        var totalKm: Double = 0
        var farthestHopKm: Double = 0
        if sorted.count >= 2 {
            for index in 1..<sorted.count {
                let hop = distanceKm(sorted[index - 1].centerCoordinate, sorted[index].centerCoordinate)
                totalKm += hop
                farthestHopKm = max(farthestHopKm, hop)
            }
        }

        // Months.
        var monthCounts = [Int](repeating: 0, count: 12)
        for memory in sorted {
            let month = calendar.component(.month, from: memory.date)
            if (1...12).contains(month) { monthCounts[month - 1] += 1 }
        }
        let busiestMonthIndex: Int? = monthCounts.contains(where: { $0 > 0 })
            ? monthCounts.enumerated().max(by: { $0.element < $1.element })?.offset
            : nil

        // People.
        var companionCounts: [UUID: (connection: Connection, count: Int)] = [:]
        for memory in sorted {
            for person in memory.connections {
                if let existing = companionCounts[person.id] {
                    companionCounts[person.id] = (existing.connection, existing.count + 1)
                } else {
                    companionCounts[person.id] = (person, 1)
                }
            }
        }
        let topCompanions = companionCounts.values
            .sorted { lhs, rhs in
                lhs.count == rhs.count
                    ? lhs.connection.displayName < rhs.connection.displayName
                    : lhs.count > rhs.count
            }
            .prefix(3)
            .map { CompanionStat(connection: $0.connection, count: $0.count) }

        // Soundtrack: single songs, playlist tracks, and the pinned song.
        var songCounts: [String: (title: String, artist: String, count: Int)] = [:]
        func countSong(title: String, artist: String) {
            let key = "\(title.lowercased())|\(artist.lowercased())"
            if let existing = songCounts[key] {
                songCounts[key] = (existing.title, existing.artist, existing.count + 1)
            } else {
                songCounts[key] = (title, artist, 1)
            }
        }
        var totalSongMentions = 0
        for memory in sorted {
            for song in memory.songs {
                countSong(title: song.title, artist: song.artist)
                totalSongMentions += 1
            }
            for track in memory.playlist?.tracks ?? [] {
                countSong(title: track.title, artist: track.artist)
                totalSongMentions += 1
            }
            if let music = memory.music {
                countSong(title: music.songTitle, artist: music.artist)
                totalSongMentions += 1
            }
        }
        let topSongs = songCounts.values
            .sorted { lhs, rhs in
                lhs.count == rhs.count ? lhs.title < rhs.title : lhs.count > rhs.count
            }
            .prefix(3)
            .map { SongStat(title: $0.title, artist: $0.artist, count: $0.count) }

        // Mood.
        var moodCounts: [String: Int] = [:]
        for memory in sorted {
            if let mood = memory.weather?.mood, !mood.isEmpty {
                moodCounts[mood, default: 0] += 1
            }
        }
        let topMoodPair = moodCounts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }

        // Home base + active days.
        var cellVisits: [String: Int] = [:]
        for memory in sorted {
            cellVisits[cellKey(memory.centerCoordinate), default: 0] += 1
        }
        let homeBaseVisits = cellVisits.values.max() ?? 0
        let activeDayCount = Set(sorted.map { calendar.startOfDay(for: $0.date) }).count

        // Persona.
        let monthsCovered = monthCounts.count { $0 > 0 }
        let persona = Self.persona(
            memoryCount: sorted.count,
            placeCount: cells.count,
            newPlaceCount: newPlaceCount,
            totalKm: totalKm,
            photoCount: photoCount,
            songMentions: totalSongMentions,
            monthsCovered: monthsCovered,
            topCompanion: topCompanions.first
        )

        return WrappedStats(
            memoryCount: sorted.count,
            photoCount: photoCount,
            videoCount: videoCount,
            voiceCount: voiceCount,
            placeCount: cells.count,
            newPlaceCount: newPlaceCount,
            totalDistanceKm: totalKm,
            farthestHopKm: farthestHopKm,
            monthCounts: monthCounts,
            busiestMonthIndex: busiestMonthIndex,
            topCompanions: Array(topCompanions),
            topSongs: Array(topSongs),
            topMood: topMoodPair?.key,
            topMoodCount: topMoodPair?.value ?? 0,
            homeBaseVisits: homeBaseVisits,
            activeDayCount: activeDayCount,
            firstDate: sorted.first?.date,
            lastDate: sorted.last?.date,
            personaEmoji: persona.emoji,
            personaTitle: persona.title,
            personaLine: persona.line
        )
    }

    /// A fun archetype summarizing how the collection was lived.
    private static func persona(
        memoryCount: Int,
        placeCount: Int,
        newPlaceCount: Int,
        totalKm: Double,
        photoCount: Int,
        songMentions: Int,
        monthsCovered: Int,
        topCompanion: CompanionStat?
    ) -> (emoji: String, title: String, line: String) {
        if totalKm > 8000 || newPlaceCount >= 12 {
            return ("✈️", "The Globetrotter", "The world kept calling — you kept answering.")
        }
        if let companion = topCompanion, memoryCount >= 3,
           companion.count >= max(2, Int((Double(memoryCount) * 0.6).rounded())) {
            return ("🤝", "The Ride or Die", "Almost every moment had \(companion.connection.displayName) in it.")
        }
        if placeCount <= 2 && memoryCount >= 4 {
            return ("☕️", "The Regular", "You found your places and made them legendary.")
        }
        if memoryCount > 0 && photoCount >= memoryCount * 8 {
            return ("📸", "The Archivist", "If it happened, you have the proof.")
        }
        if songMentions >= 5 {
            return ("🎧", "The Soundtracker", "Every moment got its own score.")
        }
        if monthsCovered >= 10 {
            return ("🗓️", "The Ever-Present", "Not a single season slipped by unmarked.")
        }
        return ("✨", "The Memory Keeper", "Quality over quantity — every pin earned its place.")
    }

    /// A playful size comparison for the distance slide.
    var distanceComparison: String? {
        guard totalDistanceKm >= 1 else { return nil }
        if totalDistanceKm >= 40_075 {
            let laps = totalDistanceKm / 40_075
            return String(format: "That's %.1f× around the entire planet.", laps)
        }
        if totalDistanceKm >= 3_000 {
            let pct = Int((totalDistanceKm / 40_075 * 100).rounded())
            return "That's \(pct)% of the way around the Earth."
        }
        if totalDistanceKm >= 300 {
            let marathons = Int((totalDistanceKm / 42.2).rounded())
            return "That's about \(marathons) marathons, back to back."
        }
        let laps = Int((totalDistanceKm / 0.4).rounded())
        return "That's roughly \(laps) laps of a running track."
    }
}
