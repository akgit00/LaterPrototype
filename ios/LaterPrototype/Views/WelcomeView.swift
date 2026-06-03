import SwiftUI
import AuthenticationServices

struct WelcomeView: View {
    @Environment(AuthManager.self) private var auth

    @State private var appear = false
    @State private var showEmailAuth = false

    var body: some View {
        @Bindable var auth = auth

        ZStack {
            backdrop

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
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
                            .shadow(color: .purple.opacity(0.5), radius: 24, y: 8)

                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .scaleEffect(appear ? 1 : 0.6)
                    .opacity(appear ? 1 : 0)

                    VStack(spacing: 8) {
                        Text("Later")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Collect moments across\ntime & space")
                            .font(.headline.weight(.regular))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
                }

                Spacer()

                VStack(spacing: 12) {
                    if auth.isSigningIn {
                        ProgressView()
                            .tint(.white)
                            .padding(.bottom, 4)
                    }

                    SignInWithAppleButton(.continue) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            Task { await auth.signInWithApple(authorization) }
                        case .failure(let error):
                            if (error as? ASAuthorizationError)?.code != .canceled {
                                auth.errorMessage = error.localizedDescription
                                auth.showError = true
                            }
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .clipShape(.rect(cornerRadius: 16))
                    .disabled(auth.isSigningIn)

                    Button {
                        auth.notice = nil
                        showEmailAuth = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .font(.title3)
                            Text("Continue with Email")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.12), in: .rect(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .disabled(auth.isSigningIn)

                    Text("By continuing you agree to keep your memories safe.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 20)
            }
        }
        .alert("Sign-in error", isPresented: $auth.showError) {
            Button("OK") { }
        } message: {
            Text(auth.errorMessage)
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView()
                .environment(auth)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                appear = true
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.10, green: 0.06, blue: 0.20),
                    Color(red: 0.02, green: 0.02, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.purple.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: -120, y: -220)

            Circle()
                .fill(Color.blue.opacity(0.30))
                .frame(width: 280, height: 280)
                .blur(radius: 110)
                .offset(x: 140, y: 260)
        }
        .ignoresSafeArea()
    }
}
