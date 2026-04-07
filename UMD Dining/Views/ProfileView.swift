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
    @State private var scrollProxy: ScrollViewProxy?

    private let allergenOptions = [
        ("Contains dairy", "Dairy"),
        ("Contains egg", "Egg"),
        ("Contains fish", "Fish"),
        ("Contains gluten", "Gluten"),
        ("Contains nuts", "Nuts"),
        ("Contains Shellfish", "Shellfish"),
        ("Contains sesame", "Sesame"),
        ("Contains soy", "Soy"),
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        Color.clear.frame(height: 0).id("profileTop")
                        // --- Food Preferences ---
                        sectionCard("Food Preferences") {
                            filterPill("Cuisine Preferences", subtitle: preferences.cuisinePrefs.isEmpty ? "Not set" : "\(preferences.cuisinePrefs.count) selected") {
                                showCuisinePrefs = true
                            }

                            selectablePill("Vegetarian", isOn: $preferences.vegetarian)
                            selectablePill("Vegan", isOn: $preferences.vegan)
                            selectablePill("Halal", isOn: $preferences.halal)

                            Text("Preferred Dining Halls")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, 4)

                            ForEach([("19", "Yahentamitsi"), ("51", "251 North"), ("16", "South Campus Diner")], id: \.0) { hallId, hallName in
                                selectablePill(hallName, isOn: Binding(
                                    get: { preferences.preferredDiningHalls.contains(hallId) },
                                    set: { on in
                                        if on { preferences.preferredDiningHalls.insert(hallId) }
                                        else { preferences.preferredDiningHalls.remove(hallId) }
                                    }
                                ))
                            }

                            Text("Allergens to Avoid")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, 4)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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
                        }

                        // --- Favorites ---
                        NavigationLink(destination: FavoritesView()) {
                            HStack {
                                Text("Favorites")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "heart")
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

                        // --- General ---
                        sectionCard("General") {
                            contactCard

                            togglePill(
                                label: isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode",
                                icon: isDarkMode ? "sun.max.fill" : "moon.fill",
                                action: { isDarkMode.toggle() }
                            )
                            togglePill(
                                label: "Send Feedback",
                                icon: "envelope",
                                action: {
                                    if let url = URL(string: "https://forms.gle/53RrYDkmZjmf72Py9") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            )
                            togglePill(
                                label: "Privacy Policy",
                                icon: "hand.raised",
                                action: {
                                    if let url = URL(string: "https://api.umddining.com/privacy") {
                                        UIApplication.shared.open(url)
                                    }
                                }
                            )
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

    // MARK: - Contact Card

    private var contactCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(AuthManager.shared.isGuest
                              ? Color.gray.opacity(0.3)
                              : Color.umdRed.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: AuthManager.shared.isGuest ? "person.fill" : "person.crop.circle.fill")
                        .font(.system(size: AuthManager.shared.isGuest ? 24 : 28))
                        .foregroundStyle(AuthManager.shared.isGuest ? .secondary : Color.umdRed)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if AuthManager.shared.isGuest {
                        Text("Guest User")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Sign in to save your data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(AuthManager.shared.displayName ?? "Apple User")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Apple Account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !AuthManager.shared.isGuest {
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
            }

            if AuthManager.shared.isGuest {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
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
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))
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
                        UserDefaults.standard.set(false, forKey: "hasCompletedPalateSurvey")
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
