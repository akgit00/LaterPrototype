import SwiftUI
import MapKit

struct WorldMapView: View {
    let viewModel: LaterViewModel
    @State private var position: MapCameraPosition = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: -20),
        distance: 30000000,
        heading: 0,
        pitch: 0
    ))
    @State private var selectedMemoryID: UUID?
    @State private var showCreateMemory: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                ForEach(viewModel.memories) { memory in
                    Annotation(memory.title, coordinate: memory.centerCoordinate) {
                        Button {
                            selectedMemoryID = memory.id
                        } label: {
                            MemoryPinView(memory: memory)
                        }
                    }
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
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
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }

                WaveformTimelineView(
                    memories: viewModel.memories,
                    onMemorySelected: { memory in
                        selectedMemoryID = memory.id
                        withAnimation(.spring(duration: 0.6)) {
                            position = .region(MKCoordinateRegion(
                                center: memory.centerCoordinate,
                                span: MKCoordinateSpan(latitudeDelta: memory.spanDelta, longitudeDelta: memory.spanDelta)
                            ))
                        }
                    }
                )
            }
        }
        .fullScreenCover(item: $selectedMemoryID) { memoryID in
            MemoryRoomView(memoryID: memoryID, viewModel: viewModel)
        }
        .sheet(isPresented: $showCreateMemory) {
            CreateMemoryView(viewModel: viewModel)
                .presentationDetents([.large])
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct MemoryPinView: View {
    let memory: Memory
    @State private var isAnimating: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
                    .opacity(isAnimating ? 0 : 0.6)

                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 32, height: 32)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .orange],
                            center: .center,
                            startRadius: 0,
                            endRadius: 12
                        )
                    )
                    .frame(width: 18, height: 18)
                    .shadow(color: .orange.opacity(0.6), radius: 8, x: 0, y: 0)
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
