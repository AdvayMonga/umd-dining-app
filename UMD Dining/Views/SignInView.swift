import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.umdRed)

                Text("UMD Dining")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.umdRed)

                Text("Sign in to save your favorites across devices")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                        Task {
                            await authManager.handleSignIn(credential: credential)
                        }
                    }
                case .failure(let error):
                    print("Sign in failed: \(error.localizedDescription)")
                }
            }
            .signInWithAppleButtonStyle(isDarkMode ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 40)

            Button {
                Task { await authManager.continueAsGuest() }
            } label: {
                Text("Continue as Guest")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 40)
            .padding(.top, -24)

            Spacer()
                .frame(height: 40)
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthManager.shared)
}
