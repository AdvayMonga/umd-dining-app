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

    private(set) var foodFavoriteOrder: [String] {
        didSet { UserDefaults.standard.set(foodFavoriteOrder, forKey: foodOrderKey) }
    }

    private(set) var stationFavoriteOrder: [String] {
        didSet { UserDefaults.standard.set(stationFavoriteOrder, forKey: stationOrderKey) }
    }

    private let foodsKey = "favoriteFoods"
    private let stationsKey = "favoriteStations"
    private let foodOrderKey = "favoriteFoodOrder"
    private let stationOrderKey = "favoriteStationOrder"

    var sortedFoods: [(recNum: String, name: String)] {
        var result: [(String, String)] = []
        for recNum in foodFavoriteOrder {
            if let name = favoriteFoods[recNum] {
                result.append((recNum, name))
            }
        }
        // Include any foods not yet in the order array (backwards compat)
        for (recNum, name) in favoriteFoods where !foodFavoriteOrder.contains(recNum) {
            result.append((recNum, name))
        }
        return result
    }

    var sortedStations: [String] {
        var result: [String] = []
        for station in stationFavoriteOrder where favoriteStations.contains(station) {
            result.append(station)
        }
        // Include any stations not yet in the order array
        for station in favoriteStations where !stationFavoriteOrder.contains(station) {
            result.append(station)
        }
        return result
    }

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: "favoriteFoods") as? [String: String]
        self.favoriteFoods = stored ?? [:]
        let storedStations = UserDefaults.standard.stringArray(forKey: "favoriteStations") ?? []
        self.favoriteStations = Set(storedStations)
        self.foodFavoriteOrder = UserDefaults.standard.stringArray(forKey: "favoriteFoodOrder") ?? []
        self.stationFavoriteOrder = UserDefaults.standard.stringArray(forKey: "favoriteStationOrder") ?? []
    }

    func toggleFood(recNum: String, name: String) {
        if favoriteFoods[recNum] != nil {
            favoriteFoods.removeValue(forKey: recNum)
            foodFavoriteOrder.removeAll { $0 == recNum }
            syncRemove(recNum: recNum)
        } else {
            favoriteFoods[recNum] = name
            foodFavoriteOrder.insert(recNum, at: 0)
            syncAdd(recNum: recNum, name: name)
        }
    }

    func isFavorite(recNum: String) -> Bool {
        favoriteFoods[recNum] != nil
    }

    func toggleStation(name: String) {
        if favoriteStations.contains(name) {
            favoriteStations.remove(name)
            stationFavoriteOrder.removeAll { $0 == name }
            syncRemoveStation(name: name)
        } else {
            favoriteStations.insert(name)
            stationFavoriteOrder.insert(name, at: 0)
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
            var newOrder: [String] = []
            for fav in serverFavs {
                merged[fav.recNum] = fav.name
                newOrder.append(fav.recNum)
            }
            favoriteFoods = merged
            // Preserve local order for known items, append new ones at front
            var updatedOrder: [String] = []
            for recNum in foodFavoriteOrder where merged[recNum] != nil {
                updatedOrder.append(recNum)
            }
            for recNum in newOrder where !updatedOrder.contains(recNum) {
                updatedOrder.insert(recNum, at: 0)
            }
            foodFavoriteOrder = updatedOrder
        } catch {
            // Keep local cache if API fails
        }
        do {
            let serverStations = try await DiningAPIService.shared.fetchStationFavorites(userId: userId)
            let stationNames = Set(serverStations.map(\.stationName))
            favoriteStations = stationNames
            var updatedOrder: [String] = []
            for station in stationFavoriteOrder where stationNames.contains(station) {
                updatedOrder.append(station)
            }
            for station in stationNames where !updatedOrder.contains(station) {
                updatedOrder.insert(station, at: 0)
            }
            stationFavoriteOrder = updatedOrder
        } catch {
            // Keep local cache if API fails
        }
    }

    func clearAll() {
        favoriteFoods = [:]
        favoriteStations = []
        foodFavoriteOrder = []
        stationFavoriteOrder = []
        UserDefaults.standard.removeObject(forKey: foodsKey)
        UserDefaults.standard.removeObject(forKey: stationsKey)
        UserDefaults.standard.removeObject(forKey: foodOrderKey)
        UserDefaults.standard.removeObject(forKey: stationOrderKey)
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
