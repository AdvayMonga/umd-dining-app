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
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasCheckedCredential = false
    @State private var selectedHallId: String? = nil

    var body: some Scene {
        WindowGroup {
            if authManager.isSignedIn {
                if !hasCompletedSurvey {
                    OnboardingView {
                        hasCompletedSurvey = true
                        UserDefaults.standard.set(false, forKey: "hasCompletedTutorial")
                    }
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                } else if let hallId = selectedHallId {
                    ContentView(initialHallId: hallId)
                        .preferredColorScheme(isDarkMode ? .dark : .light)
                        .environment(authManager)
                        .environment(favoritesManager)
                        .environment(trackerManager)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.04, anchor: .center)),
                            removal: .opacity
                        ))
                        .task {
                            await favoritesManager.syncFromServer()
                            await UserPreferences.shared.syncFromServer()
                        }
                        .onChange(of: scenePhase) {
                            if scenePhase == .background {
                                withAnimation(.easeInOut(duration: 0.3)) { selectedHallId = nil }
                            }
                            if scenePhase == .active && !hasCheckedCredential {
                                hasCheckedCredential = true
                                Task {
                                    await authManager.checkAppleCredentialState()
                                    await authManager.refreshTokenIfNeeded()
                                }
                            }
                        }
                } else {
                    DiningHallPickerView(
                        userName: authManager.displayName ?? "",
                        selectedHallId: nil,
                        onSelect: { id in
                            withAnimation(.easeInOut(duration: 0.35)) { selectedHallId = id }
                        }
                    )
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                    .transition(.opacity)
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
