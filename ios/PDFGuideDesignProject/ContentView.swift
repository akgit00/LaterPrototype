import SwiftUI

struct ContentView: View {
    @State private var viewModel = LaterViewModel()
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Explore", systemImage: "globe", value: 0) {
                WorldMapView(viewModel: viewModel)
            }

            Tab("Capsules", systemImage: "envelope.badge.shield.half.filled", value: 1) {
                TimeCapsuleView()
            }

            Tab("Profile", systemImage: "person.crop.circle", value: 2) {
                ProfileView()
            }
        }
        .tint(.white)
    }
}
