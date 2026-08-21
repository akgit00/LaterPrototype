import SwiftUI
import CoreLocation
import MapboxMaps

/// A few camera destinations where the styles show off well.
enum LabCity: String, CaseIterable, Identifiable {
    case newYork
    case london
    case paris
    case tokyo
    case sanFrancisco

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newYork: "New York"
        case .london: "London"
        case .paris: "Paris"
        case .tokyo: "Tokyo"
        case .sanFrancisco: "San Francisco"
        }
    }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .newYork: CLLocationCoordinate2D(latitude: 40.7061, longitude: -74.0086)
        case .london: CLLocationCoordinate2D(latitude: 51.5007, longitude: -0.1246)
        case .paris: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945)
        case .tokyo: CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005)
        case .sanFrancisco: CLLocationCoordinate2D(latitude: 37.7936, longitude: -122.3930)
        }
    }
}

/// Theme picker: a live preview of the current pick up top, and a grid of
/// rendered map thumbnails below — tap any box to make it the globe's style.
struct MapThemeLabView: View {
    @Environment(ProfileManager.self) private var profile
    @AppStorage(MapThemeOption.storageKey) private var storedThemeRaw: String = MapThemeOption.defaultTheme.rawValue
    @State private var heroViewport: Viewport
    @State private var selectedCity: LabCity = .newYork
    @State private var customInput: String = ""
    @State private var customError: String?

    private var previews: MapThemePreviewStore { .shared }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    init() {
        MapboxSetup.configureIfNeeded()
        _heroViewport = State(initialValue: Self.viewport(for: .newYork))
    }

    var body: some View {
        Group {
            if MapboxSetup.hasToken {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroPreview
                        themeGrid
                        communitySection
                    }
                    .padding(.vertical, 16)
                }
                .background(Color(.systemGroupedBackground))
                .scrollDismissesKeyboard(.interactively)
            } else {
                ContentUnavailableView {
                    Label("Mapbox token missing", systemImage: "key.slash")
                } description: {
                    Text("Add your Mapbox public token and rebuild the app to preview map themes.")
                }
            }
        }
        .navigationTitle("Map Themes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await previews.generateAll() }
        .sensoryFeedback(.selection, trigger: storedThemeRaw)
        .sensoryFeedback(.impact(weight: .light), trigger: selectedCity)
        .onChange(of: selectedCity) { _, newCity in
            withViewportAnimation(.fly) {
                heroViewport = Self.viewport(for: newCity)
            }
        }
    }

    // MARK: - Hero

    private var heroPreview: some View {
        Map(viewport: $heroViewport) {
            samplePin(latOffset: 0.0012, lonOffset: -0.0018, emoji: "📸", tint: .blue)
            samplePin(latOffset: -0.0008, lonOffset: 0.0014, emoji: "🎂", tint: .pink)
            samplePin(latOffset: 0.0005, lonOffset: 0.0028, emoji: "🎶", tint: .purple)
        }
        .mapStyle(MapThemeSelection.mapStyle(forRaw: storedThemeRaw))
        .allowsHitTesting(false)
        .frame(height: 250)
        .overlay {
            LinearGradient(
                colors: [.clear, .clear, .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .bottomLeading) {
            heroInfo
                .padding(14)
        }
        .overlay(alignment: .topTrailing) {
            cityMenu
                .padding(10)
        }
        .padding(.horizontal, 16)
    }

    private var heroInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(MapThemeSelection.label(forRaw: storedThemeRaw))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(MapThemeSelection.detail(forRaw: storedThemeRaw))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Label("Live on your globe and memory maps", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.green.opacity(0.9), in: Capsule())
                .padding(.top, 4)
        }
    }

    private var cityMenu: some View {
        Menu {
            Picker("Fly to", selection: $selectedCity) {
                ForEach(LabCity.allCases) { city in
                    Text(city.label).tag(city)
                }
            }
        } label: {
            Label(selectedCity.label, systemImage: "paperplane.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
        }
    }

    /// Sample memory-style pins near the current city so every theme can be
    /// judged with real markers on top.
    private func samplePin(latOffset: Double, lonOffset: Double, emoji: String, tint: Color) -> some MapContent {
        MapViewAnnotation(coordinate: CLLocationCoordinate2D(
            latitude: selectedCity.coordinate.latitude + latOffset,
            longitude: selectedCity.coordinate.longitude + lonOffset
        )) {
            LabMemoryPin(emoji: emoji, tint: tint)
        }
        .allowOverlap(true)
        .allowZElevate(true)
    }

    // MARK: - Theme grid

    private var themeGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a style")
                .font(.headline)
                .padding(.horizontal, 16)

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(MapThemeOption.allCases) { option in
                    themeCard(option)
                }
            }
            .padding(.horizontal, 16)

            Text("Tap any style to apply it to your globe and memory maps. Previews are rendered live by Mapbox.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }

    private func themeCard(_ option: MapThemeOption) -> some View {
        let isSelected = option.rawValue == storedThemeRaw
        return Button {
            select(option.rawValue)
        } label: {
            Color(.secondarySystemBackground)
                .frame(height: 132)
                .overlay {
                    if let image = previews.image(for: option) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    } else if previews.hasFailed(option) {
                        VStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("Preview unavailable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .bottomLeading) {
                    Text(option.label)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 8 : 4, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isSelected)
    }

    // MARK: - Community & custom styles

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community styles")
                .font(.headline)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                if MapThemeSelection.isCustomRaw(storedThemeRaw) {
                    activeCustomCard
                }

                Text("Use any public style from the Mapbox gallery or one you designed in Mapbox Studio: add the template to your Mapbox account, copy its style URL, and paste it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("mapbox://styles/username/styleid", text: $customInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote)
                        .onSubmit { applyCustomStyle() }

                    Button("Apply") {
                        applyCustomStyle()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let customError {
                    Label(customError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Link(destination: URL(string: "https://www.mapbox.com/gallery/")!) {
                    Label("Browse the Mapbox style gallery", systemImage: "safari")
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 16)
        }
    }

    /// Shown while a pasted community style is live, with a way back to the
    /// built-in default.
    private var activeCustomCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Community style active")
                    .font(.footnote.weight(.semibold))
                Text(MapThemeSelection.detail(forRaw: storedThemeRaw))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Remove") {
                select(MapThemeOption.defaultTheme.rawValue)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
        }
    }

    /// Applies a theme everywhere and saves it to the user's cloud profile so
    /// the pick survives reinstalls and follows their account.
    private func select(_ raw: String) {
        storedThemeRaw = raw
        profile.saveMapTheme(raw)
    }

    private func applyCustomStyle() {
        guard let raw = MapThemeSelection.normalizeCustomInput(customInput) else {
            customError = "That doesn't look like a Mapbox style URL. In Mapbox Studio, use Share and copy the Style URL."
            return
        }
        customError = nil
        customInput = ""
        select(raw)
    }

    private static func viewport(for city: LabCity) -> Viewport {
        .camera(center: city.coordinate, zoom: 15.6, bearing: -17.6, pitch: 60)
    }
}

/// Mimics the app's memory pins so themes are judged with markers on top.
private struct LabMemoryPin: View {
    let emoji: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.gradient)
            Text(emoji)
                .font(.system(size: 15))
        }
        .frame(width: 34, height: 34)
        .overlay(Circle().stroke(.white, lineWidth: 2.5))
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}
