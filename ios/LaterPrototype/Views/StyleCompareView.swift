import SwiftUI
import CoreLocation
import MapboxMaps

/// Side-by-side live comparison of the map's current style and a saved
/// style, rendered at the same camera with a sample pin so palette, detail,
/// and marker contrast differences pop before committing to a switch.
struct StyleCompareView: View {
    let currentRaw: String
    let candidate: SavedMapStyle
    let onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentViewport: Viewport
    @State private var candidateViewport: Viewport
    @State private var city: LabCity = .newYork

    init(currentRaw: String, candidate: SavedMapStyle, onApply: @escaping (String) -> Void) {
        self.currentRaw = currentRaw
        self.candidate = candidate
        self.onApply = onApply
        MapboxSetup.configureIfNeeded()
        let start = Self.viewport(for: .newYork)
        _currentViewport = State(initialValue: start)
        _candidateViewport = State(initialValue: start)
    }

    private var isSameStyle: Bool { currentRaw == candidate.raw }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    comparePane(
                        badge: "Current",
                        badgeTint: Color(.systemGray),
                        name: MapThemeSelection.label(forRaw: currentRaw),
                        raw: currentRaw,
                        viewport: $currentViewport
                    )
                    comparePane(
                        badge: "Saved",
                        badgeTint: Color.accentColor,
                        name: candidate.name,
                        raw: candidate.raw,
                        viewport: $candidateViewport
                    )
                }
                .frame(maxHeight: .infinity)

                Text(isSameStyle
                     ? "This saved style is already live on your map."
                     : "Pan or zoom each side freely — pick a city to line both cameras back up.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    onApply(candidate.raw)
                    dismiss()
                } label: {
                    Label("Use \(candidate.name)", systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSameStyle)
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Compare Styles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    cityMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: city) { _, newCity in
                withViewportAnimation(.fly) {
                    currentViewport = Self.viewport(for: newCity)
                    candidateViewport = Self.viewport(for: newCity)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: city)
        }
        .presentationDetents([.large])
    }

    private var cityMenu: some View {
        Menu {
            Picker("Fly to", selection: $city) {
                ForEach(LabCity.allCases) { city in
                    Text(city.label).tag(city)
                }
            }
        } label: {
            Label(city.label, systemImage: "paperplane.fill")
                .font(.caption.weight(.semibold))
        }
    }

    /// One half of the comparison: a live interactive map with a badge on
    /// top and the style's name underneath.
    private func comparePane(
        badge: String,
        badgeTint: Color,
        name: String,
        raw: String,
        viewport: Binding<Viewport>
    ) -> some View {
        VStack(spacing: 6) {
            Map(viewport: viewport) {
                MapViewAnnotation(coordinate: pinCoordinate) {
                    LabMemoryPin(emoji: "📸", tint: .blue)
                }
                .allowOverlap(true)
                .allowZElevate(true)
            }
            .mapStyle(MapThemeSelection.mapStyle(forRaw: raw))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeTint.opacity(0.9), in: Capsule())
                    .padding(8)
                    .allowsHitTesting(false)
            }

            Text(name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Text(MapThemeSelection.detail(forRaw: raw))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Sample pin near the current city so marker legibility can be judged
    /// on both styles at once.
    private var pinCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: city.coordinate.latitude + 0.0008,
            longitude: city.coordinate.longitude + 0.0010
        )
    }

    private static func viewport(for city: LabCity) -> Viewport {
        .camera(center: city.coordinate, zoom: 15.6, bearing: -17.6, pitch: 60)
    }
}
