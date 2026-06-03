import SwiftUI

/// Holds the user's editable profile (display name, bio, avatar) and persists
/// it in `UserDefaults`. Overrides are `nil` until the user customizes a field,
/// in which case the view falls back to the signed-in account's defaults.
@Observable
class ProfileManager {
    var displayNameOverride: String?
    var bioOverride: String?
    var avatarLocalURL: String?

    private let nameKey = "profile_displayName"
    private let bioKey = "profile_bio"
    private let avatarKey = "profile_avatarURL"

    init() {
        let defaults = UserDefaults.standard
        displayNameOverride = defaults.string(forKey: nameKey)
        bioOverride = defaults.string(forKey: bioKey)
        avatarLocalURL = defaults.string(forKey: avatarKey)
    }

    /// Applies edited values, treating empty input as "use the default".
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
    }

    /// Clears all profile customizations (used on sign-out).
    func clear() {
        if let avatar = avatarLocalURL {
            MediaStore.deleteFile(at: avatar)
        }
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
