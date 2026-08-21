import SwiftUI
import UIKit

/// App-wide theme override chosen in Settings, persisted across launches.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    private var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applies this appearance to every window so sheets and full-screen
    /// covers follow it too (`preferredColorScheme` doesn't reach separate
    /// presentations).
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }

    /// Re-applies whatever the user last picked (called at launch).
    static func applyStored() {
        let raw = UserDefaults.standard.string(forKey: "appearance_preference")
            ?? AppearancePreference.system.rawValue
        (AppearancePreference(rawValue: raw) ?? .system).apply()
    }
}

/// Central hub for account, profile, privacy, appearance and notification
/// options — opened from the gear on the Profile tab.
struct SettingsView: View {
    let viewModel: LaterViewModel
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileManager.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance_preference") private var appearanceRawValue: String = AppearancePreference.system.rawValue
    @State private var showEditProfile = false
    @State private var showSignOutConfirm = false

    private static let defaultBio = "Collecting moments across time & space"

    private var push: PushNotificationService { .shared }

    /// The account's default name, derived from auth, used when no override is set.
    private var accountName: String {
        if let name = auth.user?.name, !name.isEmpty { return name }
        if let email = auth.user?.email, !email.isEmpty {
            return String(email.prefix(while: { $0 != "@" }))
        }
        return "You"
    }

    private var displayName: String {
        profile.displayNameOverride ?? accountName
    }

    /// Bridges the persisted raw value to the typed preference and applies
    /// the change to every window the moment it's picked.
    private var appearance: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRawValue) ?? .system },
            set: { newValue in
                appearanceRawValue = newValue.rawValue
                newValue.apply()
            }
        )
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountSettingsView(viewModel: viewModel)
                    } label: {
                        HStack(spacing: 12) {
                            settingsIcon("person.fill", .blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Account")
                                if let email = auth.user?.email, !email.isEmpty {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    Button {
                        showEditProfile = true
                    } label: {
                        HStack(spacing: 12) {
                            settingsIcon("pencil", .indigo)
                            Text("Edit Profile")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $bindableViewModel.readReceiptsEnabled) {
                        HStack(spacing: 12) {
                            settingsIcon("checkmark.message.fill", .green)
                            Text("Send Read Receipts")
                        }
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("When on, friends see \"Read\" under messages you've opened.")
                }

                Section {
                    Picker(selection: appearance) {
                        ForEach(AppearancePreference.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            settingsIcon("circle.lefthalf.filled", .purple)
                            Text("Theme")
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose how Later looks, or match your device setting.")
                }

                Section {
                    HStack(spacing: 12) {
                        settingsIcon("bell.badge.fill", .red)
                        Text("Push Notifications")
                        Spacer()
                        Text(notificationStatusText)
                            .foregroundStyle(.secondary)
                    }

                    if case .needsPermission = push.setupState {
                        Button("Enable Notifications") {
                            push.requestPermissionIfNeeded()
                        }
                    } else {
                        Button("Notification Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Sounds, banners and badges are managed in iOS Settings.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Text("Sign Out")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign out of Later?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    profile.clear()
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(
                    profile: profile,
                    initialName: profile.displayNameOverride ?? accountName,
                    initialBio: profile.bioOverride ?? Self.defaultBio,
                    fallbackInitial: String(displayName.prefix(1)).uppercased(),
                    authPicture: auth.user?.picture
                )
            }
        }
    }

    private var notificationStatusText: String {
        switch push.setupState {
        case .active: "On"
        case .denied: "Off"
        case .needsPermission: "Not set up"
        case .registering: "Setting up…"
        case .failed: "Issue"
        case .unknown: "—"
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// iOS-Settings-style rounded colored square with a white glyph.
    private func settingsIcon(_ systemName: String, _ tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7))
    }
}
