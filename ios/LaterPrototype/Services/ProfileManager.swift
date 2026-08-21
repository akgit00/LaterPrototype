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
    /// Community map styles the user bookmarked from pasted links, shown as
    /// one-tap cards in every style picker.
    var savedMapStyles: [SavedMapStyle] = []

    private var userID: String?

    private let nameKey = "profile_displayName"
    private let bioKey = "profile_bio"
    private let avatarKey = "profile_avatarURL"
    private let savedStylesKey = "profile_savedMapStyles"

    init() {
        let defaults = UserDefaults.standard
        displayNameOverride = defaults.string(forKey: nameKey)
        bioOverride = defaults.string(forKey: bioKey)
        avatarLocalURL = defaults.string(forKey: avatarKey)
        if let data = defaults.data(forKey: savedStylesKey),
           let styles = try? JSONDecoder().decode([SavedMapStyle].self, from: data) {
            savedMapStyles = styles
        }
    }

    /// Loads the signed-in user's saved profile from Supabase so customizations
    /// survive logout and reinstalls. Falls back to whatever is cached locally.
    func configure(userID: String) async {
        self.userID = userID

        // Restore the saved map theme with its own query so a failure on
        // either side never blocks the other.
        if let theme = await CloudMemoryService.fetchMapTheme(userID: userID), !theme.isEmpty {
            UserDefaults.standard.set(theme, forKey: MapThemeOption.storageKey)
        }

        // Restore bookmarked community styles the same way, merging so styles
        // saved on this device before the first sync are never lost.
        if let cloudStyles = await CloudMemoryService.fetchSavedMapStyles(userID: userID), !cloudStyles.isEmpty {
            mergeSavedStyles(cloud: cloudStyles)
        } else if !savedMapStyles.isEmpty {
            syncSavedStylesToCloud()
        }

        guard let cloud = (try? await CloudMemoryService.fetchProfile(id: userID)) ?? nil else { return }
        if let name = cloud.display_name, !name.isEmpty { displayNameOverride = name }
        if let bio = cloud.bio, !bio.isEmpty { bioOverride = bio }
        if let avatar = cloud.avatar_url, !avatar.isEmpty { avatarLocalURL = avatar }
        persist()
    }

    /// Saves the user's app-wide map theme locally and to their cloud profile
    /// so the pick survives reinstalls and follows them across devices.
    func saveMapTheme(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: MapThemeOption.storageKey)
        guard let userID else { return }
        Task { await CloudMemoryService.updateMapTheme(userID: userID, raw: raw) }
    }

    /// True when the style is already in the user's saved collection.
    func isStyleSaved(_ raw: String) -> Bool {
        savedMapStyles.contains { $0.raw == raw }
    }

    /// Bookmarks a community style (or renames an existing bookmark) and
    /// syncs the collection to the user's cloud profile.
    func saveStyle(raw: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? MapThemeSelection.suggestedSaveName(forRaw: raw) : trimmed
        if let index = savedMapStyles.firstIndex(where: { $0.raw == raw }) {
            savedMapStyles[index].name = finalName
        } else {
            savedMapStyles.append(SavedMapStyle(
                name: finalName,
                raw: raw,
                themeType: SavedStyleThemeType.guess(from: finalName)
            ))
        }
        persistAndSyncSavedStyles()
    }

    /// Folder names in use, in the order they first appear in the library.
    var savedStyleFolders: [String] {
        var seen = Set<String>()
        var folders: [String] = []
        for style in savedMapStyles {
            if let folder = style.folder, !folder.isEmpty, seen.insert(folder).inserted {
                folders.append(folder)
            }
        }
        return folders
    }

    /// Files a style under a folder (nil removes it from its folder). Folders
    /// exist implicitly — they live as long as one style uses them.
    func setFolder(_ folder: String?, forStyleRaw raw: String) {
        guard let index = savedMapStyles.firstIndex(where: { $0.raw == raw }) else { return }
        let trimmed = folder?.trimmingCharacters(in: .whitespacesAndNewlines)
        savedMapStyles[index].folder = (trimmed?.isEmpty ?? true) ? nil : trimmed
        persistAndSyncSavedStyles()
    }

    /// Overrides the automatic look bucket for a style.
    func setThemeType(_ type: SavedStyleThemeType?, forStyleRaw raw: String) {
        guard let index = savedMapStyles.firstIndex(where: { $0.raw == raw }) else { return }
        savedMapStyles[index].themeType = type
        persistAndSyncSavedStyles()
    }

    /// Drops a style from the saved collection. The style itself keeps
    /// working anywhere it's still applied.
    func removeSavedStyle(raw: String) {
        savedMapStyles.removeAll { $0.raw == raw }
        persistAndSyncSavedStyles()
    }

    /// Cloud copy wins on order; anything saved locally but missing from the
    /// cloud is appended and pushed back up.
    private func mergeSavedStyles(cloud: [SavedMapStyle]) {
        var merged = cloud
        for style in savedMapStyles where !merged.contains(where: { $0.raw == style.raw }) {
            merged.append(style)
        }
        let cloudNeedsUpdate = merged != cloud
        savedMapStyles = merged
        persistSavedStyles()
        if cloudNeedsUpdate { syncSavedStylesToCloud() }
    }

    private func persistAndSyncSavedStyles() {
        persistSavedStyles()
        syncSavedStylesToCloud()
    }

    private func persistSavedStyles() {
        if let data = try? JSONEncoder().encode(savedMapStyles) {
            UserDefaults.standard.set(data, forKey: savedStylesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: savedStylesKey)
        }
    }

    private func syncSavedStylesToCloud() {
        guard let userID else { return }
        let styles = savedMapStyles
        Task { await CloudMemoryService.updateSavedMapStyles(userID: userID, styles: styles) }
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
        savedMapStyles = []
        UserDefaults.standard.removeObject(forKey: savedStylesKey)
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
