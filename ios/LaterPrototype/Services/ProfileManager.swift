import SwiftUI

/// Holds the user's editable profile (display name, bio, avatar) and persists
/// it in `UserDefaults`. Overrides are `nil` until the user customizes a field,
/// in which case the view falls back to the signed-in account's defaults.
@Observable
class ProfileManager {
    var displayNameOverride: String?
    var bioOverride: String?
    /// Holds either a local file URL (just-picked, pending upload) or, once
    /// synced, the remote Storage URL of the avatar.
    var avatarLocalURL: String?

    private var userID: String?

    private let nameKey = "profile_displayName"
    private let bioKey = "profile_bio"
    private let avatarKey = "profile_avatarURL"

    init() {
        let defaults = UserDefaults.standard
        displayNameOverride = defaults.string(forKey: nameKey)
        bioOverride = defaults.string(forKey: bioKey)
        avatarLocalURL = defaults.string(forKey: avatarKey)
    }

    /// Loads the signed-in user's saved profile from Supabase so customizations
    /// survive logout and reinstalls. Falls back to whatever is cached locally.
    func configure(userID: String) async {
        self.userID = userID
        guard let cloud = (try? await CloudMemoryService.fetchProfile(id: userID)) ?? nil else { return }
        if let name = cloud.display_name, !name.isEmpty { displayNameOverride = name }
        if let bio = cloud.bio, !bio.isEmpty { bioOverride = bio }
        if let avatar = cloud.avatar_url, !avatar.isEmpty { avatarLocalURL = avatar }
        persist()
    }

    /// Applies edited values, treating empty input as "use the default", then
    /// syncs them to Supabase (uploading a freshly-picked avatar if needed).
    func update(displayName: String, bio: String, avatarLocalURL: String?) {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        displayNameOverride = trimmedName.isEmpty ? nil : trimmedName

        let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        bioOverride = trimmedBio.isEmpty ? nil : trimmedBio

        // Replace the stored avatar, cleaning up the previous file if it changed.
        if let old = self.avatarLocalURL, old != avatarLocalURL {
            MediaStore.deleteFile(at: old)
        }
        self.avatarLocalURL = avatarLocalURL

        persist()
        Task { await syncToCloud() }
    }

    /// Uploads a local avatar (if any) and writes name/bio/avatar to Supabase.
    private func syncToCloud() async {
        guard let userID else { return }

        var avatarRemote = avatarLocalURL
        if let local = avatarLocalURL, let url = URL(string: local), url.isFileURL {
            if let uploaded = await CloudMemoryService.uploadAvatar(local, userID: userID) {
                avatarRemote = uploaded
                // Swap the local file path for the durable remote URL.
                MediaStore.deleteFile(at: local)
                avatarLocalURL = uploaded
                persist()
            }
        }

        await CloudMemoryService.updateProfileDetails(
            userID: userID,
            displayName: displayNameOverride,
            bio: bioOverride,
            avatarURL: avatarRemote
        )
    }

    /// Clears the locally-cached profile on sign-out. The cloud copy stays
    /// intact and is reloaded by `configure(userID:)` on the next sign-in.
    func clear() {
        if let avatar = avatarLocalURL {
            MediaStore.deleteFile(at: avatar)
        }
        userID = nil
        displayNameOverride = nil
        bioOverride = nil
        avatarLocalURL = nil
        persist()
    }

    private func persist() {
        let defaults = UserDefaults.standard
        setOrRemove(displayNameOverride, key: nameKey, in: defaults)
        setOrRemove(bioOverride, key: bioKey, in: defaults)
        setOrRemove(avatarLocalURL, key: avatarKey, in: defaults)
    }

    private func setOrRemove(_ value: String?, key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
