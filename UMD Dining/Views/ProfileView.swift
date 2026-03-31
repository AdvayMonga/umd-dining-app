import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @State private var preferences = UserPreferences.shared
    @Environment(FavoritesManager.self) private var favorites
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var isUpgrading = false
    @State private var upgradeError: String?

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
                        ForEach(Array(favorites.favoriteFoods.values).sorted(), id: \.self) { name in
                            Text(name)
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
                        AuthManager.shared.signOut()
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
