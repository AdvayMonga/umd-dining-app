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
    @State private var showDietaryPrefs = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // Header — directly on background, no card
                    VStack(spacing: 10) {
                        Text(AuthManager.shared.isGuest
                             ? "Hi, there!"
                             : "Hi, \(AuthManager.shared.displayName?.components(separatedBy: " ").first ?? "there")!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)

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
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(width: 220, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 19))
                            .disabled(isUpgrading)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "apple.logo")
                                    .font(.caption)
                                Text("Signed in with Apple")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(.systemGray3), lineWidth: 1.5))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.bottom, 28)

                    // PREFERENCES section
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("PREFERENCES")

                        // Cuisine Preferences
                        itemCard {
                            HStack(spacing: 14) {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.umdRed)
                                    .frame(width: 24)
                                Text("Cuisine Preferences")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.systemGray3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } action: {
                            showCuisinePrefs = true
                        }

                        // Allergens & Dietary Needs
                        itemCard {
                            HStack(spacing: 14) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.umdRed)
                                    .frame(width: 24)
                                Text("Allergens & Dietary Needs")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.systemGray3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } action: {
                            showDietaryPrefs = true
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 36)

                    // APP SETTINGS section
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("APP SETTINGS")

                        itemCard {
                            HStack(spacing: 14) {
                                Image(systemName: isDarkMode ? "sun.max.fill" : "moon.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.umdRed)
                                    .frame(width: 24)
                                Text("Dark Mode")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(isDarkMode ? "On" : "Off")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } action: {
                            isDarkMode.toggle()
                        }

                        itemCard {
                            HStack(spacing: 14) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.umdRed)
                                    .frame(width: 24)
                                Text("Privacy Policy")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.systemGray3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } action: {
                            if let url = URL(string: "https://api.umddining.com/privacy") {
                                UIApplication.shared.open(url)
                            }
                        }

                        itemCard {
                            HStack(spacing: 14) {
                                Image(systemName: "message")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.umdRed)
                                    .frame(width: 24)
                                Text("App Feedback")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.systemGray3))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                        } action: {
                            if let url = URL(string: "https://forms.gle/53RrYDkmZjmf72Py9") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    Spacer().frame(height: 24)

                    if !AuthManager.shared.isGuest {
                        Button { showSignOutAlert = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.body.weight(.bold))
                                Text("Logout")
                                    .font(.body.weight(.bold))
                            }
                            .foregroundStyle(Color.umdRed)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.umdRed, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }

                    Spacer().frame(height: 16)

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("Version \(version) (\(build))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer().frame(height: 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .sheet(isPresented: $showCuisinePrefs) {
                NavigationStack {
                    PalateSurveyView(onComplete: {}, isOnboarding: false)
                }
            }
            .sheet(isPresented: $showDietaryPrefs) {
                DietaryPrefsSheet(preferences: preferences)
            }
            .overlay {
                if isUpgrading {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.5)
                }
            }
            .overlay { if showSignOutAlert { signOutOverlay } }
            .overlay { if showDeleteAlert { deleteAccountOverlay } }
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

    // MARK: - Item Card

    private func itemCard<Content: View>(
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.bottom, 2)
    }

    // MARK: - Sign Out Overlay

    private var signOutOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showSignOutAlert = false }
            VStack(spacing: 16) {
                Text("Sign Out?")
                    .font(.title3)
                    .fontWeight(.bold)
                Text(AuthManager.shared.isGuest
                     ? "Your favorites and preferences will be lost."
                     : "Your data will be saved to your account. Sign back in anytime to restore it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showSignOutAlert = false
                    AuthManager.shared.signOut()
                } label: {
                    Text("Sign Out")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.umdRed)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Button { showSignOutAlert = false } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
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
                        do { try await DiningAPIService.shared.deleteAccount() }
                        catch { print("Delete account API error: \(error)") }
                        FavoritesManager.shared.clearAll()
                        UserPreferences.shared.clearAll()
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
                Button { showDeleteAlert = false } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Dietary Prefs Sheet

private struct DietaryPrefsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var preferences: UserPreferences

    private let allergenOptions: [(label: String, key: String)] = [
        ("Dairy",     "Contains dairy"),
        ("Egg",       "Contains egg"),
        ("Fish",      "Contains fish"),
        ("Gluten",    "Contains gluten"),
        ("Nuts",      "Contains nuts"),
        ("Shellfish", "Contains Shellfish"),
        ("Sesame",    "Contains sesame"),
        ("Soy",       "Contains soy"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    filterSection(title: "Dietary Preferences", icon: "leaf.fill", iconColor: Color.umdRed) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            dietaryPill("Vegetarian",     isOn: $preferences.vegetarian)
                            dietaryPill("Vegan",          isOn: $preferences.vegan)
                            dietaryPill("Halal Friendly", isOn: $preferences.halal)
                            dietaryPill("Gluten Free",    isOn: $preferences.glutenFree)
                            dietaryPill("Dairy Free",     isOn: $preferences.dairyFree)
                        }
                    }

                    Divider()

                    filterSection(
                        title: "Allergens to Avoid",
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color(red: 180/255, green: 83/255, blue: 9/255),
                        subtitle: "Items containing these ingredients will be hidden from your menu."
                    ) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(allergenOptions, id: \.key) { option in
                                allergenPill(option.label, key: option.key)
                            }
                        }
                    }

                    // Safety advisory
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color(.systemGray3))
                            .font(.system(size: 18))
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dining Safety")
                                .font(.inter(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Maryland Dining does not guarantee allergen-free preparation. Cross-contamination may occur. Consult dining staff if you have a severe allergy.")
                                .font(.inter(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.umdBorder, lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Allergens & Dietary Needs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func filterSection<Content: View>(
        title: String, icon: String, iconColor: Color,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.inter(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.top, -6)
            }
            content()
        }
    }

    private func dietaryPill(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack {
                Text(label)
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? Color.umdRed : .primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.umdRed)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(isOn.wrappedValue ? Color.umdRed.opacity(0.08) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isOn.wrappedValue ? Color.umdRed : Color.umdBorder,
                        lineWidth: isOn.wrappedValue ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn.wrappedValue)
    }

    private func allergenPill(_ label: String, key: String) -> some View {
        let isOn = preferences.allergens.contains(key)
        let color = Color(red: 180/255, green: 83/255, blue: 9/255)
        return Button {
            if isOn { preferences.allergens.remove(key) }
            else { preferences.allergens.insert(key) }
        } label: {
            HStack {
                Text(label)
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(isOn ? color : .primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(isOn ? color.opacity(0.08) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isOn ? color : Color.umdBorder, lineWidth: isOn ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

#Preview {
    ProfileView(tabResetID: .constant(UUID()))
        .environment(FavoritesManager.shared)
}
