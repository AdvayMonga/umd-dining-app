import Foundation

@Observable
class FavoritesManager {
    static let shared = FavoritesManager()

    var favoriteFoods: [String: String] {
        didSet { saveFoods() }
    }

    private let foodsKey = "favoriteFoods"

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: "favoriteFoods") as? [String: String]
        self.favoriteFoods = stored ?? [:]
    }

    func toggleFood(recNum: String, name: String) {
        if favoriteFoods[recNum] != nil {
            favoriteFoods.removeValue(forKey: recNum)
        } else {
            favoriteFoods[recNum] = name
        }
    }

    func isFavorite(recNum: String) -> Bool {
        favoriteFoods[recNum] != nil
    }

    private func saveFoods() {
        UserDefaults.standard.set(favoriteFoods, forKey: foodsKey)
    }
}
