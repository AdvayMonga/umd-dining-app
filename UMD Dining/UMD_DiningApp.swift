import AuthenticationServices
import SwiftData
import SwiftUI

@main
struct UMD_DiningApp: App {
    @State private var authManager = AuthManager.shared
    @State private var favoritesManager = FavoritesManager.shared
    @State private var trackerManager = NutritionTrackerManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("hasCompletedPalateSurvey") private var hasCompletedSurvey = false

    var body: some Scene {
        WindowGroup {
            if authManager.isSignedIn {
                if !hasCompletedSurvey {
                    OnboardingView {
                        hasCompletedSurvey = true
                    }
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                } else {
                    ContentView()
                        .preferredColorScheme(isDarkMode ? .dark : .light)
                        .environment(authManager)
                        .environment(favoritesManager)
                        .environment(trackerManager)
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
                }
            } else {
                SignInView()
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                    .environment(authManager)
            }
        }
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
    }
}
