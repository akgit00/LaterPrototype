import SwiftUI
import MapKit

struct CreateMemoryView: View {
    let viewModel: LaterViewModel
    let initialCoordinate: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var subtitle: String = ""
    @State private var date: Date = Date()
    @State private var selectedConnections: Set<UUID> = []
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var addressQuery: String = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var mapPosition: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        distance: 10000000
    ))
    @State private var currentStep: Int = 0
    @State private var isSearching: Bool = false

    init(viewModel: LaterViewModel, initialCoordinate: CLLocationCoordinate2D? = nil) {
        self.viewModel = viewModel
        self.initialCoordinate = initialCoordinate
        if let coord = initialCoordinate {
            _pinCoordinate = State(initialValue: coord)
            _mapPosition = State(initialValue: .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                TabView(selection: $currentStep) {
                    locationStep
                        .tag(0)
                    detailsStep
                        .tag(1)
                    connectionsStep
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(duration: 0.4), value: currentStep)
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(currentStep == 0 ? "Cancel" : "Back") {
                        if currentStep == 0 {
                            dismiss()
                        } else {
                            currentStep -= 1
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(currentStep == 2 ? "Create" : "Next") {
                        if currentStep == 2 {
                            createMemory()
                        } else {
                            currentStep += 1
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canProceed)
                }
            }
            .safeAreaInset(edge: .bottom) {
                stepIndicator
            }
        }
    }

    private var stepTitle: String {
        switch currentStep {
        case 0: return "Pin Location"
        case 1: return "Memory Details"
        case 2: return "Add People"
        default: return ""
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case 0: return pinCoordinate != nil
        case 1: return !title.isEmpty
        case 2: return true
        default: return false
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.primary : Color(.tertiarySystemFill))
                    .frame(width: step == currentStep ? 24 : 8, height: 8)
            }
        }
        .padding(.bottom, 8)
        .animation(.spring(duration: 0.3), value: currentStep)
    }

    // MARK: - Location Step

    private var locationStep: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search address or place...", text: $addressQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
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
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if !searchResults.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults, id: \.self) { item in
                            Button {
                                selectSearchResult(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "Unknown")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if let subtitle = item.placemark.title {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }

                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            ZStack {
                Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
                    if let coord = pinCoordinate {
                        Annotation("", coordinate: coord) {
                            VStack(spacing: 0) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.red)
                                    .shadow(color: .black.opacity(0.3), radius: 4)

                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.red)
                                    .rotationEffect(.degrees(180))
                                    .offset(y: -3)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .clipShape(.rect(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if pinCoordinate == nil {
                    VStack {
                        Spacer()
                        Text("Search for a location or tap Next to place a pin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 16)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }

    // MARK: - Details Step

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("e.g. Summer Road Trip", text: $title)
                        .font(.body)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("A short tagline for this memory...", text: $subtitle, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...4)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Date")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    DatePicker("", selection: $date, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                if let coord = pinCoordinate {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pinned Location")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.red)
                            Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Connections Step

    private var connectionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Who was there?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                if viewModel.allConnections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No connections yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.allConnections) { connection in
                            let isSelected = selectedConnections.contains(connection.id)

                            Button {
                                if isSelected {
                                    selectedConnections.remove(connection.id)
                                } else {
                                    selectedConnections.insert(connection.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    ConnectionAvatarView(connection: connection, size: 40)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(connection.displayName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text("@\(connection.username)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isSelected ? .blue : Color(.tertiaryLabel))
                                        .symbolEffect(.bounce, value: isSelected)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }

                            Divider().padding(.leading, 68)
                        }
                    }
                }

                if !selectedConnections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(selectedConnections.count) people selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.allConnections.filter { selectedConnections.contains($0.id) }) { connection in
                                    HStack(spacing: 6) {
                                        ConnectionAvatarView(connection: connection, size: 24)
                                        Text(connection.username)
                                            .font(.caption.weight(.medium))

                                        Button {
                                            selectedConnections.remove(connection.id)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .contentMargins(.horizontal, 0)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func searchAddress() {
        guard !addressQuery.isEmpty else { return }
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = addressQuery

        let search = MKLocalSearch(request: request)
        Task {
            do {
                let response = try await search.start()
                searchResults = response.mapItems
            } catch {
                searchResults = []
            }
            isSearching = false
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        pinCoordinate = coord
        addressQuery = item.name ?? ""
        searchResults = []

        withAnimation(.spring(duration: 0.6)) {
            mapPosition = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        }
    }

    private func createMemory() {
        guard let coord = pinCoordinate else { return }

        let selectedPeople = viewModel.allConnections.filter { selectedConnections.contains($0.id) }
        var creators = ["Samantherr"]
        creators.append(contentsOf: selectedPeople.map(\.username))

        let pin = MemoryPin(
            coordinate: coord,
            title: title,
            date: date,
            intensity: 0.8
        )

        let memory = Memory(
            title: title,
            subtitle: subtitle,
            date: date,
            creators: creators,
            centerCoordinate: coord,
            spanDelta: 0.05,
            pins: [pin],
            connections: selectedPeople
        )

        viewModel.addMemory(memory)
        dismiss()
    }
}

struct ConnectionAvatarView: View {
    let connection: Connection
    let size: CGFloat

    private var color: Color {
        switch connection.avatarColor {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        }
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Text(String(connection.username.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}
