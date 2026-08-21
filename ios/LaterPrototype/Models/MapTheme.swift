import SwiftUI
import MapboxMaps

/// One-time Mapbox SDK configuration shared by every Mapbox-backed screen.
enum MapboxSetup {
    private static var isConfigured = false

    static var hasToken: Bool { !Config.EXPO_PUBLIC_MAPBOX_TOKEN.isEmpty }

    static func configureIfNeeded() {
        guard !isConfigured, hasToken else { return }
        MapboxOptions.accessToken = Config.EXPO_PUBLIC_MAPBOX_TOKEN
        isConfigured = true
    }
}

/// Every map look the app can render — Mapbox Standard variations plus the
/// classic static styles. The user's pick is stored globally and applied to
/// the Explore globe and to every memory map without a theme of its own.
enum MapThemeOption: String, CaseIterable, Identifiable {
    case standardDay
    case standardDawn
    case standardDusk
    case standardNight
    case fadedDay
    case fadedNight
    case monochromeDay
    case monochromeNight
    case satellite3D
    case satelliteStreets
    case streets
    case outdoors
    case light
    case dark

    var id: String { rawValue }

    /// UserDefaults key for the app-wide theme choice.
    static let storageKey = "map_theme_preference"

    /// Closest match to the app's original Apple satellite look.
    static let defaultTheme: MapThemeOption = .satellite3D

    /// Resolves a stored raw value, falling back to the default look.
    static func stored(from raw: String) -> MapThemeOption {
        MapThemeOption(rawValue: raw) ?? defaultTheme
    }

    var label: String {
        switch self {
        case .standardDay: "Standard · Day"
        case .standardDawn: "Standard · Dawn"
        case .standardDusk: "Standard · Dusk"
        case .standardNight: "Standard · Night"
        case .fadedDay: "Faded"
        case .fadedNight: "Faded · Night"
        case .monochromeDay: "Monochrome"
        case .monochromeNight: "Mono · Night"
        case .satellite3D: "Satellite 3D"
        case .satelliteStreets: "Satellite Streets"
        case .streets: "Streets Classic"
        case .outdoors: "Outdoors"
        case .light: "Light Classic"
        case .dark: "Dark Classic"
        }
    }

    var detail: String {
        switch self {
        case .standardDay: "The 3D flagship style in full daylight"
        case .standardDawn: "3D buildings under a soft sunrise"
        case .standardDusk: "Golden-hour lighting with long shadows"
        case .standardNight: "Glowing windows and street lights"
        case .fadedDay: "Muted pastel palette, 3D buildings"
        case .fadedNight: "Muted palette after dark"
        case .monochromeDay: "Single-hue minimal look"
        case .monochromeNight: "Minimal look, night lighting"
        case .satellite3D: "Imagery draped over 3D terrain and buildings"
        case .satelliteStreets: "Imagery with street and label overlay"
        case .streets: "The classic flat street map"
        case .outdoors: "Trails, terrain contours and parks"
        case .light: "Flat, airy grayscale for data overlays"
        case .dark: "Flat charcoal base, great for glowing pins"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standardDay: .standard(lightPreset: .day)
        case .standardDawn: .standard(lightPreset: .dawn)
        case .standardDusk: .standard(lightPreset: .dusk)
        case .standardNight: .standard(lightPreset: .night)
        case .fadedDay: .standard(theme: .faded, lightPreset: .day)
        case .fadedNight: .standard(theme: .faded, lightPreset: .night)
        case .monochromeDay: .standard(theme: .monochrome, lightPreset: .day)
        case .monochromeNight: .standard(theme: .monochrome, lightPreset: .night)
        case .satellite3D: .standardSatellite(lightPreset: .day)
        case .satelliteStreets: .satelliteStreets
        case .streets: .streets
        case .outdoors: .outdoors
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Resolves a stored theme value — either a built-in `MapThemeOption` raw
/// value or a full custom style URL (`mapbox://styles/owner/id`) pasted from
/// Mapbox Studio or the community gallery. Any Mapbox style that is set to
/// public can be rendered by the SDK this way.
enum MapThemeSelection {
    /// True when the raw value is a full Mapbox style URL rather than a
    /// built-in option.
    static func isCustomRaw(_ raw: String) -> Bool {
        raw.hasPrefix("mapbox://styles/")
    }

    /// The `MapStyle` for any stored raw value. Unrecognized values fall back
    /// to the default built-in theme.
    static func mapStyle(forRaw raw: String) -> MapStyle {
        if isCustomRaw(raw), let uri = StyleURI(rawValue: raw) {
            return MapStyle(uri: uri)
        }
        return MapThemeOption.stored(from: raw).mapStyle
    }

    static func label(forRaw raw: String) -> String {
        isCustomRaw(raw) ? "Community style" : MapThemeOption.stored(from: raw).label
    }

    static func detail(forRaw raw: String) -> String {
        if isCustomRaw(raw) {
            return raw.replacingOccurrences(of: "mapbox://styles/", with: "")
        }
        return MapThemeOption.stored(from: raw).detail
    }

    /// Normalizes a user-pasted style reference into a canonical
    /// `mapbox://styles/owner/id` URL. Accepts the native style URL, the
    /// Styles API form (`https://api.mapbox.com/styles/v1/owner/id`), and
    /// Mapbox Studio share links. Returns nil when no owner/id pair is found.
    static func normalizeCustomInput(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var owner: String?
        var styleID: String?

        if trimmed.lowercased().hasPrefix("mapbox://styles/") {
            let path = trimmed.dropFirst("mapbox://styles/".count)
            let parts = path.split(separator: "?")[0].split(separator: "/").map(String.init)
            if parts.count >= 2 {
                owner = parts[0]
                styleID = parts[1]
            }
        } else if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            let parts = url.pathComponents.filter { $0 != "/" }
            if let stylesIndex = parts.lastIndex(of: "styles") {
                var rest = Array(parts.dropFirst(stylesIndex + 1))
                if rest.first == "v1" { rest.removeFirst() }
                if rest.count >= 2 {
                    owner = rest[0]
                    styleID = rest[1].replacingOccurrences(of: ".html", with: "")
                }
            }
        }

        guard let owner, let styleID,
              isValidComponent(owner), isValidComponent(styleID) else { return nil }
        let raw = "mapbox://styles/\(owner)/\(styleID)"
        guard StyleURI(rawValue: raw) != nil else { return nil }
        return raw
    }

    private static func isValidComponent(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "."
        }
    }
}

/// Shared camera math for the app's Mapbox maps.
enum MapCameraMath {
    /// Converts a MapKit-style span delta (degrees of latitude visible) into
    /// an equivalent Mapbox zoom level.
    static func zoom(forSpanDelta span: Double) -> Double {
        guard span > 0 else { return 13 }
        return min(max(log2(360 / span), 1), 17)
    }
}

/// Per-memory theme cascade: a memory with its own theme keeps it; a memory
/// without one follows the app-wide pick from Settings, so it always matches
/// the Explore globe by default.
extension Memory {
    /// The theme raw value chosen just for this memory, when set and still
    /// usable: a built-in option's raw value or a custom style URL.
    var mapThemeOverrideRaw: String? {
        guard let raw = mapTheme, !raw.isEmpty else { return nil }
        if MapThemeSelection.isCustomRaw(raw) { return raw }
        return MapThemeOption(rawValue: raw)?.rawValue
    }

    /// The raw theme this memory's map should render with, given the app-wide
    /// value stored under `MapThemeOption.storageKey`.
    func resolvedMapThemeRaw(globalRaw: String) -> String {
        mapThemeOverrideRaw ?? globalRaw
    }
}
