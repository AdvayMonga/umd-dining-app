import AuthenticationServices
import SwiftUI

@main
struct UMD_DiningApp: App {
    @State private var authManager = AuthManager.shared
    @State private var favoritesManager = FavoritesManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = true

    var body: some Scene {
        WindowGroup {
            if authManager.isSignedIn {
                ContentView()
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                    .environment(authManager)
                    .environment(favoritesManager)
                    .task {
                        await authManager.checkAppleCredentialState()
                        await authManager.refreshTokenIfNeeded()
                        await favoritesManager.syncFromServer()
                        await UserPreferences.shared.syncFromServer()
                    }
                    .onReceive(NotificationCenter.default.publisher(
                        for: ASAuthorizationAppleIDProvider.credentialRevokedNotification
                    )) { _ in
                        authManager.signOut()
                    }
            } else {
                SignInView()
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                    .environment(authManager)
            }
        }
    }
}
