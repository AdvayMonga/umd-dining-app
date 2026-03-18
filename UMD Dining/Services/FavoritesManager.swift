import Foundation

@MainActor
@Observable
class FavoritesManager {
    static let shared = FavoritesManager()

    var favoriteFoods: [String: String] {
        didSet { saveFoodsLocally() }
    }

    private let foodsKey = "favoriteFoods"

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: "favoriteFoods") as? [String: String]
        self.favoriteFoods = stored ?? [:]
    }

    func toggleFood(recNum: String, name: String) {
        if favoriteFoods[recNum] != nil {
            favoriteFoods.removeValue(forKey: recNum)
            syncRemove(recNum: recNum)
        } else {
            favoriteFoods[recNum] = name
            syncAdd(recNum: recNum, name: name)
        }
    }

    func isFavorite(recNum: String) -> Bool {
        favoriteFoods[recNum] != nil
    }

    /// Fetch favorites from the API and update local cache
    func syncFromServer() async {
        guard let userId = AuthManager.shared.userId else { return }
        do {
            let serverFavs = try await DiningAPIService.shared.fetchFavorites(userId: userId)
            var merged: [String: String] = [:]
            for fav in serverFavs {
                merged[fav.recNum] = fav.name
            }
            favoriteFoods = merged
        } catch {
            // Keep local cache if API fails
        }
    }

    private func saveFoodsLocally() {
        UserDefaults.standard.set(favoriteFoods, forKey: foodsKey)
    }

    private func syncAdd(recNum: String, name: String) {
        guard let userId = AuthManager.shared.userId else { return }
        Task {
            try? await DiningAPIService.shared.addFavorite(userId: userId, recNum: recNum, name: name)
        }
    }

    private func syncRemove(recNum: String) {
        guard let userId = AuthManager.shared.userId else { return }
        Task {
            try? await DiningAPIService.shared.removeFavorite(userId: userId, recNum: recNum)
        }
    }
}
