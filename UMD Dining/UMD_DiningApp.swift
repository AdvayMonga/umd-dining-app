import SwiftUI

@main
struct UMD_DiningApp: App {
    @State private var authManager = AuthManager.shared
    @State private var favoritesManager = FavoritesManager.shared

    var body: some Scene {
        WindowGroup {
            if authManager.isSignedIn {
                ContentView()
                    .environment(authManager)
                    .environment(favoritesManager)
                    .task {
                        await authManager.refreshTokenIfNeeded()
                        await favoritesManager.syncFromServer()
                        await UserPreferences.shared.syncFromServer()
                    }
            } else {
                SignInView()
                    .environment(authManager)
            }
        }
    }
}
