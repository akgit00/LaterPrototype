import Foundation
import CoreLocation
import SwiftUI
import MapKit

@Observable
final class LaterViewModel {
    var memories: [Memory] = []
    var selectedMemory: Memory?
    var globalPins: [MemoryPin] = []
    var timelineProgress: Double = 0.0
    var selectedTab: Tab = .explore

    var allConnections: [Connection] = []

    enum Tab: String {
        case explore
        case timeCapsules
        case profile
    }

    init() {
        if let stored = MemoryStore.load() {
            memories = stored
            rebuildGlobalPins()
        }
    }

    /// Persists the current memories to disk. Call after any mutation.
    private func persist() {
        MemoryStore.save(memories)
    }

    func addMemory(_ memory: Memory) {
        memories.insert(memory, at: 0)
        rebuildGlobalPins()
        persist()
    }

    func updateMemory(_ memory: Memory) {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[index] = memory
        rebuildGlobalPins()
        persist()
    }

    func deleteMemory(_ id: UUID) {
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return }
        let memory = memories[index]
        for url in memory.photoURLs {
            MediaStore.deleteFile(at: url)
        }
        for video in memory.videos {
            if let videoURL = video.videoURL {
                MediaStore.deleteFile(at: videoURL)
            }
            MediaStore.deleteFile(at: video.thumbnailURL)
        }
        memories.remove(at: index)
        if selectedMemory?.id == id {
            selectedMemory = nil
        }
        rebuildGlobalPins()
        persist()
    }

    func removePhotoURL(from memoryID: UUID, url: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].photoURLs.removeAll { $0 == url }
        memories[index].pins.removeAll { $0.imageURL == url }
        MediaStore.deleteFile(at: url)
        rebuildGlobalPins()
        persist()
    }

    func removeVideo(from memoryID: UUID, video: VideoAttachment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].videos.removeAll { $0.id == video.id }
        if let videoURL = video.videoURL {
            MediaStore.deleteFile(at: videoURL)
        }
        MediaStore.deleteFile(at: video.thumbnailURL)
        persist()
    }

    func addComment(to memoryID: UUID, comment: Comment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].comments.append(comment)
        persist()
    }

    func addPhotoURL(to memoryID: UUID, url: String) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].photoURLs.append(url)
        persist()
    }

    func addVideo(to memoryID: UUID, video: VideoAttachment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].videos.append(video)
        persist()
    }

    func setPlaylist(for memoryID: UUID, playlist: PlaylistAttachment) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].playlist = playlist
        persist()
    }

    func addConnection(to memoryID: UUID, connection: Connection) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        if !memories[index].connections.contains(where: { $0.id == connection.id }) {
            memories[index].connections.append(connection)
            if !memories[index].creators.contains(connection.username) {
                memories[index].creators.append(connection.username)
            }
            persist()
        }
    }

    func removeConnection(from memoryID: UUID, connection: Connection) {
        guard let index = memories.firstIndex(where: { $0.id == memoryID }) else { return }
        memories[index].connections.removeAll { $0.id == connection.id }
        memories[index].creators.removeAll { $0 == connection.username }
        persist()
    }

    func memory(for pin: MemoryPin) -> Memory? {
        memories.first { memory in
            memory.pins.contains { $0.id == pin.id }
        }
    }

    func memoryByID(_ id: UUID) -> Memory? {
        memories.first { $0.id == id }
    }

    private func rebuildGlobalPins() {
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
}
