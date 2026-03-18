import Foundation

@MainActor
@Observable
class UserPreferences {
    static let shared = UserPreferences()

    var vegetarian: Bool {
        didSet { saveLocally(); syncToServer() }
    }
    var vegan: Bool {
        didSet { saveLocally(); syncToServer() }
    }
    var allergens: Set<String> {
        didSet { saveLocally(); syncToServer() }
    }

    private let vegetarianKey = "pref_vegetarian"
    private let veganKey = "pref_vegan"
    private let allergensKey = "pref_allergens"

    init() {
        self.vegetarian = UserDefaults.standard.bool(forKey: "pref_vegetarian")
        self.vegan = UserDefaults.standard.bool(forKey: "pref_vegan")
        let stored = UserDefaults.standard.stringArray(forKey: "pref_allergens") ?? []
        self.allergens = Set(stored)
    }

    func shouldHide(item: MenuItem) -> Bool {
        if vegan && !item.dietaryIcons.contains("vegan") {
            return true
        }
        if vegetarian && !item.dietaryIcons.contains("vegetarian") {
            return true
        }
        for allergen in allergens {
            if item.dietaryIcons.contains(allergen) {
                return true
            }
        }
        return false
    }

    /// Fetch preferences from the API (only for signed-in, non-guest users)
    func syncFromServer() async {
        guard let userId = AuthManager.shared.userId, !AuthManager.shared.isGuest else { return }
        do {
            let prefs = try await DiningAPIService.shared.fetchPreferences(userId: userId)
            vegetarian = prefs.vegetarian
            vegan = prefs.vegan
            allergens = Set(prefs.allergens)
        } catch {
            // Keep local values if API fails
        }
    }

    private func saveLocally() {
        UserDefaults.standard.set(vegetarian, forKey: vegetarianKey)
        UserDefaults.standard.set(vegan, forKey: veganKey)
        UserDefaults.standard.set(Array(allergens), forKey: allergensKey)
    }

    private func syncToServer() {
        guard let userId = AuthManager.shared.userId, !AuthManager.shared.isGuest else { return }
        Task {
            try? await DiningAPIService.shared.updatePreferences(
                userId: userId,
                vegetarian: vegetarian,
                vegan: vegan,
                allergens: Array(allergens)
            )
        }
    }
}
