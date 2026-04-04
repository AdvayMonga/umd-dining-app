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
    var cuisinePrefs: [String] {
        didSet { saveLocally(); syncToServer() }
    }

    private let vegetarianKey = "pref_vegetarian"
    private let veganKey = "pref_vegan"
    private let allergensKey = "pref_allergens"
    private let cuisinePrefsKey = "pref_cuisine_prefs"

    init() {
        self.vegetarian = UserDefaults.standard.bool(forKey: "pref_vegetarian")
        self.vegan = UserDefaults.standard.bool(forKey: "pref_vegan")
        let stored = UserDefaults.standard.stringArray(forKey: "pref_allergens") ?? []
        self.allergens = Set(stored)
        self.cuisinePrefs = UserDefaults.standard.stringArray(forKey: "pref_cuisine_prefs") ?? []
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
            cuisinePrefs = prefs.cuisinePrefs
        } catch {
            // Keep local values if API fails
        }
    }

    func clearAll() {
        vegetarian = false
        vegan = false
        allergens = []
        cuisinePrefs = []
        UserDefaults.standard.removeObject(forKey: vegetarianKey)
        UserDefaults.standard.removeObject(forKey: veganKey)
        UserDefaults.standard.removeObject(forKey: allergensKey)
        UserDefaults.standard.removeObject(forKey: cuisinePrefsKey)
    }

    private func saveLocally() {
        UserDefaults.standard.set(vegetarian, forKey: vegetarianKey)
        UserDefaults.standard.set(vegan, forKey: veganKey)
        UserDefaults.standard.set(Array(allergens), forKey: allergensKey)
        UserDefaults.standard.set(cuisinePrefs, forKey: cuisinePrefsKey)
    }

    private func syncToServer() {
        guard let userId = AuthManager.shared.userId, !AuthManager.shared.isGuest else { return }
        Task {
            try? await DiningAPIService.shared.updatePreferences(
                userId: userId,
                vegetarian: vegetarian,
                vegan: vegan,
                allergens: Array(allergens),
                cuisinePrefs: cuisinePrefs
            )
        }
    }
}
