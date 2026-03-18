import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var authManager

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

                Text("Sign in to save your favorites")
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
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 60)
        }
    }
}
