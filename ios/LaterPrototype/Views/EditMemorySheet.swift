import SwiftUI
import MapKit

/// Lets the memory's owner edit its core details: title, description, date,
/// and pinned location (via search or tapping the map).
struct EditMemorySheet: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var subtitle: String
    @State private var date: Date
    @State private var coordinate: CLLocationCoordinate2D
    @State private var addressQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var mapPosition: MapCameraPosition
    @State private var resolvedAddress: String?

    init(memoryID: UUID, viewModel: LaterViewModel) {
        self.memoryID = memoryID
        self.viewModel = viewModel
        let memory = viewModel.memoryByID(memoryID)
        _title = State(initialValue: memory?.title ?? "")
        _subtitle = State(initialValue: memory?.subtitle ?? "")
        _date = State(initialValue: memory?.date ?? Date())
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
            coordinate: coordinate
        )
        dismiss()
    }
}
