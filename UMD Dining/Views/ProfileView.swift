import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @State private var preferences = UserPreferences.shared
    @Environment(FavoritesManager.self) private var favorites
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var isUpgrading = false
    @State private var upgradeError: String?
    @State private var showSignOutConfirmation = false

    private let allergenOptions = [
        "Contains dairy",
        "Contains egg",
        "Contains gluten",
        "Contains soy"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                }

                Section("Taste Preferences") {
                    NavigationLink {
                        PalateSurveyView(onComplete: {})
                    } label: {
                        HStack {
                            Text("Cuisine Preferences")
                            Spacer()
                            if preferences.cuisinePrefs.isEmpty {
                                Text("Not set")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(preferences.cuisinePrefs.count) selected")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Dietary Preferences") {
                    Toggle("Vegetarian", isOn: $preferences.vegetarian)
                    Toggle("Vegan", isOn: $preferences.vegan)
                }

                Section("Allergens to Avoid") {
                    ForEach(allergenOptions, id: \.self) { allergen in
                        Toggle(allergen.replacingOccurrences(of: "Contains ", with: ""),
                               isOn: Binding(
                                get: { preferences.allergens.contains(allergen) },
                                set: { isOn in
                                    if isOn {
                                        preferences.allergens.insert(allergen)
                                    } else {
                                        preferences.allergens.remove(allergen)
                                    }
                                }
                               ))
                    }
                }

                Section("Favorites") {
                    if favorites.favoriteFoods.isEmpty {
                        Text("No favorite foods yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(favorites.favoriteFoods.sorted(by: { $0.value < $1.value }), id: \.key) { recNum, name in
                            NavigationLink(destination: NutritionDetailView(recNum: recNum, foodName: name)) {
                                Text(name)
                            }
                        }
                    }
                }

                if AuthManager.shared.isGuest {
                    Section("Account") {
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = []
                        } onCompletion: { result in
                            switch result {
                            case .success(let authorization):
                                if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                    isUpgrading = true
                                    Task {
                                        await AuthManager.shared.upgradeToApple(credential: credential)
                                        isUpgrading = false
                                    }
                                }
                            case .failure(let error):
                                upgradeError = "Sign in failed. Please try again."
                                print("Upgrade failed: \(error.localizedDescription)")
                            }
                        }
                        .frame(height: 44)
                        .disabled(isUpgrading)
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                    .confirmationDialog(
                        "Are you sure you want to sign out?",
                        isPresented: $showSignOutConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Sign Out & Delete Data", role: .destructive) {
                            AuthManager.shared.signOut()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Your favorites and preferences will be lost.")
                    }
                }
            }
            .navigationTitle("Profile")
            .overlay {
                if isUpgrading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { upgradeError != nil },
                set: { if !$0 { upgradeError = nil } }
            )) {
                Button("OK") { upgradeError = nil }
            } message: {
                Text(upgradeError ?? "")
            }
        }
    }
}

#Preview {
    ProfileView()
        .environment(FavoritesManager.shared)
}
