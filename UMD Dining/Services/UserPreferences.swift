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
    var halal: Bool {
        didSet { saveLocally(); syncToServer() }
    }
    var allergens: Set<String> {
        didSet { saveLocally(); syncToServer() }
    }
    var cuisinePrefs: [String] {
        didSet { saveLocally(); syncToServer() }
    }
    var preferredDiningHalls: Set<String> {
        didSet { saveLocally(); syncToServer() }
    }

    private let vegetarianKey = "pref_vegetarian"
    private let veganKey = "pref_vegan"
    private let halalKey = "pref_halal"
    private let allergensKey = "pref_allergens"
    private let cuisinePrefsKey = "pref_cuisine_prefs"
    private let diningHallsKey = "pref_dining_halls"

    init() {
        self.vegetarian = UserDefaults.standard.bool(forKey: "pref_vegetarian")
        self.vegan = UserDefaults.standard.bool(forKey: "pref_vegan")
        self.halal = UserDefaults.standard.bool(forKey: "pref_halal")
        let stored = UserDefaults.standard.stringArray(forKey: "pref_allergens") ?? []
        self.allergens = Set(stored)
        self.cuisinePrefs = UserDefaults.standard.stringArray(forKey: "pref_cuisine_prefs") ?? []
        let storedHalls = UserDefaults.standard.stringArray(forKey: "pref_dining_halls") ?? []
        self.preferredDiningHalls = Set(storedHalls)
    }

    func shouldHide(item: MenuItem) -> Bool {
        if vegan && !item.dietaryIcons.contains("vegan") {
            return true
        }
        if vegetarian && !item.dietaryIcons.contains("vegetarian") {
            return true
        }
        if halal && !item.dietaryIcons.contains("HalalFriendly") {
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
        guard let userId = AuthManager.shared.userId else { return }
        do {
            let prefs = try await DiningAPIService.shared.fetchPreferences(userId: userId)
            vegetarian = prefs.vegetarian
            vegan = prefs.vegan
            allergens = Set(prefs.allergens)
            cuisinePrefs = prefs.cuisinePrefs
            preferredDiningHalls = Set(prefs.preferredDiningHalls)
        } catch {
            // Keep local values if API fails
        }
    }

    func clearAll() {
        vegetarian = false
        vegan = false
        halal = false
        allergens = []
        cuisinePrefs = []
        preferredDiningHalls = []
        UserDefaults.standard.removeObject(forKey: vegetarianKey)
        UserDefaults.standard.removeObject(forKey: veganKey)
        UserDefaults.standard.removeObject(forKey: halalKey)
        UserDefaults.standard.removeObject(forKey: allergensKey)
        UserDefaults.standard.removeObject(forKey: cuisinePrefsKey)
        UserDefaults.standard.removeObject(forKey: diningHallsKey)
    }

    private func saveLocally() {
        UserDefaults.standard.set(vegetarian, forKey: vegetarianKey)
        UserDefaults.standard.set(vegan, forKey: veganKey)
        UserDefaults.standard.set(halal, forKey: halalKey)
        UserDefaults.standard.set(Array(allergens), forKey: allergensKey)
        UserDefaults.standard.set(cuisinePrefs, forKey: cuisinePrefsKey)
        UserDefaults.standard.set(Array(preferredDiningHalls), forKey: diningHallsKey)
    }

    private func syncToServer() {
        guard let userId = AuthManager.shared.userId else { return }
        Task {
            try? await DiningAPIService.shared.updatePreferences(
                userId: userId,
                vegetarian: vegetarian,
                vegan: vegan,
                allergens: Array(allergens),
                cuisinePrefs: cuisinePrefs,
                preferredDiningHalls: Array(preferredDiningHalls)
            )
        }
    }
}
