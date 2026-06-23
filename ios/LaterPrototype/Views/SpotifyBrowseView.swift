import SwiftUI

/// Lets the signed-in user connect Spotify and pick one of their playlists (or
/// search public ones) to attach to a memory. On selection the playlist is
/// imported with its real cover art and tracks.
struct SpotifyBrowseView: View {
    let memoryID: UUID
    let viewModel: LaterViewModel
    /// Called after a playlist is successfully attached so parent sheets close.
    var onAttached: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var isConnected: Bool = SpotifyService.shared.isConnected
    @State private var isConnecting: Bool = false
    @State private var isLoading: Bool = false
    @State private var playlists: [SpotifyPlaylistRef] = []
    @State private var searchText: String = ""
    @State private var importingID: String?
    @State private var errorMessage: String?

    private let green = Color(red: 0.11, green: 0.84, blue: 0.38)

    var body: some View {
        NavigationStack {
            Group {
                if !SpotifyConfig.isConfigured {
                    notConfiguredState
                } else if !isConnected {
                    connectState
                } else {
                    playlistList
                }
            }
            .navigationTitle("Spotify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isConnected {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Disconnect") {
                            SpotifyService.shared.disconnect()
                            isConnected = false
                            playlists = []
                        }
                    }
                }
            }
        }
    }

    // MARK: - States

    private var notConfiguredState: some View {
        ContentUnavailableView {
            Label("Spotify Not Set Up", systemImage: "music.note.list")
        } description: {
            Text("Add your Spotify Client ID in SpotifyConfig to enable connecting your account.")
        }
    }

    private var connectState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 52))
                .foregroundStyle(green)
            Text("Connect your Spotify")
                .font(.title3.weight(.semibold))
            Text("Sign in to browse your playlists and add them to this memory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                connect()
            } label: {
                HStack {
                    if isConnecting { ProgressView().tint(.white) }
                    Text(isConnecting ? "Connecting..." : "Connect Spotify")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(green, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(isConnecting)
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private var playlistList: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            ForEach(playlists) { playlist in
                Button {
                    attach(playlist)
                } label: {
                    playlistRow(playlist)
                }
                .disabled(importingID != nil)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search Spotify playlists")
        .onSubmit(of: .search) { runSearch() }
        .task { if playlists.isEmpty { await loadMine() } }
        .refreshable { await loadMine() }
    }

    private func playlistRow(_ playlist: SpotifyPlaylistRef) -> some View {
        HStack(spacing: 12) {
            Color(.tertiarySystemFill)
                .frame(width: 52, height: 52)
                .overlay {
                    if let cover = playlist.coverURL, let url = URL(string: cover) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "music.note")
                                .foregroundStyle(.secondary)
                        }
                        .allowsHitTesting(false)
                    } else {
                        Image(systemName: "music.note").foregroundStyle(.secondary)
                    }
                }
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(playlist.trackTotal) tracks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if importingID == playlist.id {
                ProgressView()
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(green)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func connect() {
        errorMessage = nil
        isConnecting = true
        Task {
            do {
                try await SpotifyService.shared.connect()
                isConnected = true
                await loadMine()
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func loadMine() async {
        errorMessage = nil
        isLoading = true
        do {
            playlists = try await SpotifyService.shared.myPlaylists()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func runSearch() {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            Task { await loadMine() }
            return
        }
        errorMessage = nil
        isLoading = true
        Task {
            do {
                playlists = try await SpotifyService.shared.searchPlaylists(term)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func attach(_ playlist: SpotifyPlaylistRef) {
        importingID = playlist.id
        errorMessage = nil
        Task {
            do {
                let attachment = try await SpotifyService.shared.importPlaylist(playlist)
                viewModel.setPlaylist(for: memoryID, playlist: attachment)
                importingID = nil
                onAttached()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                importingID = nil
            }
        }
    }
}
