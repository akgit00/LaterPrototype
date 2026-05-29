import Foundation
import UIKit
import AVFoundation
import CoreMedia

/// Persists user-picked photos and videos into the app's Documents directory
/// and derives video thumbnails / durations. All methods are `nonisolated`
/// so heavy file and media work stays off the main actor.
nonisolated enum MediaStore {
    /// Directory where imported media files are stored.
    static var mediaDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Writes image data to disk and returns its file URL string, or nil on failure.
    static func saveImage(_ data: Data) -> String? {
        let url = mediaDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url.absoluteString
        } catch {
            return nil
        }
    }

    /// Writes video data to disk and returns its file URL string, or nil on failure.
    static func saveVideo(_ data: Data) -> String? {
        let url = mediaDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        do {
            try data.write(to: url, options: .atomic)
            return url.absoluteString
        } catch {
            return nil
        }
    }

    /// Deletes a media file from disk if it is a local file URL. No-op for remote URLs.
    static func deleteFile(at urlString: String) {
        guard let url = URL(string: urlString), url.isFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Generates a thumbnail image for a video and persists it, returning its file URL string.
    static func generateThumbnail(for videoURL: URL) async -> String? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let result = try await generator.image(at: time)
            let uiImage = UIImage(cgImage: result.image)
            if let data = uiImage.jpegData(compressionQuality: 0.8) {
                return saveImage(data)
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Returns a formatted `m:ss` duration string for a video.
    static func durationString(for videoURL: URL) async -> String {
        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return "" }
        let totalSeconds = Int(CMTimeGetSeconds(duration).rounded())
        guard totalSeconds > 0 else { return "" }
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
