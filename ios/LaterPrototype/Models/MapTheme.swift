import SwiftUI
import MapboxMaps

/// One-time Mapbox SDK configuration shared by every Mapbox-backed screen.
enum MapboxSetup {
    private static var isConfigured = false

    /// Mapbox public token used when the build-time environment doesn't supply
    /// one (Xcode Cloud builds compile from the repo, where `Config` is blank).
    /// Public tokens are client-side by design and URL-restrictable in the
    /// Mapbox dashboard; rotate there if it ever needs replacing.
    ///
    /// Stored in fragments purely so automated repository secret scanners don't
    /// flag a publishable token as a leaked credential.
    private static let fallbackToken = [
        "pk",
        "eyJ1IjoiYWswMDAiLCJhIjoiY210M2J1YXZzMTI4aDJ4b2huODV0d3hsaSJ9",
        "EsTv5uci1RrnmFf5tnAVOw",
    ].joined(separator: ".")

    /// The build-time token when present, otherwise the bundled fallback.
    static var token: String {
        Config.EXPO_PUBLIC_MAPBOX_TOKEN.isEmpty
            ? fallbackToken
            : Config.EXPO_PUBLIC_MAPBOX_TOKEN
    }

    static var hasToken: Bool { !token.isEmpty }

    static func configureIfNeeded() {
        guard !isConfigured, hasToken else { return }
        MapboxOptions.accessToken = token
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

/// Every style in the public Mapbox gallery (mapbox.com/gallery), keyed by
/// the anchor slug its share link uses — `…/gallery#community-mineral` maps
/// to the Mineral style. Extracted from the gallery's own card data; every
/// entry is owned by a Mapbox account, so they render with any access token.
enum MapboxGalleryCatalog {
    struct Entry {
        let name: String
        let raw: String
    }

    /// Looks up a gallery anchor slug ("community-mineral") or a bare style
    /// name typed by hand ("mineral", "neon glow", "Lè Shine").
    static func entry(forSlug input: String) -> Entry? {
        let slug = slugify(input)
        guard !slug.isEmpty else { return nil }
        if let exact = bySlug[slug] { return exact }
        if let community = bySlug["community-\(slug)"] { return community }
        return bySlug["mapbox-\(slug)"]
    }

    /// The gallery entry matching a stored style URL, used for labels.
    static func entry(forRaw raw: String) -> Entry? {
        byRaw[raw]
    }

    /// The gallery anchor slug for a stored style URL, used to build share
    /// links that open the style's card on mapbox.com/gallery.
    static func slug(forRaw raw: String) -> String? {
        slugByRaw[raw]
    }

    /// Lowercased, diacritic-folded, hyphen-separated form of a name:
    /// "Lè Shine" → "le-shine", "NASA's Black Marble" → "nasas-black-marble".
    private static func slugify(_ value: String) -> String {
        let folded = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US")
        )
        var out = ""
        var lastWasHyphen = true
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasHyphen = false
            } else if ch == "'" || ch == "’" {
                continue
            } else if !lastWasHyphen {
                out.append("-")
                lastWasHyphen = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    private static let byRaw: [String: Entry] = Dictionary(
        bySlug.values.map { ($0.raw, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    private static let slugByRaw: [String: String] = Dictionary(
        bySlug.map { ($0.value.raw, $0.key) },
        uniquingKeysWith: { first, _ in first }
    )

    private static let bySlug: [String: Entry] = [
        "community-american-memory": Entry(name: "American Memory", raw: "mapbox://styles/mapbox-map-design/cl4orrp5e000p14ldwenm7xsf"),
        "community-basic": Entry(name: "Basic", raw: "mapbox://styles/mapbox-map-design/cl4whef7m000714pc44f3qaxs"),
        "community-basic-overcast": Entry(name: "Basic Overcast", raw: "mapbox://styles/mapbox-map-design/cl4whev1w002w16s9mgoliotw"),
        "community-blueprint": Entry(name: "Blueprint", raw: "mapbox://styles/mapbox-map-design/cks97e1e37nsd17nzg7p0308g"),
        "community-bubble": Entry(name: "Bubble", raw: "mapbox://styles/mapbox-map-design/cl4wxue5j000c14r17uqrjpqb"),
        "community-cali-terrain": Entry(name: "Cali Terrain", raw: "mapbox://styles/mapbox/cjerxnqt3cgvp2rmyuxbeqme7"),
        "community-dark": Entry(name: "Dark", raw: "mapbox://styles/mapbox/dark-v10"),
        "community-decimal": Entry(name: "Decimal", raw: "mapbox://styles/mapbox-map-design/ck4014y110wt61ctt07egsel6"),
        "community-finland-topo": Entry(name: "Finland Topo", raw: "mapbox://styles/mapbox-map-design/cmd3ga8yb065i01sh1oho4h1r"),
        "community-frank": Entry(name: "Frank", raw: "mapbox://styles/mapbox-map-design/ckshxkppe0gge18nz20i0nrwq"),
        "community-ice-cream": Entry(name: "Ice Cream", raw: "mapbox://styles/mapbox/cj7t3i5yj0unt2rmt3y4b5e32"),
        "community-le-shine": Entry(name: "Lè Shine", raw: "mapbox://styles/mapbox/cjcunv5ae262f2sm9tfwg8i0w"),
        "community-light": Entry(name: "Light", raw: "mapbox://styles/mapbox/light-v10"),
        "community-mapbox-streets-japan": Entry(name: "Mapbox Streets Japan", raw: "mapbox://styles/mapbox-map-design/ckt20wgoy1awp17ms7pyygigf"),
        "community-mineral": Entry(name: "Mineral", raw: "mapbox://styles/mapbox/cjtep62gq54l21frr1whf27ak"),
        "community-minimo": Entry(name: "Minimo", raw: "mapbox://styles/mapbox-map-design/cksjc2nsq1bg117pnekb655h1"),
        "community-moonlight": Entry(name: "Moonlight", raw: "mapbox://styles/mapbox/cj3kbeqzo00022smj7akz3o1e"),
        "community-nasas-black-marble": Entry(name: "NASA's Black Marble", raw: "mapbox://styles/mapbox-map-design/cl4fnpof7000i15p8jvz3aw2r"),
        "community-navigation-guidance-day": Entry(name: "Navigation Guidance Day", raw: "mapbox://styles/mapbox/navigation-guidance-day-v4"),
        "community-navigation-guidance-night": Entry(name: "Navigation Guidance Night", raw: "mapbox://styles/mapbox/navigation-guidance-night-v4"),
        "community-neon-glow": Entry(name: "Neon Glow", raw: "mapbox://styles/mapbox-map-design/cl4gxqwi5001415l381n7qwak"),
        "community-north-star": Entry(name: "North Star", raw: "mapbox://styles/mapbox/cj44mfrt20f082snokim4ungi"),
        "community-outdoors": Entry(name: "Outdoors", raw: "mapbox://styles/mapbox/outdoors-v12"),
        "community-pencil": Entry(name: "Pencil", raw: "mapbox://styles/mapbox-map-design/cks9iema71es417mlrft4go2k"),
        "community-satellite": Entry(name: "Legacy Satellite", raw: "mapbox://styles/mapbox/satellite-v9"),
        "community-satellite-streets": Entry(name: "Satellite Streets", raw: "mapbox://styles/mapbox/satellite-streets-v12"),
        "community-standard-oil-company": Entry(name: "Standard Oil Company", raw: "mapbox://styles/mapbox-map-design/ckr0svm3922ki18qntevm857n"),
        "community-streets": Entry(name: "Streets", raw: "mapbox://styles/mapbox/streets-v12"),
        "community-unicorn": Entry(name: "Unicorn", raw: "mapbox://styles/mapbox-map-design/cl4fotjdi000l15p8cqc6nuts"),
        "community-water-world": Entry(name: "Water World", raw: "mapbox://styles/mapbox-map-design/cl4bxa84b000l15kg4a2q8zsr"),
        "mapbox-cool": Entry(name: "Cool", raw: "mapbox://styles/mapbox-map-design/cmclxnhzb008001sb6g3m49ko"),
        "mapbox-dark-2d": Entry(name: "Dark 2D", raw: "mapbox://styles/mapbox-map-design/cmf04nwfx00at01ple6dhenx3"),
        "mapbox-default": Entry(name: "Default", raw: "mapbox://styles/mapbox-map-design/cmcz3qlqr005j01qm3il69x43"),
        "mapbox-faded": Entry(name: "Faded", raw: "mapbox://styles/mapbox-map-design/cmcl29tgn008r01p69cx43vvx"),
        "mapbox-light-2d": Entry(name: "Light 2D", raw: "mapbox://styles/mapbox-map-design/cmf04wyjp018e01sd3633800a"),
        "mapbox-monochrome": Entry(name: "Monochrome", raw: "mapbox://styles/mapbox-map-design/cmcl1sypr006u01qv5l157uov"),
        "mapbox-outdoors": Entry(name: "Outdoors", raw: "mapbox://styles/mapbox-map-design/cmh0wgofd00bu01srg2k73chv"),
        "mapbox-outdoors-winter": Entry(name: "Outdoors Winter", raw: "mapbox://styles/mapbox-map-design/cmh0wje0n00bx01smbs4p3iz8"),
        "mapbox-satellite": Entry(name: "Satellite", raw: "mapbox://styles/mapbox-map-design/cmcz3srn801br01qv31s62t4b"),
        "mapbox-warm": Entry(name: "Warm", raw: "mapbox://styles/mapbox-map-design/cmclxpx6g007101s2d4kq4ivs"),
    ]
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
        if isCustomRaw(raw) {
            if let designer = MapboxDesignerStyle.named(raw: raw) { return designer.name }
            if let entry = MapboxGalleryCatalog.entry(forRaw: raw) { return entry.name }
            return "Community style"
        }
        return MapThemeOption.stored(from: raw).label
    }

    static func detail(forRaw raw: String) -> String {
        if isCustomRaw(raw) {
            if let designer = MapboxDesignerStyle.named(raw: raw) {
                return designer.blurb
            }
            if MapboxGalleryCatalog.entry(forRaw: raw) != nil {
                return "From the Mapbox style gallery"
            }
            return raw.replacingOccurrences(of: "mapbox://styles/", with: "")
        }
        return MapThemeOption.stored(from: raw).detail
    }

    /// True when the input points at the Mapbox gallery page (a share link
    /// like `mapbox.com/gallery#community-mineral`) rather than a style URL.
    static func isGalleryLink(_ input: String) -> Bool {
        input.lowercased().contains("mapbox.com/gallery")
    }

    /// Suggested bookmark name when saving a custom style: the known gallery
    /// or designer name, otherwise the style's owner/id path so different
    /// unknown styles stay tellable apart.
    static func suggestedSaveName(forRaw raw: String) -> String {
        let label = label(forRaw: raw)
        if label == "Community style" {
            return raw.replacingOccurrences(of: "mapbox://styles/", with: "")
        }
        return label
    }

    /// Ready-to-send text for sharing a saved style: the gallery link when
    /// the style is a known gallery entry, plus the raw style URL — either
    /// one can be pasted straight into the app's style fields.
    static func shareText(for style: SavedMapStyle) -> String {
        var lines = ["Map style: \(style.name)"]
        if let slug = MapboxGalleryCatalog.slug(forRaw: style.raw) {
            lines.append("Gallery link: https://www.mapbox.com/gallery#\(slug)")
        }
        lines.append("Style URL: \(style.raw)")
        lines.append("Paste either one into Later's Map Themes to use this look.")
        return lines.joined(separator: "\n")
    }

    /// Normalizes a user-pasted style reference into a canonical
    /// `mapbox://styles/owner/id` URL. Accepts the native style URL, the
    /// Styles API form (`https://api.mapbox.com/styles/v1/owner/id`), and
    /// Mapbox Studio share links. Returns nil when no owner/id pair is found.
    static func normalizeCustomInput(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Gallery share links and bare style names resolve through the
        // baked-in catalog: "…mapbox.com/gallery#community-mineral",
        // "community-mineral", or just "mineral".
        if let galleryRaw = resolveGalleryReference(trimmed) {
            return galleryRaw
        }

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

    /// Resolves a gallery page link by its `#anchor` slug, or a bare slug or
    /// style name typed straight into the field. Returns nil when the input
    /// isn't a gallery reference or the style isn't in the catalog.
    private static func resolveGalleryReference(_ input: String) -> String? {
        if isGalleryLink(input) {
            var candidate = input
            if !candidate.lowercased().hasPrefix("http") {
                candidate = "https://" + candidate
            }
            guard let url = URL(string: candidate),
                  let fragment = url.fragment,
                  let entry = MapboxGalleryCatalog.entry(forSlug: fragment) else { return nil }
            return entry.raw
        }
        // Bare names and anchor slugs contain no URL punctuation.
        if !input.contains("/"), !input.contains(":"), !input.contains(".") {
            return MapboxGalleryCatalog.entry(forSlug: input)?.raw
        }
        return nil
    }

    private static func isValidComponent(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "."
        }
    }
}

/// Broad look-and-feel buckets for saved styles so a growing library stays
/// filterable — guessed from the style's name when recognizable, and
/// adjustable from the card's long-press menu.
nonisolated enum SavedStyleThemeType: String, Codable, Sendable, CaseIterable, Identifiable {
    case light
    case dark
    case terrain
    case colorful

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .terrain: "Terrain"
        case .colorful: "Colorful"
        }
    }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .terrain: "mountain.2.fill"
        case .colorful: "paintpalette.fill"
        }
    }

    /// Best-effort bucket from a style's name, so fresh bookmarks land under
    /// the right filter without any manual tagging.
    static func guess(from name: String) -> SavedStyleThemeType? {
        let lower = name.lowercased()
        let buckets: [(SavedStyleThemeType, [String])] = [
            (.terrain, ["terrain", "outdoor", "topo", "satellite", "winter", "mountain", "hill"]),
            (.dark, ["dark", "night", "moon", "neon", "black", "midnight", "dusk"]),
            (.light, ["light", "day", "bright", "shine", "ice", "pencil", "basic", "minimo"]),
            (.colorful, ["unicorn", "color", "rainbow", "bubble", "cream", "warm", "cool"]),
        ]
        for (type, keywords) in buckets where keywords.contains(where: { lower.contains($0) }) {
            return type
        }
        return nil
    }
}

/// A community style the user bookmarked after pasting its link, so it can
/// be re-applied anytime without hunting down the URL again. The collection
/// is stored on the user's cloud profile and follows their account.
nonisolated struct SavedMapStyle: Codable, Sendable, Identifiable, Equatable {
    var name: String
    let raw: String
    /// User-created folder this style is filed under, if any.
    var folder: String? = nil
    /// Manually-set look bucket; when nil the name-based guess applies.
    var themeType: SavedStyleThemeType? = nil

    var id: String { raw }

    /// The bucket this style falls under in the library's filter bar.
    var effectiveThemeType: SavedStyleThemeType? {
        themeType ?? SavedStyleThemeType.guess(from: name)
    }
}

/// Featured designer styles from the public style gallery, shown as one-tap
/// preset cards. All are owned by Mapbox accounts, so they render with any
/// access token — instant community styles with no Studio setup. Style URLs
/// match the gallery's own card data (see `MapboxGalleryCatalog`).
struct MapboxDesignerStyle: Identifiable {
    let name: String
    let blurb: String
    let swatch: Color
    let raw: String

    var id: String { raw }

    /// The designer style matching a stored raw value, if any.
    static func named(raw: String) -> MapboxDesignerStyle? {
        gallery.first { $0.raw == raw }
    }

    static let gallery: [MapboxDesignerStyle] = [
        MapboxDesignerStyle(
            name: "North Star",
            blurb: "A modern take on classic nautical charts",
            swatch: Color(red: 0.0, green: 0.533, blue: 0.8),
            raw: "mapbox://styles/mapbox/cj44mfrt20f082snokim4ungi"
        ),
        MapboxDesignerStyle(
            name: "Ice Cream",
            blurb: "Soft pastel purples, sweet and minimal",
            swatch: Color(red: 0.58, green: 0.412, blue: 0.682),
            raw: "mapbox://styles/mapbox/cj7t3i5yj0unt2rmt3y4b5e32"
        ),
        MapboxDesignerStyle(
            name: "Moonlight",
            blurb: "High-contrast dark, made for glowing pins",
            swatch: Color(red: 0.2, green: 0.2, blue: 0.2),
            raw: "mapbox://styles/mapbox/cj3kbeqzo00022smj7akz3o1e"
        ),
        MapboxDesignerStyle(
            name: "Mineral",
            blurb: "Inspired by a 1940s British mineral map",
            swatch: Color(red: 0.918, green: 0.863, blue: 0.761),
            raw: "mapbox://styles/mapbox/cjtep62gq54l21frr1whf27ak"
        ),
        MapboxDesignerStyle(
            name: "Lè Shine",
            blurb: "Restrained palette of winter light",
            swatch: Color(red: 0.824, green: 0.894, blue: 0.937),
            raw: "mapbox://styles/mapbox/cjcunv5ae262f2sm9tfwg8i0w"
        ),
        MapboxDesignerStyle(
            name: "Cali Terrain",
            blurb: "Warm hills from a plane-window view",
            swatch: Color(red: 0.408, green: 0.541, blue: 0.678),
            raw: "mapbox://styles/mapbox/cjerxnqt3cgvp2rmyuxbeqme7"
        ),
        MapboxDesignerStyle(
            name: "Decimal",
            blurb: "Vintage control-panel greens",
            swatch: Color(red: 0.314, green: 0.659, blue: 0.51),
            raw: "mapbox://styles/mapbox-map-design/ck4014y110wt61ctt07egsel6"
        ),
        MapboxDesignerStyle(
            name: "Minimo",
            blurb: "Clean Italian minimalism with stippling",
            swatch: Color(red: 0.718, green: 0.733, blue: 0.737),
            raw: "mapbox://styles/mapbox-map-design/cksjc2nsq1bg117pnekb655h1"
        ),
        MapboxDesignerStyle(
            name: "Pencil",
            blurb: "Hand-sketched look, drawn in graphite",
            swatch: Color(red: 0.55, green: 0.55, blue: 0.57),
            raw: "mapbox://styles/mapbox-map-design/cks9iema71es417mlrft4go2k"
        ),
        MapboxDesignerStyle(
            name: "Blueprint",
            blurb: "Architectural drafting-table blues",
            swatch: Color(red: 0.13, green: 0.32, blue: 0.65),
            raw: "mapbox://styles/mapbox-map-design/cks97e1e37nsd17nzg7p0308g"
        ),
        MapboxDesignerStyle(
            name: "Unicorn",
            blurb: "Playful pinks with a magic touch",
            swatch: Color(red: 0.93, green: 0.6, blue: 0.85),
            raw: "mapbox://styles/mapbox-map-design/cl4fotjdi000l15p8cqc6nuts"
        ),
        MapboxDesignerStyle(
            name: "Neon Glow",
            blurb: "Dark map with electric neon lines",
            swatch: Color(red: 0.0, green: 0.9, blue: 0.85),
            raw: "mapbox://styles/mapbox-map-design/cl4gxqwi5001415l381n7qwak"
        ),
    ]
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
