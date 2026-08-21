import SwiftUI
import UIKit

/// Read-only account details: the email used to sign up, username and
/// display name, plus a quick copy action for the email.
struct AccountSettingsView: View {
    let viewModel: LaterViewModel
    @Environment(AuthManager.self) private var auth
    @Environment(ProfileManager.self) private var profile
    @State private var didCopyEmail = false

    private var email: String? {
        guard let email = auth.user?.email, !email.isEmpty else { return nil }
        return email
    }

    /// The account's default name, derived from auth, used when no override is set.
    private var accountName: String {
        if let name = auth.user?.name, !name.isEmpty { return name }
        if let email {
            return String(email.prefix(while: { $0 != "@" }))
        }
        return "You"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Email") {
                    Text(email ?? "—")
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }

                if let username = viewModel.currentUsername {
                    LabeledContent("Username", value: "@\(username)")
                }

                LabeledContent("Display Name", value: profile.displayNameOverride ?? accountName)
            } header: {
                Text("Signed in as")
            } footer: {
                Text("This is the email you signed up with. Changing your sign-in email isn't available yet — it's coming in a future update.")
            }

            Section {
                Button {
                    guard let email else { return }
                    UIPasteboard.general.string = email
                    withAnimation { didCopyEmail = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { didCopyEmail = false }
                    }
                } label: {
                    Label(
                        didCopyEmail ? "Copied!" : "Copy Email",
                        systemImage: didCopyEmail ? "checkmark" : "doc.on.doc"
                    )
                }
                .disabled(email == nil)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}
