import SwiftUI
import CoreLocation
import MapboxMaps

/// Renders and caches a static preview image for every map theme so the
/// theme picker can show real map tiles instead of just style names.
/// Previews are rendered once with Mapbox's Snapshotter, kept in memory for
/// the session, and stored in the caches directory for later launches.
@Observable
final class MapThemePreviewStore {
    static let shared = MapThemePreviewStore()

    private(set) var images: [MapThemeOption: UIImage] = [:]
    private(set) var failedThemes: Set<MapThemeOption> = []

    private var isGenerating = false
    private var cancelables = Set<AnyCancelable>()
    private var activeSnapshotter: Snapshotter?

    /// Downtown New York — dense buildings show off 3D themes well.
    private static let previewCenter = CLLocationCoordinate2D(latitude: 40.7061, longitude: -74.0086)
    private static let snapshotSize = CGSize(width: 340, height: 240)

    func image(for option: MapThemeOption) -> UIImage? {
        images[option]
    }

    func hasFailed(_ option: MapThemeOption) -> Bool {
        failedThemes.contains(option)
    }

    /// Fills in any missing previews, one at a time to keep memory low.
    func generateAll() async {
        guard MapboxSetup.hasToken, !isGenerating else { return }
        MapboxSetup.configureIfNeeded()
        isGenerating = true
        defer { isGenerating = false }

        for option in MapThemeOption.allCases where images[option] == nil {
            if let cached = loadCachedImage(for: option) {
                images[option] = cached
                continue
            }
            if let rendered = await renderSnapshot(for: option) {
                images[option] = rendered
                failedThemes.remove(option)
                cacheImage(rendered, for: option)
            } else {
                failedThemes.insert(option)
            }
        }

        cancelables.removeAll()
        activeSnapshotter = nil
    }

    private func renderSnapshot(for option: MapThemeOption) async -> UIImage? {
        let options = MapSnapshotOptions(size: Self.snapshotSize, pixelRatio: 2)
        let snapshotter = Snapshotter(options: options)
        activeSnapshotter = snapshotter
        snapshotter.load(mapStyle: option.mapStyle)
        snapshotter.setCamera(to: Self.camera(for: option))

        let resumeGuard = ResumeGuard()
        return await withCheckedContinuation { continuation in
            let finish: (UIImage?) -> Void = { image in
                guard !resumeGuard.hasResumed else { return }
                resumeGuard.hasResumed = true
                continuation.resume(returning: image)
            }

            snapshotter.onStyleLoaded.observeNext { _ in
                snapshotter.start(overlayHandler: nil) { result in
                    switch result {
                    case .success(let image):
                        finish(image)
                    case .failure:
                        finish(nil)
                    }
                }
            }.store(in: &cancelables)

            // Safety net: never let one broken style stall the whole grid.
            Task {
                try? await Task.sleep(for: .seconds(25))
                finish(nil)
            }
        }
    }

    /// Tilted camera for 3D-capable themes, flat top-down for classic ones.
    private static func camera(for option: MapThemeOption) -> CameraOptions {
        switch option {
        case .streets, .outdoors, .light, .dark:
            CameraOptions(center: previewCenter, zoom: 13.8, bearing: 0, pitch: 0)
        default:
            CameraOptions(center: previewCenter, zoom: 15.4, bearing: -17.6, pitch: 55)
        }
    }

    // MARK: - Disk cache

    private func cacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = base.appendingPathComponent("MapThemePreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func cacheURL(for option: MapThemeOption) -> URL? {
        cacheDirectory()?.appendingPathComponent("preview_v1_\(option.rawValue).jpg")
    }

    private func loadCachedImage(for option: MapThemeOption) -> UIImage? {
        guard let url = cacheURL(for: option) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func cacheImage(_ image: UIImage, for option: MapThemeOption) {
        guard let url = cacheURL(for: option), let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: url)
    }
}

/// Guarantees a checked continuation is resumed exactly once even when the
/// snapshot completion and the timeout race each other.
private final class ResumeGuard {
    var hasResumed = false
}
