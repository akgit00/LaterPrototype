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
    @State private var showSavePrompt = false
    @State private var saveNameInput = ""
    @State private var renamingStyleRaw: String?
    @State private var renameInput = ""

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
        .sensoryFeedback(.impact(weight: .medium), trigger: profile.savedMapStyles.count)
        .alert("Save this style", isPresented: $showSavePrompt) {
            TextField("Style name", text: $saveNameInput)
            Button("Save") {
                profile.saveStyle(raw: storedThemeRaw, name: saveNameInput)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It'll be one tap away under Your saved styles, on every device you sign in to.")
        }
        .alert("Rename style", isPresented: Binding(
            get: { renamingStyleRaw != nil },
            set: { if !$0 { renamingStyleRaw = nil } }
        )) {
            TextField("Style name", text: $renameInput)
            Button("Save") {
                if let raw = renamingStyleRaw {
                    profile.saveStyle(raw: raw, name: renameInput)
                }
                renamingStyleRaw = nil
            }
            Button("Cancel", role: .cancel) { renamingStyleRaw = nil }
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

                if !profile.savedMapStyles.isEmpty {
                    Text("Your saved styles — tap to apply, hold to rename or remove:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(profile.savedMapStyles) { style in
                                savedStyleCard(style)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()
                }

                Text("Designer styles from the Mapbox gallery — tap to try one:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(MapboxDesignerStyle.gallery) { style in
                            designerCard(style)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                Text("Or paste a gallery link exactly as shared — like mapbox.com/gallery#community-mineral — type a style name like “Pencil”, or paste any public style URL from Mapbox Studio (Share → copy Style URL).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Gallery link, style name, or style URL", text: $customInput)
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

    /// One-tap card for a Mapbox-made designer style.
    private func designerCard(_ style: MapboxDesignerStyle) -> some View {
        let isSelected = storedThemeRaw == style.raw
        return Button {
            select(style.raw)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Circle()
                        .fill(style.swatch.gradient)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle().strokeBorder(.black.opacity(0.1), lineWidth: 1)
                        }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(style.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(style.blurb)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(10)
            .frame(width: 140, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: isSelected)
    }

    /// Shown while a pasted community style is live, with a bookmark to keep
    /// it in the saved collection and a way back to the built-in default.
    private var activeCustomCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(MapThemeSelection.label(forRaw: storedThemeRaw)) active")
                    .font(.footnote.weight(.semibold))
                Text(MapThemeSelection.detail(forRaw: storedThemeRaw))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                toggleSaveForActiveStyle()
            } label: {
                Label(
                    profile.isStyleSaved(storedThemeRaw) ? "Saved" : "Save",
                    systemImage: profile.isStyleSaved(storedThemeRaw) ? "bookmark.fill" : "bookmark"
                )
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Color.accentColor)
            .accessibilityLabel(profile.isStyleSaved(storedThemeRaw) ? "Remove from saved styles" : "Save this style")

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

    /// One-tap card for a style the user bookmarked from a pasted link.
    private func savedStyleCard(_ style: SavedMapStyle) -> some View {
        let isSelected = storedThemeRaw == style.raw
        return Button {
            select(style.raw)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "bookmark.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(style.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(MapThemeSelection.detail(forRaw: style.raw))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(10)
            .frame(width: 140, alignment: .leading)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: isSelected)
        .contextMenu {
            Button {
                renameInput = style.name
                renamingStyleRaw = style.raw
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                profile.removeSavedStyle(raw: style.raw)
            } label: {
                Label("Remove from saved", systemImage: "bookmark.slash")
            }
        }
    }

    /// Bookmarks the active custom style (asking for a name first) or drops
    /// it from the collection when it's already saved.
    private func toggleSaveForActiveStyle() {
        if profile.isStyleSaved(storedThemeRaw) {
            profile.removeSavedStyle(raw: storedThemeRaw)
        } else {
            saveNameInput = MapThemeSelection.suggestedSaveName(forRaw: storedThemeRaw)
            showSavePrompt = true
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
            if MapThemeSelection.isGalleryLink(customInput) {
                customError = "Couldn't match that gallery link to a style. Tap the style in the gallery first so the link ends in #community-…, or copy its Style URL instead."
            } else {
                customError = "That doesn't look like a Mapbox style. Paste a gallery link, a style name, or a Style URL from Mapbox Studio."
            }
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
