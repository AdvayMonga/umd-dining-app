import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @Binding var tabResetID: UUID
    @State private var preferences = UserPreferences.shared
    @Environment(FavoritesManager.self) private var favorites
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var isUpgrading = false
    @State private var upgradeError: String?
    @State private var showSignOutAlert = false
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    @State private var showCuisinePrefs = false
    @State private var foodsToShow = 10
    @State private var stationsToShow = 10
    @State private var scrollProxy: ScrollViewProxy?

    private let allergenOptions = [
        ("Contains dairy", "Dairy"),
        ("Contains egg", "Egg"),
        ("Contains fish", "Fish"),
        ("Contains gluten", "Gluten"),
        ("Contains shellfish", "Shellfish"),
        ("Contains sesame", "Sesame"),
        ("Contains soy", "Soy"),
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        Color.clear.frame(height: 0).id("profileTop")
                        // --- Account header (MOVED TO TOP) ---
                        if AuthManager.shared.isGuest {
                        sectionCard("Account") {
                            VStack(spacing: 8) {
                                Text("Sign in to save your preferences")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

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
                                .signInWithAppleButtonStyle(isDarkMode ? .black : .white)
                                .frame(height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isDarkMode ? Color.white.opacity(0.3) : Color.black.opacity(0.3), lineWidth: 1))
                                .disabled(isUpgrading)

                                Button {
                                    showDeleteAlert = true
                                } label: {
                                    Text("Delete Account")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(Color.red.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        accountHeader
                    }

                    // --- General ---
                    sectionCard("General") {
                        togglePill(
                            label: isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode",
                            icon: isDarkMode ? "sun.max.fill" : "moon.fill",
                            action: { isDarkMode.toggle() }
                        )
                    }

                    // --- Taste Preferences ---
                    sectionCard("Taste Preferences") {
                        filterPill("Cuisine Preferences", subtitle: preferences.cuisinePrefs.isEmpty ? "Not set" : "\(preferences.cuisinePrefs.count) selected") {
                            showCuisinePrefs = true
                        }
                    }

                    // --- Dietary Preferences ---
                    sectionCard("Dietary Preferences") {
                        selectablePill("Vegetarian", isOn: $preferences.vegetarian)
                        selectablePill("Vegan", isOn: $preferences.vegan)
                    }

                    // --- Allergens ---
                    sectionCard("Allergens to Avoid") {
                        ForEach(allergenOptions, id: \.0) { key, label in
                            selectablePill(label, isOn: Binding(
                                get: { preferences.allergens.contains(key) },
                                set: { on in
                                    if on { preferences.allergens.insert(key) }
                                    else { preferences.allergens.remove(key) }
                                }
                            ))
                        }
                    }

                    // --- Favorite Foods ---
                    sectionCard("Favorite Foods") {
                        if favorites.favoriteFoods.isEmpty {
                            NavigationLink(destination: SearchOverlay()) {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.primary)
                                    Text("Find Foods")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            let sorted = favorites.favoriteFoods.sorted(by: { $0.value < $1.value })
                            let visible = Array(sorted.prefix(foodsToShow))
                            ForEach(visible, id: \.key) { recNum, name in
                                NavigationLink(destination: NutritionDetailView(recNum: recNum, foodName: name, source: "profile_favorites")) {
                                    HStack {
                                        Text(name)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            if foodsToShow < sorted.count {
                                Button {
                                    foodsToShow += 20
                                } label: {
                                    Text("See More")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.umdRed)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                    }

                    // --- Favorite Stations ---
                    sectionCard("Favorite Stations") {
                        if favorites.favoriteStations.isEmpty {
                            NavigationLink(destination: SearchOverlay()) {
                                HStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.primary)
                                    Text("Find Stations")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        } else {
                            let sorted = favorites.favoriteStations.sorted()
                            let visible = Array(sorted.prefix(stationsToShow))
                            ForEach(visible, id: \.self) { station in
                                HStack {
                                    Text(station)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            }
                            if stationsToShow < sorted.count {
                                Button {
                                    stationsToShow += 20
                                } label: {
                                    Text("See More")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(Color.umdRed)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                    }

                    Spacer().frame(height: 40)
                }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .onAppear { scrollProxy = proxy }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .sheet(isPresented: $showCuisinePrefs) {
                NavigationStack {
                    PalateSurveyView(onComplete: {}, isOnboarding: false)
                }
            }
            .overlay {
                if isUpgrading {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.5)
                }
            }
            .overlay {
                if showSignOutAlert {
                    signOutOverlay
                }
            }
            .overlay {
                if showDeleteAlert {
                    deleteAccountOverlay
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
        .id(tabResetID)
    }

    // MARK: - Account Header

    private var accountHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(AuthManager.shared.isGuest ? "Guest User" : "Signed In")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !AuthManager.shared.isGuest {
                    Text("Apple Account")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Button {
                    showSignOutAlert = true
                } label: {
                    Text("Sign Out")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.umdRed)
                        .clipShape(Capsule())
                }
                Button {
                    showDeleteAlert = true
                } label: {
                    Text("Delete Account")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Sign Out Overlay (centered, hard to miss)

    private var signOutOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showSignOutAlert = false }

            VStack(spacing: 16) {
                Text("Sign Out?")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Your favorites and preferences will be lost.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showSignOutAlert = false
                    AuthManager.shared.signOut()
                } label: {
                    Text("Sign Out & Delete Data")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showSignOutAlert = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Delete Account Overlay

    private var deleteAccountOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showDeleteAlert = false }

            VStack(spacing: 16) {
                Text("Delete Account?")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("This will permanently delete your account and all your data. This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showDeleteAlert = false
                    isDeleting = true
                    Task {
                        do {
                            try await DiningAPIService.shared.deleteAccount()
                        } catch {
                            print("Delete account API error: \(error)")
                        }
                        AuthManager.shared.signOut()
                        isDeleting = false
                    }
                } label: {
                    Text("Delete Account")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showDeleteAlert = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Reusable Components

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func togglePill(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func selectablePill(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.umdRed)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isOn.wrappedValue ? Color.umdRed.opacity(0.12) : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn.wrappedValue ? Color.umdRed : Color(.systemGray4), lineWidth: isOn.wrappedValue ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func filterPill(_ label: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileView(tabResetID: .constant(UUID()))
        .environment(FavoritesManager.shared)
}
