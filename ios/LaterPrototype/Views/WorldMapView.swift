import SwiftUI
import CoreLocation
import MapboxMaps

struct WorldMapView: View {
    let viewModel: LaterViewModel
    @AppStorage(MapThemeOption.storageKey) private var mapThemeRaw: String = MapThemeOption.defaultTheme.rawValue
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 30, longitude: -20),
        zoom: 0.9,
        bearing: 0,
        pitch: 0
    )
    @State private var selectedMemoryID: UUID?
    @State private var showCreateMemory: Bool = false
    @State private var timelineHeight: CGFloat = 0

    private var location: LocationService { .shared }

    private var mapThemeStyle: MapStyle { MapThemeSelection.mapStyle(forRaw: mapThemeRaw) }

    init(viewModel: LaterViewModel) {
        self.viewModel = viewModel
        MapboxSetup.configureIfNeeded()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapLayer

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Button {
                            centerOnMyLocation()
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }

                        Button {
                            showCreateMemory = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }

                WaveformTimelineView(
                    memories: viewModel.memories,
                    onMemorySelected: { memory in
                        selectedMemoryID = memory.id
                        flyTo(
                            center: memory.centerCoordinate,
                            zoom: MapCameraMath.zoom(forSpanDelta: memory.spanDelta)
                        )
                    }
                )
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    timelineHeight = newHeight
                }
            }
        }
        .overlay {
            if viewModel.memories.isEmpty {
                MapEmptyState(onCreate: { showCreateMemory = true })
            }
        }
        .fullScreenCover(item: $selectedMemoryID) { memoryID in
            MemoryRoomView(memoryID: memoryID, viewModel: viewModel)
        }
        .sheet(isPresented: $showCreateMemory) {
            CreateMemoryView(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .onAppear {
            location.requestLocation()
        }
        .onChange(of: location.currentCoordinate?.latitude) { old, new in
            // First fix after granting permission: gently fly to the user.
            if old == nil, new != nil {
                centerOnMyLocation()
            }
        }
    }

    /// The themed Mapbox globe with every memory pinned on it. Falls back to
    /// a notice when the app was built without a Mapbox token.
    @ViewBuilder
    private var mapLayer: some View {
        if MapboxSetup.hasToken {
            Map(viewport: $viewport) {
                Puck2D()

                ForEvery(viewModel.memories) { memory in
                    MapViewAnnotation(coordinate: memory.centerCoordinate) {
                        Button {
                            selectedMemoryID = memory.id
                        } label: {
                            MemoryPinView(memory: memory)
                        }
                    }
                    .allowOverlap(true)
                    .allowZElevate(true)
                }
            }
            .mapStyle(mapThemeStyle)
            .additionalSafeAreaInsets(.bottom, timelineHeight)
            .ignoresSafeArea()
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                ContentUnavailableView {
                    Label("Map unavailable", systemImage: "key.slash")
                        .foregroundStyle(.white)
                } description: {
                    Text("Add your Mapbox public token and rebuild the app to load the globe.")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private func centerOnMyLocation() {
        location.requestLocation()
        guard let coordinate = location.currentCoordinate else { return }
        flyTo(center: coordinate, zoom: 12.2)
    }

    private func flyTo(center: CLLocationCoordinate2D, zoom: Double) {
        withViewportAnimation(.fly) {
            viewport = .camera(center: center, zoom: zoom, bearing: 0, pitch: 0)
        }
    }
}

struct MapEmptyState: View {
    let onCreate: () -> Void
    @State private var float: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 110, height: 110)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 44))
                    .foregroundStyle(.white)
                    .offset(y: float ? -4 : 4)
            }
            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)

            VStack(spacing: 8) {
                Text("Your map is empty")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Pin your first memory to a place in the world and watch your globe come to life.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                onCreate()
            } label: {
                Label("Create your first memory", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
            }
            .padding(.top, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.35))
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                float = true
            }
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct MemoryPinView: View {
    let memory: Memory
    @State private var isAnimating: Bool = false

    /// The pin's accent color — the owner's custom pick, or the classic orange.
    private var tint: Color {
        MemoryPinStyle.color(named: memory.pinStyle?.colorName)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.25))
                    .frame(width: 44, height: 44)
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
                    .opacity(isAnimating ? 0 : 0.6)

                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 32, height: 32)

                if let emoji = memory.pinStyle?.emoji, !emoji.isEmpty {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 26, height: 26)
                            .shadow(color: tint.opacity(0.6), radius: 8, x: 0, y: 0)
                        Text(emoji)
                            .font(.system(size: 14))
                    }
                    .overlay {
                        Circle().stroke(tint, lineWidth: 2)
                    }
                } else {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, tint],
                                center: .center,
                                startRadius: 0,
                                endRadius: 12
                            )
                        )
                        .frame(width: 18, height: 18)
                        .shadow(color: tint.opacity(0.6), radius: 8, x: 0, y: 0)
                }
            }

            Text(memory.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
