import SwiftUI
import MapKit

/// Create / edit sheet for a memory pinned inside another memory: a title,
/// a date, and a spot picked by search or by tapping the map.
struct SubMemoryEditorSheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    let existing: SubMemory?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var date: Date
    @State private var coordinate: CLLocationCoordinate2D
    @State private var addressQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var mapPosition: MapCameraPosition
    @State private var resolvedAddress: String?

    private var parentTitle: String {
        viewModel.memoryByID(memoryID)?.title ?? "this memory"
    }

    init(memoryID: UUID, viewModel: LaterViewModel, existing: SubMemory?) {
        self.memoryID = memoryID
        self.viewModel = viewModel
        self.existing = existing
        let memory = viewModel.memoryByID(memoryID)
        let center = existing?.coordinate ?? memory?.centerCoordinate ?? CLLocationCoordinate2D()
        _title = State(initialValue: existing?.title ?? "")
        _date = State(initialValue: existing?.date ?? memory?.date ?? Date())
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
                    if existing == nil {
                        Label(
                            "This pins a smaller memory inside \"\(parentTitle)\". It shows on the map connected by a red thread, and photos and videos can be pinned to it.",
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    fieldSection(header: "Title") {
                        TextField("Where you fished, rode, ate...", text: $title)
                            .font(.body)
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

                    fieldSection(header: "Spot") {
                        VStack(spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search the place...", text: $addressQuery)
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
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(existing == nil ? "Pin a Memory Inside" : "Edit Pinned Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Pin" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task { resolveAddress() }
        }
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
        // Bias results toward the parent memory's area, since a pinned memory
        // usually happened nearby.
        if let memory = viewModel.memoryByID(memoryID) {
            request.region = MKCoordinateRegion(
                center: memory.centerCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
            )
        }
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
        if title.trimmingCharacters(in: .whitespaces).isEmpty, let name = item.name {
            title = name
        }
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
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if let existing {
            viewModel.updateSubMemoryDetails(
                memoryID: memoryID,
                subMemoryID: existing.id,
                title: trimmed,
                coordinate: coordinate,
                date: date
            )
        } else {
            viewModel.addSubMemory(to: memoryID, title: trimmed, coordinate: coordinate, date: date)
        }
        dismiss()
    }
}

/// Photo-preview marker for a memory pinned inside another, shown at its
/// spot on the map's red web.
struct SubMemoryPinCard: View {
    let imageURL: String?
    let mediaCount: Int
    let isSelected: Bool

    private var side: CGFloat { isSelected ? 82 : 64 }

    var body: some View {
        VStack(spacing: 2) {
            Color(.secondarySystemBackground)
                .frame(width: side, height: side)
                .overlay {
                    if let imageURL {
                        MediaImageView(urlString: imageURL)
                            .allowsHitTesting(false)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [.red.opacity(0.85), .orange.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "mappin.and.ellipse")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.red : Color.white, lineWidth: isSelected ? 3 : 2)
                }
                .overlay(alignment: .topTrailing) {
                    if mediaCount > 0 {
                        Text("\(mediaCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.red, in: Capsule())
                            .overlay {
                                Capsule().stroke(.white, lineWidth: 1)
                            }
                            .offset(x: 7, y: -7)
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

            Image(systemName: "triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.red)
                .rotationEffect(.degrees(180))
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
        .animation(.spring(duration: 0.3), value: isSelected)
    }
}

/// The main memory's marker at the center of the web. Tapping it clears any
/// pinned-memory filter and shows everything again.
struct MemoryHubPinCard: View {
    let imageURL: String?
    let isDimmed: Bool

    var body: some View {
        VStack(spacing: 2) {
            Color(.secondarySystemBackground)
                .frame(width: 92, height: 92)
                .overlay {
                    if let imageURL {
                        MediaImageView(urlString: imageURL)
                            .allowsHitTesting(false)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [.red, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "heart.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.red, lineWidth: 3)
                }
                .overlay(alignment: .topLeading) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.red, in: Circle())
                        .overlay {
                            Circle().stroke(.white, lineWidth: 1)
                        }
                        .offset(x: -7, y: -7)
                }
                .shadow(color: .black.opacity(0.45), radius: 7, x: 0, y: 3)
                .opacity(isDimmed ? 0.75 : 1)

            Image(systemName: "triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.red)
                .rotationEffect(.degrees(180))
                .shadow(color: .black.opacity(0.3), radius: 2)
        }
        .animation(.easeInOut(duration: 0.25), value: isDimmed)
    }
}
