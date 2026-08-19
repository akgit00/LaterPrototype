import Foundation
import Photos
import UIKit

/// UI state for a "save to Photos" action.
enum MediaSaveState: Equatable {
    case idle
    case saving
    case saved
}

/// Saves memory photos and videos to the user's Photos library ("camera
/// roll"), downloading remote media first when needed. Uses add-only Photos
/// access so the app never asks to read the user's library.
nonisolated enum MediaSaver {
    enum SaveError: LocalizedError {
        case permissionDenied
        case invalidURL
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Later isn't allowed to add to your Photos library. Enable it in Settings > Later > Photos."
            case .invalidURL:
                return "This item isn't available to save yet. It may still be uploading."
            case .downloadFailed:
                return "Couldn't load this item. Check your connection and try again."
            }
        }
    }

    /// Saves the photo at the given URL string (local file or https) to the
    /// user's Photos library.
    static func savePhoto(urlString: String?) async throws {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            throw SaveError.invalidURL
        }
        try await ensureAddPermission()

        let data: Data
        if url.isFileURL {
            guard let fileData = try? Data(contentsOf: url) else { throw SaveError.downloadFailed }
            data = fileData
        } else {
            data = try await download(url)
        }
        guard UIImage(data: data) != nil else { throw SaveError.downloadFailed }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    /// Saves the video at the given URL string (local file or https) to the
    /// user's Photos library.
    static func saveVideo(urlString: String?) async throws {
        guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else {
            throw SaveError.invalidURL
        }
        try await ensureAddPermission()

        let fileURL: URL
        var isTemporary = false
        if url.isFileURL {
            guard FileManager.default.fileExists(atPath: url.path) else { throw SaveError.downloadFailed }
            fileURL = url
        } else {
            fileURL = try await downloadToTemporaryFile(url)
            isTemporary = true
        }
        defer {
            if isTemporary { try? FileManager.default.removeItem(at: fileURL) }
        }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: fileURL, options: nil)
        }
    }

    private static func ensureAddPermission() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw SaveError.permissionDenied
        }
    }

    private static func download(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw SaveError.downloadFailed
            }
            return data
        } catch {
            throw SaveError.downloadFailed
        }
    }

    /// Downloads a remote video to a temporary file with a proper video
    /// extension — Photos imports videos from file URLs only.
    private static func downloadToTemporaryFile(_ url: URL) async throws -> URL {
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: tempURL)
                throw SaveError.downloadFailed
            }
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.moveItem(at: tempURL, to: destination)
            return destination
        } catch let error as SaveError {
            throw error
        } catch {
            throw SaveError.downloadFailed
        }
    }
}
