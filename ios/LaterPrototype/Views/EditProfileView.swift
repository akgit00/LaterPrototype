import SwiftUI
import PhotosUI

/// Sheet for editing the user's profile: avatar, display name, and bio.
struct EditProfileView: View {
    let profile: ProfileManager
    let fallbackInitial: String
    let authPicture: String?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var bio: String
    @State private var avatarURL: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false

    init(
        profile: ProfileManager,
        initialName: String,
        initialBio: String,
        fallbackInitial: String,
        authPicture: String?
    ) {
        self.profile = profile
        self.fallbackInitial = fallbackInitial
        self.authPicture = authPicture
        _name = State(initialValue: initialName)
        _bio = State(initialValue: initialBio)
        _avatarURL = State(initialValue: profile.avatarLocalURL)
    }

    private var resolvedAvatar: String? {
        avatarURL ?? authPicture
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        avatarView

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Text(isProcessingPhoto ? "Adding…" : "Change Photo")
                                .font(.subheadline.weight(.semibold))
                        }
                        .disabled(isProcessingPhoto)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Name") {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Bio") {
                    TextField("Add a short bio", text: $bio, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        profile.update(displayName: name, bio: bio, avatarLocalURL: avatarURL)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                isProcessingPhoto = true
                Task {
                    defer { isProcessingPhoto = false }
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let saved = MediaStore.saveImage(data) {
                        avatarURL = saved
                    }
                }
            }
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)

            if let avatar = resolvedAvatar, let url = URL(string: avatar) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Text(fallbackInitial)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 96, height: 96)
                .clipShape(.circle)
            } else {
                Text(fallbackInitial)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(.blue, in: .circle)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
        }
    }
}
