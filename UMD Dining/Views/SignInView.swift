import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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

                    Text("Sign in to save your preferences")
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
                            isLoading = true
                            Task {
                                await authManager.handleSignIn(credential: credential)
                                isLoading = false
                            }
                        }
                    case .failure(let error):
                        errorMessage = "Sign in failed. Please try again."
                        print("Sign in failed: \(error.localizedDescription)")
                    }
                }
                .signInWithAppleButtonStyle(isDarkMode ? .white : .black)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 40)
                .disabled(isLoading)

                Button {
                    isLoading = true
                    Task {
                        await authManager.continueAsGuest()
                        isLoading = false
                    }
                } label: {
                    Text("Continue as Guest")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 40)
                .padding(.top, -24)
                .disabled(isLoading)

                Spacer()
                    .frame(height: 40)
            }

            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthManager.shared)
}
