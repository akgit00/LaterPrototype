import Foundation
import CoreLocation
import SwiftUI

@Observable
final class LaterViewModel {
    var memories: [Memory] = []
    var selectedMemory: Memory?
    var globalPins: [MemoryPin] = []
    var timelineProgress: Double = 0.0
    var selectedTab: Tab = .explore

    enum Tab: String {
        case explore
        case timeCapsules
        case profile
    }

    init() {
        loadSampleData()
    }

    private func loadSampleData() {
        let poconosPins: [MemoryPin] = [
            MemoryPin(
                coordinate: CLLocationCoordinate2D(latitude: 41.0534, longitude: -75.5155),
                title: "Cabin Arrival",
                date: dateFrom("2025-08-15 14:45"),
                imageURL: "https://images.unsplash.com/photo-1510798831971-661eb04b3739?w=400",
                intensity: 0.8
            ),
            MemoryPin(
                coordinate: CLLocationCoordinate2D(latitude: 41.0580, longitude: -75.5200),
                title: "Lake Hangout",
                date: dateFrom("2025-08-15 17:30"),
                imageURL: "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400",
                intensity: 1.0
            ),
            MemoryPin(
                coordinate: CLLocationCoordinate2D(latitude: 41.0490, longitude: -75.5100),
                title: "Bonfire Night",
                date: dateFrom("2025-08-15 21:00"),
                imageURL: "https://images.unsplash.com/photo-1475483768296-6163e08872a1?w=400",
                intensity: 0.6
            ),
            MemoryPin(
                coordinate: CLLocationCoordinate2D(latitude: 41.0600, longitude: -75.5250),
                title: "Morning Hike",
                date: dateFrom("2025-08-16 08:00"),
                imageURL: "https://images.unsplash.com/photo-1551632811-561732d1e306?w=400",
                intensity: 0.7
            )
        ]

        let poconosMemory = Memory(
            title: "Poconos Trip 2025",
            subtitle: "The weekend that changed everything",
            date: dateFrom("2025-08-15 14:00"),
            creators: ["Samantherr", "Kool-Aidd", "Trist0", "AkaWild"],
            centerCoordinate: CLLocationCoordinate2D(latitude: 41.0534, longitude: -75.5155),
            spanDelta: 0.15,
            pins: poconosPins,
            photoURLs: [
                "https://images.unsplash.com/photo-1510798831971-661eb04b3739?w=400",
                "https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400",
                "https://images.unsplash.com/photo-1475483768296-6163e08872a1?w=400",
                "https://images.unsplash.com/photo-1551632811-561732d1e306?w=400"
            ],
            chatLog: [
                ChatMessage(time: "2:45 P.M.", username: "Samantherr", message: "Just arrived 🎉"),
                ChatMessage(time: "5:17 P.M.", username: "Kool-Aidd", message: "Showed off my fifty people #GOAT"),
                ChatMessage(time: "8:48 P.M.", username: "Trist0", message: "Shots?"),
                ChatMessage(time: "10:10 P.M.", username: "AkaWild", message: "Brought the Cases couldn't let us starve without me #Junior")
            ],
            music: MusicAttachment(
                songTitle: "Summer Nights",
                artist: "SZA",
                albumArtURL: "https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=200"
            )
        )

        let nycPins: [MemoryPin] = [
            MemoryPin(
                coordinate: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
                title: "Times Square Meetup",
                date: dateFrom("2025-07-04 19:00"),
                intensity: 0.9
            ),
            MemoryPin(
                coordinate: CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857),
                title: "Empire State View",
                date: dateFrom("2025-07-04 21:00"),
                intensity: 0.7
            )
        ]

        let nycMemory = Memory(
            title: "NYC Fourth of July",
            subtitle: "Fireworks over the skyline",
            date: dateFrom("2025-07-04 19:00"),
            creators: ["Samantherr", "Jay"],
            centerCoordinate: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
            spanDelta: 0.05,
            pins: nycPins,
            photoURLs: [
                "https://images.unsplash.com/photo-1534430480872-3498386e7856?w=400",
                "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=400"
            ],
            chatLog: [
                ChatMessage(time: "7:00 P.M.", username: "Samantherr", message: "Where is everyone??"),
                ChatMessage(time: "7:15 P.M.", username: "Jay", message: "Coming up from the subway now"),
                ChatMessage(time: "9:30 P.M.", username: "Samantherr", message: "Best fireworks ever 🎆")
            ]
        )

        let tokyoPins: [MemoryPin] = [
            MemoryPin(
                coordinate: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                title: "Shibuya Crossing",
                date: dateFrom("2025-03-20 10:00"),
                intensity: 0.85
            ),
            MemoryPin(
                coordinate: CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967),
                title: "Senso-ji Temple",
                date: dateFrom("2025-03-21 14:00"),
                intensity: 0.6
            )
        ]

        let tokyoMemory = Memory(
            title: "Tokyo Spring 2025",
            subtitle: "Cherry blossoms & neon lights",
            date: dateFrom("2025-03-20 10:00"),
            creators: ["Samantherr"],
            centerCoordinate: CLLocationCoordinate2D(latitude: 35.6895, longitude: 139.6917),
            spanDelta: 0.1,
            pins: tokyoPins,
            photoURLs: [
                "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=400",
                "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=400"
            ],
            chatLog: [
                ChatMessage(time: "10:00 A.M.", username: "Samantherr", message: "Shibuya is INSANE"),
                ChatMessage(time: "2:30 P.M.", username: "Samantherr", message: "Temple was so peaceful 🙏")
            ]
        )

        memories = [poconosMemory, nycMemory, tokyoMemory]

        globalPins = memories.flatMap { memory in
            memory.pins.map { pin in
                MemoryPin(
                    id: pin.id,
                    coordinate: pin.coordinate,
                    title: memory.title,
                    date: pin.date,
                    imageURL: pin.imageURL,
                    intensity: pin.intensity
                )
            }
        }
    }

    func memory(for pin: MemoryPin) -> Memory? {
        memories.first { memory in
            memory.pins.contains { $0.id == pin.id }
        }
    }

    private func dateFrom(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string) ?? Date()
    }
}
