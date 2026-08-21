import SwiftUI
import MapKit

/// Lets the memory's owner edit its core details: title, description, date,
/// pinned location (via search or tapping the map), and an optional map style
/// just for this memory.
struct EditMemorySheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MapThemeOption.storageKey) private var globalThemeRaw: String = MapThemeOption.defaultTheme.rawValue

    @State private var title: String
    @State private var subtitle: String
    @State private var date: Date
    @State private var coordinate: CLLocationCoordinate2D
    @State private var addressQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var mapPosition: MapCameraPosition
    @State private var resolvedAddress: String?
    @State private var mapThemeRaw: String?
    @State private var customStyleInput: String = ""
    @State private var customStyleError: String?

    private var previews: MapThemePreviewStore { .shared }

    init(memoryID: UUID, viewModel: LaterViewModel) {
        self.memoryID = memoryID
        self.viewModel = viewModel
        let memory = viewModel.memoryByID(memoryID)
        _title = State(initialValue: memory?.title ?? "")
        _subtitle = State(initialValue: memory?.subtitle ?? "")
        _date = State(initialValue: memory?.date ?? Date())
        _mapThemeRaw = State(initialValue: memory?.mapThemeOverrideRaw)
        let center = memory?.centerCoordinate ?? CLLocationCoordinate2D()
        _coordinate = State(initialValue: center)
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    fieldSection(header: "Title") {
                        TextField("Memory title", text: $title)
                            .font(.body)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    fieldSection(header: "Description") {
                        TextField("A short tagline...", text: $subtitle, axis: .vertical)
                            .font(.body)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    fieldSection(header: "Date") {
                        DatePicker("", selection: $date, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    fieldSection(header: "Location") {
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search a new place...", text: $addressQuery)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                                    .onSubmit { searchAddress() }
                                if !addressQuery.isEmpty {
                                    Button {
                                        addressQuery = ""
                                        searchResults = []
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                            if !searchResults.isEmpty {
                                VStack(spacing: 0) {
                                    ForEach(searchResults.prefix(4), id: \.self) { item in
                                        Button {
                                            select(item)
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: "mappin.circle.fill")
                                                    .foregroundStyle(.red)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(item.name ?? "Unknown")
                                                        .font(.subheadline.weight(.medium))
                                                        .foregroundStyle(.primary)
                                                    if let placeTitle = item.placemark.title {
                                                        Text(placeTitle)
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .lineLimit(1)
                                                    }
                                                }
                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                        }
                                        Divider().padding(.leading, 40)
                                    }
                                }
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                            }

                            MapReader { reader in
                                Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                                    Annotation("", coordinate: coordinate) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 30))
                                            .foregroundStyle(.red)
                                            .shadow(color: .black.opacity(0.3), radius: 4)
                                    }
                                }
                                .mapStyle(.standard(elevation: .realistic))
                                .frame(height: 220)
                                .clipShape(.rect(cornerRadius: 12))
                                .onTapGesture { location in
                                    if let tapped = reader.convert(location, from: .local) {
                                        coordinate = tapped
                                        resolveAddress()
                                    }
                                }
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.caption2)
                                Text(resolvedAddress ?? "Tap the map to move the pin")
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if MapboxSetup.hasToken {
                        fieldSection(header: "Map style") {
                            mapStyleSection
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Edit Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { resolveAddress() }
            .task { await previews.generateAll() }
            .sensoryFeedback(.selection, trigger: mapThemeRaw)
        }
    }

    // MARK: - Map style picker

    /// Lets this memory keep its own map look while everything else follows
    /// the app-wide pick from Settings.
    private var mapStyleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    matchAppCard
                    ForEach(MapThemeOption.allCases) { option in
                        themeCard(option)
                    }
                }
            }

            if let raw = mapThemeRaw, MapThemeSelection.isCustomRaw(raw) {
                activeCustomChip(raw)
            }

            customStyleField

            Text("This memory's map follows your app-wide style unless you pick one just for it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// The default: no override, so the memory always matches Settings.
    private var matchAppCard: some View {
        let globalOption = MapThemeOption(rawValue: globalThemeRaw)
        return Button {
            mapThemeRaw = nil
        } label: {
            themeCardBody(
                image: globalOption.flatMap { previews.image(for: $0) },
                fallbackIcon: globalOption == nil ? "paintpalette.fill" : nil,
                label: "App setting",
                isSelected: mapThemeRaw == nil
            )
        }
        .buttonStyle(.plain)
    }

    private func themeCard(_ option: MapThemeOption) -> some View {
        Button {
            mapThemeRaw = option.rawValue
        } label: {
            themeCardBody(
                image: previews.image(for: option),
                fallbackIcon: previews.hasFailed(option) ? "wifi.slash" : nil,
                label: option.label,
                isSelected: mapThemeRaw == option.rawValue
            )
        }
        .buttonStyle(.plain)
    }

    private func themeCardBody(image: UIImage?, fallbackIcon: String?, label: String, isSelected: Bool) -> some View {
        Color(.secondarySystemBackground)
            .frame(width: 128, height: 96)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .allowsHitTesting(false)
                } else if let fallbackIcon {
                    Image(systemName: fallbackIcon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .bottomLeading) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
            }
            .animation(.spring(duration: 0.25), value: isSelected)
    }

    /// Shown while this memory uses a pasted community style.
    private func activeCustomChip(_ raw: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "paintpalette.fill")
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Community style just for this memory")
                    .font(.caption.weight(.semibold))
                Text(MapThemeSelection.detail(forRaw: raw))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Remove") { mapThemeRaw = nil }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var customStyleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Community style URL (optional)", text: $customStyleInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote)
                    .onSubmit { applyCustomStyle() }

                Button("Apply") { applyCustomStyle() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .disabled(customStyleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let customStyleError {
                Label(customStyleError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func applyCustomStyle() {
        guard let raw = MapThemeSelection.normalizeCustomInput(customStyleInput) else {
            customStyleError = "That doesn't look like a Mapbox style URL. In Mapbox Studio, use Share and copy the Style URL."
            return
        }
        customStyleError = nil
        customStyleInput = ""
        mapThemeRaw = raw
    }

    private func fieldSection(header: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func searchAddress() {
        guard !addressQuery.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = addressQuery
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            searchResults = response?.mapItems ?? []
        }
    }

    private func select(_ item: MKMapItem) {
        coordinate = item.placemark.coordinate
        addressQuery = item.name ?? ""
        searchResults = []
        resolvedAddress = item.placemark.title
        withAnimation(.spring(duration: 0.5)) {
            mapPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        }
    }

    private func resolveAddress() {
        let target = coordinate
        Task {
            resolvedAddress = await LocationService.address(for: target)
        }
    }

    private func save() {
        viewModel.updateMemoryDetails(
            memoryID: memoryID,
            title: title.trimmingCharacters(in: .whitespaces),
            subtitle: subtitle.trimmingCharacters(in: .whitespaces),
            date: date,
            coordinate: coordinate,
            mapTheme: mapThemeRaw
        )
        dismiss()
    }
}
