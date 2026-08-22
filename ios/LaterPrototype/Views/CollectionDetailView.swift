import SwiftUI
import CoreLocation
import MapboxMaps
import UniformTypeIdentifiers

/// One line of the collection's spiderweb: either the chronological thread
/// or a nearest-neighbor strand.
private struct WebSegment: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
}

private enum CollectionViewMode {
    case web
    case wrapped
}

/// A whole collection at once: every member memory pinned on the globe and
/// interlocked into one zoomable spiderweb, with an alternate Wrapped stats
/// story a toggle away. Custom collections can be renamed, shared as a deep
/// link, reordered by dragging strip cards, and narrowed by month or year.
struct CollectionDetailView: View {
    let viewModel: LaterViewModel

    private let display: CollectionDisplay
    private let stats: WrappedStats
    private let tint: Color

    @Environment(\.dismiss) private var dismiss
    @AppStorage(MapThemeOption.storageKey) private var mapThemeRaw: String = MapThemeOption.defaultTheme.rawValue

    @State private var mode: CollectionViewMode
    @State private var viewport: Viewport
    @State private var openedMemoryID: UUID?
    @State private var focusedMemoryID: UUID?
    @State private var stripHeight: CGFloat = 0

    /// The member memories in their display order — mutated live while the
    /// user drags strip cards around, then committed to the collection.
    @State private var orderedMemories: [Memory]
    @State private var threadSegments: [WebSegment]
    @State private var webSegments: [WebSegment]
    @State private var draggedID: UUID?

    /// Date-range narrowing: a year, optionally tightened to one month.
    @State private var filterYear: Int?
    @State private var filterMonth: Int?

    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""

    init(display: CollectionDisplay, viewModel: LaterViewModel) {
        self.display = display
        self.viewModel = viewModel
        self.stats = WrappedStats.compute(memories: display.memories, allMemories: viewModel.memories)
        self.tint = MemoryPinStyle.color(named: display.colorName)

        let coordinates = display.memories.map { $0.centerCoordinate }
        self._threadSegments = State(initialValue: coordinates.count >= 2
            ? [WebSegment(id: "thread", coordinates: coordinates)]
            : [])
        self._webSegments = State(initialValue: Self.buildWebSegments(for: display.memories))
        self._orderedMemories = State(initialValue: display.memories)

        self._mode = State(initialValue: display.opensInWrapped ? .wrapped : .web)
        self._viewport = State(initialValue: Self.fittingViewport(for: display.memories))
        MapboxSetup.configureIfNeeded()
    }

    // MARK: - Live collection state

    /// Name/emoji read live from the view model so a rename shows instantly.
    private var liveName: String {
        guard let id = display.customID else { return display.title }
        return viewModel.lifeCollections.first(where: { $0.id == id })?.name ?? display.title
    }

    private var liveEmoji: String {
        guard let id = display.customID else { return display.emoji }
        return viewModel.lifeCollections.first(where: { $0.id == id })?.emoji ?? display.emoji
    }

    private var shareMessage: String? {
        guard let id = display.customID,
              let collection = viewModel.lifeCollections.first(where: { $0.id == id }) else { return nil }
        return CollectionShareCodec.shareMessage(for: collection)
    }

    /// The memories currently on screen: the full arrangement, or the slice
    /// inside the active month/year filter.
    private var displayedMemories: [Memory] {
        guard let year = filterYear else { return orderedMemories }
        let calendar = Calendar.current
        return orderedMemories.filter { memory in
            let components = calendar.dateComponents([.year, .month], from: memory.date)
            guard components.year == year else { return false }
            if let month = filterMonth, components.month != month { return false }
            return true
        }
    }

    /// Dragging is offered on custom collections with the full list showing
    /// (reordering a filtered slice would be ambiguous).
    private var isReorderable: Bool {
        display.customID != nil && filterYear == nil && orderedMemories.count > 1
    }

    private var filterKey: String {
        "\(filterYear ?? -1):\(filterMonth ?? -1)"
    }

    var body: some View {
        ZStack {
            if mode == .web {
                webLayer
                    .transition(.opacity)
            } else {
                CollectionWrappedView(display: display, stats: stats) {
                    withAnimation(.easeInOut(duration: 0.35)) { mode = .web }
                }
                .transition(.opacity)
            }

            header
        }
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(item: $openedMemoryID) { memoryID in
            MemoryRoomView(memoryID: memoryID, viewModel: viewModel)
        }
        .onChange(of: displayedMemories.map(\.id)) { _, _ in
            rebuildSegments()
        }
        .onChange(of: filterYear) { _, _ in
            filterMonth = nil
        }
        .onChange(of: filterKey) { _, _ in
            withViewportAnimation(.fly) {
                viewport = Self.fittingViewport(for: displayedMemories)
            }
        }
        .onDisappear {
            draggedID = nil
            commitOrderIfChanged()
        }
        .alert("Rename Collection", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let id = display.customID {
                    viewModel.renameLifeCollection(id: id, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("\(liveEmoji) \(liveName)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if display.isInProgressYear {
                            Text("EARLY PEEK")
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.8)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.yellow, in: Capsule())
                        }
                    }
                    Text(filterYear == nil
                         ? "\(stats.memoryCount) \(stats.memoryCount == 1 ? "memory" : "memories") · \(stats.placeCount) \(stats.placeCount == 1 ? "place" : "places")"
                         : "\(displayedMemories.count) of \(orderedMemories.count) memories shown")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                modeToggle

                if display.customID != nil {
                    collectionMenu
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            if mode == .web && !orderedMemories.isEmpty {
                filterBar
            }

            Spacer()
        }
    }

    /// Share (deep link) and rename, for custom collections only.
    private var collectionMenu: some View {
        Menu {
            if let message = shareMessage {
                ShareLink(item: message) {
                    Label("Share Collection", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                renameText = liveName
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "character.cursor.ibeam")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            toggleSegment(icon: "point.3.connected.trianglepath.dotted", isOn: mode == .web) {
                withAnimation(.easeInOut(duration: 0.35)) { mode = .web }
            }
            toggleSegment(icon: "sparkles", isOn: mode == .wrapped) {
                withAnimation(.easeInOut(duration: 0.35)) { mode = .wrapped }
            }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func toggleSegment(icon: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(isOn ? .black : .white)
                .frame(width: 40, height: 32)
                .background {
                    if isOn {
                        Capsule().fill(.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date-range filter

    private var availableYears: [Int] {
        let calendar = Calendar.current
        return Set(orderedMemories.map { calendar.component(.year, from: $0.date) })
            .sorted(by: >)
    }

    private func availableMonths(in year: Int) -> [Int] {
        let calendar = Calendar.current
        return Set(
            orderedMemories
                .filter { calendar.component(.year, from: $0.date) == year }
                .map { calendar.component(.month, from: $0.date) }
        ).sorted()
    }

    private func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        guard (1...12).contains(month) else { return "" }
        return symbols[month - 1]
    }

    /// Month/year chips that narrow the web to a slice of time.
    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Year", selection: $filterYear) {
                    Text("All Time").tag(Int?.none)
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(Int?.some(year))
                    }
                }
            } label: {
                filterChip(text: filterYear.map(String.init) ?? "All Time", isActive: filterYear != nil)
            }

            if let year = filterYear {
                Menu {
                    Picker("Month", selection: $filterMonth) {
                        Text("Any Month").tag(Int?.none)
                        ForEach(availableMonths(in: year), id: \.self) { month in
                            Text(monthName(month)).tag(Int?.some(month))
                        }
                    }
                } label: {
                    filterChip(text: filterMonth.map(monthName) ?? "Any Month", isActive: filterMonth != nil)
                }
            }

            if filterYear != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filterYear = nil
                        filterMonth = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func filterChip(text: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar")
                .font(.caption2.weight(.bold))
            Text(text)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isActive ? .black : .white)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.ultraThinMaterial),
            in: Capsule()
        )
    }

    // MARK: - Web (map) layer

    @ViewBuilder
    private var webLayer: some View {
        if MapboxSetup.hasToken {
            ZStack(alignment: .bottom) {
                map

                if orderedMemories.isEmpty {
                    emptyOverlay
                } else if displayedMemories.isEmpty {
                    filteredEmptyNotice
                } else {
                    memoryStrip
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { newHeight in
                            stripHeight = newHeight
                        }
                }
            }
        } else {
            ContentUnavailableView {
                Label("Map unavailable", systemImage: "key.slash")
                    .foregroundStyle(.white)
            } description: {
                Text("Add your Mapbox public token and rebuild the app to load the web.")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var map: some View {
        Map(viewport: $viewport) {
            PolylineAnnotationGroup(webSegments, id: \.id) { segment in
                PolylineAnnotation(id: "web-\(segment.id)", lineCoordinates: segment.coordinates)
                    .lineColor(StyleColor(UIColor(tint)))
                    .lineWidth(1.3)
                    .lineOpacity(0.5)
            }

            PolylineAnnotationGroup(threadSegments, id: \.id) { segment in
                PolylineAnnotation(id: "thread-\(segment.id)", lineCoordinates: segment.coordinates)
                    .lineColor(StyleColor(UIColor.white))
                    .lineWidth(2.4)
                    .lineOpacity(0.85)
            }

            ForEvery(displayedMemories) { memory in
                MapViewAnnotation(coordinate: memory.centerCoordinate) {
                    Button {
                        openedMemoryID = memory.id
                    } label: {
                        CollectionWebPinView(
                            memory: memory,
                            tint: tint,
                            isFocused: focusedMemoryID == memory.id
                        )
                    }
                    .buttonStyle(.plain)
                }
                .allowOverlap(true)
                .allowZElevate(true)
            }
        }
        .mapStyle(MapThemeSelection.mapStyle(forRaw: mapThemeRaw))
        .additionalSafeAreaInsets(.bottom, stripHeight)
        .ignoresSafeArea()
    }

    private var emptyOverlay: some View {
        VStack(spacing: 8) {
            Text("No memories in here yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text(display.customID != nil
                 ? "Long-press this collection on the Collections tab and choose Edit to add memories."
                 : "Memories you make this year will weave themselves in automatically.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }

    /// Shown when the month/year filter matches nothing.
    private var filteredEmptyNotice: some View {
        VStack(spacing: 6) {
            Text("Nothing in this range")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Try a different month or year, or clear the filter.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 40)
    }

    /// Horizontally scrollable member memories. Tapping a card flies the web
    /// to that pin; tapping the focused card opens the memory room. On custom
    /// collections, holding and dragging a card rearranges the order — the
    /// thread on the map re-weaves live.
    private var memoryStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isReorderable {
                Label("Hold & drag cards to reorder", systemImage: "hand.draw")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.horizontal, 20)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(displayedMemories) { memory in
                        if isReorderable {
                            stripCard(memory)
                                .opacity(draggedID == memory.id ? 0.35 : 1)
                                .onDrag {
                                    draggedID = memory.id
                                    return NSItemProvider(object: memory.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: StripReorderDelegate(
                                    itemID: memory.id,
                                    orderedMemories: $orderedMemories,
                                    draggedID: $draggedID,
                                    onCommit: { commitOrderIfChanged() }
                                ))
                        } else {
                            stripCard(memory)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 16)
            .onDrop(of: [.text], delegate: StripDropCatchAll(
                draggedID: $draggedID,
                onCommit: { commitOrderIfChanged() }
            ))
        }
        .padding(.bottom, 8)
    }

    private func stripCard(_ memory: Memory) -> some View {
        let isFocused = focusedMemoryID == memory.id
        return Button {
            if isFocused {
                openedMemoryID = memory.id
            } else {
                focusedMemoryID = memory.id
                flyTo(memory)
            }
        } label: {
            HStack(spacing: 10) {
                Color(.darkGray)
                    .frame(width: 42, height: 42)
                    .overlay {
                        MediaImageView(urlString: memory.photoURLs.first)
                            .allowsHitTesting(false)
                    }
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(memory.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(memory.date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }

                if isFocused {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                } else if isReorderable {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 190, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isFocused ? tint : .white.opacity(0.12), lineWidth: isFocused ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func flyTo(_ memory: Memory) {
        withViewportAnimation(.fly) {
            viewport = .camera(
                center: memory.centerCoordinate,
                zoom: MapCameraMath.zoom(forSpanDelta: max(memory.spanDelta, 0.05)),
                bearing: 0,
                pitch: 0
            )
        }
    }

    // MARK: - Ordering

    /// Persists the dragged arrangement onto the collection (local store +
    /// cloud). No-ops for year wraps and unchanged orders.
    private func commitOrderIfChanged() {
        guard let id = display.customID else { return }
        viewModel.reorderLifeCollection(id: id, visibleIDs: orderedMemories.map(\.id))
    }

    // MARK: - Web geometry

    /// Recomputes the thread and strands for the memories on screen (order
    /// or filter changed).
    private func rebuildSegments() {
        let members = displayedMemories
        let coordinates = members.map { $0.centerCoordinate }
        threadSegments = coordinates.count >= 2
            ? [WebSegment(id: "thread", coordinates: coordinates)]
            : []
        webSegments = Self.buildWebSegments(for: members)
    }

    /// Connects every memory to its two nearest neighbors (skipping pairs the
    /// chronological thread already covers), producing the interlocking web.
    private static func buildWebSegments(for memories: [Memory]) -> [WebSegment] {
        guard memories.count >= 3 else { return [] }
        var taken = Set<String>()
        for index in 1..<memories.count {
            taken.insert(pairKey(memories[index - 1].id, memories[index].id))
        }

        var segments: [WebSegment] = []
        for (index, memory) in memories.enumerated() {
            let neighbors = memories.enumerated()
                .filter { $0.offset != index }
                .map { candidate in
                    (
                        memory: candidate.element,
                        distance: WrappedStats.distanceKm(memory.centerCoordinate, candidate.element.centerCoordinate)
                    )
                }
                .sorted { $0.distance < $1.distance }
                .prefix(2)

            for neighbor in neighbors {
                let key = pairKey(memory.id, neighbor.memory.id)
                guard !taken.contains(key) else { continue }
                taken.insert(key)
                segments.append(
                    WebSegment(id: key, coordinates: [memory.centerCoordinate, neighbor.memory.centerCoordinate])
                )
            }
        }
        return segments
    }

    private static func pairKey(_ a: UUID, _ b: UUID) -> String {
        [a.uuidString, b.uuidString].sorted().joined(separator: "~")
    }

    /// A camera that frames every pin with breathing room.
    private static func fittingViewport(for memories: [Memory]) -> Viewport {
        let coordinates = memories.map { $0.centerCoordinate }
        guard let first = coordinates.first else {
            return .camera(
                center: CLLocationCoordinate2D(latitude: 30, longitude: -20),
                zoom: 0.9,
                bearing: 0,
                pitch: 0
            )
        }
        guard coordinates.count > 1 else {
            let span = max(memories.first?.spanDelta ?? 0.5, 0.1)
            return .camera(center: first, zoom: MapCameraMath.zoom(forSpanDelta: span), bearing: 0, pitch: 0)
        }

        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return .camera(center: first, zoom: 2, bearing: 0, pitch: 0)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latSpan = maxLat - minLat
        let lonSpan = (maxLon - minLon) * cos(center.latitude * .pi / 180)
        let span = max(max(latSpan, lonSpan) * 1.6, 0.08)
        return .camera(center: center, zoom: MapCameraMath.zoom(forSpanDelta: span), bearing: 0, pitch: 0)
    }
}

// MARK: - Drag-to-reorder plumbing

/// Live-reorders the strip while a card drags across its neighbors, then
/// commits the arrangement on drop.
private struct StripReorderDelegate: DropDelegate {
    let itemID: UUID
    @Binding var orderedMemories: [Memory]
    @Binding var draggedID: UUID?
    let onCommit: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedID, dragged != itemID,
              let from = orderedMemories.firstIndex(where: { $0.id == dragged }),
              let to = orderedMemories.firstIndex(where: { $0.id == itemID }) else { return }
        withAnimation(.spring(duration: 0.3)) {
            orderedMemories.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        onCommit()
        return true
    }
}

/// Catches drops that land between cards (or past the last one) so the new
/// order still commits and the dragged card un-fades.
private struct StripDropCatchAll: DropDelegate {
    @Binding var draggedID: UUID?
    let onCommit: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedID != nil else { return false }
        draggedID = nil
        onCommit()
        return true
    }
}

// MARK: - Web pin

/// A compact node on the collection web: the memory's newest photo in a
/// glowing ring, or its pin emoji/color when no photo exists.
private struct CollectionWebPinView: View {
    let memory: Memory
    let tint: Color
    let isFocused: Bool

    private var pinTint: Color {
        MemoryPinStyle.color(named: memory.pinStyle?.colorName)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.35))
                    .frame(width: 40, height: 40)

                if let photo = memory.photoURLs.first, !photo.isEmpty {
                    Color(.darkGray)
                        .frame(width: 30, height: 30)
                        .overlay {
                            MediaImageView(urlString: photo)
                                .allowsHitTesting(false)
                        }
                        .clipShape(Circle())
                        .overlay {
                            Circle().strokeBorder(.white, lineWidth: 1.5)
                        }
                } else if let emoji = memory.pinStyle?.emoji, !emoji.isEmpty {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 26, height: 26)
                        Text(emoji)
                            .font(.system(size: 13))
                    }
                    .overlay {
                        Circle().strokeBorder(pinTint, lineWidth: 1.5)
                    }
                } else {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, pinTint],
                                center: .center,
                                startRadius: 0,
                                endRadius: 11
                            )
                        )
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1)
                        }
                }
            }
            .shadow(color: tint.opacity(0.8), radius: 7, x: 0, y: 0)
            .scaleEffect(isFocused ? 1.25 : 1.0)
            .animation(.spring(duration: 0.4), value: isFocused)

            if isFocused {
                Text(memory.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
    }
}
