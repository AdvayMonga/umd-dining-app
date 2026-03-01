import Foundation

@Observable
class UserPreferences {
    static let shared = UserPreferences()

    var vegetarian: Bool {
        didSet { save() }
    }
    var vegan: Bool {
        didSet { save() }
    }
    var allergens: Set<String> {
        didSet { save() }
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

    private func save() {
        UserDefaults.standard.set(vegetarian, forKey: vegetarianKey)
        UserDefaults.standard.set(vegan, forKey: veganKey)
        UserDefaults.standard.set(Array(allergens), forKey: allergensKey)
    }
}
