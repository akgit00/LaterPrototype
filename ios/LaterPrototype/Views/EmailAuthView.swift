import SwiftUI

/// Email-based authentication: sign in / sign up with a password, or get a
/// one-time login code by email (magic-link style).
struct EmailAuthView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case password
        case code
    }

    enum Step {
        case enterEmail
        case enterCode
    }

    @State private var mode: Mode = .code
    @State private var step: Step = .enterEmail
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @FocusState private var focused: Field?

    enum Field {
        case email, password, code
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isEmailValid: Bool {
        trimmedEmail.contains("@") && trimmedEmail.contains(".")
    }

    private var canSubmitPassword: Bool {
        isEmailValid && password.count >= 6 && !auth.isSigningIn
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.12).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        header

                        if mode == .password {
                            passwordForm
                        } else {
                            codeForm
                        }

                        if let notice = auth.notice {
                            Text(notice)
                                .font(.footnote)
                                .foregroundStyle(.green.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbarBackground(Color(red: 0.05, green: 0.05, blue: 0.12), for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .alert("Sign-in error", isPresented: bindingShowError) {
            Button("OK") { }
        } message: {
            Text(auth.errorMessage)
        }
        .onChange(of: auth.user != nil) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    private var bindingShowError: Binding<Bool> {
        Binding(get: { auth.showError }, set: { auth.showError = $0 })
    }

    private var navTitle: String {
        switch mode {
        case .password: return isSignUp ? "Create account" : "Sign in"
        case .code: return "Email me a code"
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: mode == .code ? "envelope.badge.fill" : "lock.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.1), in: .circle)

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var headerSubtitle: String {
        switch mode {
        case .password:
            return isSignUp ? "Create an account with your email." : "Welcome back. Sign in to continue."
        case .code:
            return step == .enterEmail
                ? "We'll email you a 6-digit code to sign in — no password needed."
                : "Enter the 6-digit code we sent to \(trimmedEmail)."
        }
    }

    // MARK: - Password form

    private var passwordForm: some View {
        VStack(spacing: 16) {
            field(
                "Email",
                text: $email,
                field: .email,
                keyboard: .emailAddress,
                content: .username
            )

            field(
                "Password",
                text: $password,
                field: .password,
                isSecure: true,
                content: isSignUp ? .newPassword : .password
            )

            Button {
                auth.notice = nil
                Task {
                    if isSignUp {
                        await auth.signUpWithEmail(email: trimmedEmail, password: password)
                    } else {
                        await auth.signInWithEmail(email: trimmedEmail, password: password)
                    }
                }
            } label: {
                primaryLabel(isSignUp ? "Create account" : "Sign in")
            }
            .disabled(!canSubmitPassword)
            .opacity(canSubmitPassword ? 1 : 0.5)

            Button {
                withAnimation { isSignUp.toggle(); auth.notice = nil }
            } label: {
                Text(isSignUp ? "Already have an account? Sign in" : "Don't have an account? Create one")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }

            divider

            Button {
                withAnimation { mode = .code; step = .enterEmail; auth.notice = nil }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill")
                    Text("Email me a code instead")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 14))
            }
        }
    }

    // MARK: - Code form

    private var codeForm: some View {
        VStack(spacing: 16) {
            if step == .enterEmail {
                field(
                    "Email",
                    text: $email,
                    field: .email,
                    keyboard: .emailAddress,
                    content: .username
                )

                Button {
                    auth.notice = nil
                    Task {
                        let sent = await auth.sendEmailCode(email: trimmedEmail)
                        if sent {
                            withAnimation { step = .enterCode }
                            focused = .code
                        }
                    }
                } label: {
                    primaryLabel("Send code")
                }
                .disabled(!isEmailValid || auth.isSigningIn)
                .opacity(isEmailValid && !auth.isSigningIn ? 1 : 0.5)
            } else {
                field(
                    "6-digit code",
                    text: $code,
                    field: .code,
                    keyboard: .numberPad,
                    content: .oneTimeCode
                )

                Button {
                    Task { await auth.verifyEmailCode(email: trimmedEmail, code: code.trimmingCharacters(in: .whitespaces)) }
                } label: {
                    primaryLabel("Verify & sign in")
                }
                .disabled(code.count < 6 || auth.isSigningIn)
                .opacity(code.count >= 6 && !auth.isSigningIn ? 1 : 0.5)

                Button {
                    auth.notice = nil
                    Task { _ = await auth.sendEmailCode(email: trimmedEmail) }
                } label: {
                    Text("Resend code")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            divider

            Button {
                withAnimation { mode = .password; step = .enterEmail; auth.notice = nil }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text("Use a password instead")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 14))
            }
        }
    }

    // MARK: - Reusable pieces

    private func field(
        _ title: String,
        text: Binding<String>,
        field: Field,
        keyboard: UIKeyboardType = .default,
        isSecure: Bool = false,
        content: UITextContentType? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))

            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .focused($focused, equals: field)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(content)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        ZStack {
            if auth.isSigningIn {
                ProgressView().tint(.black)
            } else {
                Text(title).font(.headline)
            }
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(.white, in: .rect(cornerRadius: 16))
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            Text("or").font(.caption).foregroundStyle(.white.opacity(0.4))
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}
