import Foundation

@MainActor
@Observable
class FavoritesManager {
    static let shared = FavoritesManager()

    var favoriteFoods: [String: String] {
        didSet { saveFoodsLocally() }
    }

    var favoriteStations: Set<String> {
        didSet { saveStationsLocally() }
    }

    private let foodsKey = "favoriteFoods"
    private let stationsKey = "favoriteStations"

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: "favoriteFoods") as? [String: String]
        self.favoriteFoods = stored ?? [:]
        let storedStations = UserDefaults.standard.stringArray(forKey: "favoriteStations") ?? []
        self.favoriteStations = Set(storedStations)
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

    func toggleStation(name: String) {
        if favoriteStations.contains(name) {
            favoriteStations.remove(name)
            syncRemoveStation(name: name)
        } else {
            favoriteStations.insert(name)
            syncAddStation(name: name)
        }
    }

    func isFavoriteStation(_ name: String) -> Bool {
        favoriteStations.contains(name)
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
        do {
            let serverStations = try await DiningAPIService.shared.fetchStationFavorites(userId: userId)
            favoriteStations = Set(serverStations.map(\.stationName))
        } catch {
            // Keep local cache if API fails
        }
    }

    func clearAll() {
        favoriteFoods = [:]
        favoriteStations = []
        UserDefaults.standard.removeObject(forKey: foodsKey)
        UserDefaults.standard.removeObject(forKey: stationsKey)
    }

    private func saveFoodsLocally() {
        UserDefaults.standard.set(favoriteFoods, forKey: foodsKey)
    }

    private func saveStationsLocally() {
        UserDefaults.standard.set(Array(favoriteStations), forKey: stationsKey)
    }

    private func syncAddStation(name: String) {
        guard let userId = AuthManager.shared.userId else { return }
        Task {
            try? await DiningAPIService.shared.addStationFavorite(userId: userId, stationName: name)
        }
    }

    private func syncRemoveStation(name: String) {
        guard let userId = AuthManager.shared.userId else { return }
        Task {
            try? await DiningAPIService.shared.removeStationFavorite(userId: userId, stationName: name)
        }
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
