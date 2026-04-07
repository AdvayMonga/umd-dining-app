import Foundation
import SwiftUI

enum FeedRow: Identifiable {
    case stationHeader(station: String, diningHallId: String, isDiscovery: Bool)
    case menuItem(MenuItem)
    case seeMore

    var id: String {
        switch self {
        case .stationHeader(let s, let h, _): return "header_\(s)_\(h)"
        case .menuItem(let item): return "item_\(item.id)_\(item.station)_\(item.diningHallId)"
        case .seeMore: return "see_more"
        }
    }
}

@Observable
class HomeViewModel {
    var allItems: [MenuItem] = []
    var isLoading = false
    var errorMessage: String?
    var selectedMealPeriod: String = "Lunch"
    var selectedDate: Date = {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour >= 22 {
            return Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        }
        return .now
    }()
    var selectedHallIds: Set<String> = ["19", "51", "16"]

    let diningHallNames: [String: String] = [
        "19": "Yahentamitsi",
        "51": "251 North",
        "16": "South Campus Diner"
    ]

    let allHallIds = ["19", "51", "16"]
    let mealPeriods = ["Breakfast", "Brunch", "Lunch", "Dinner"]

    // Temporary session-only filters — defaults loaded from profile prefs
    var filterVegetarian: Bool = false
    var filterVegan: Bool = false
    var filterHighProtein: Bool = false
    var filterAllergens: Set<String> = []

    var showDiscovery: Bool = false

    // Cache: skip network call if same date + filters already loaded
    private var lastLoadedKey: String?
    private var hasLoadedPrefs = false

    private var currentCacheKey: String {
        let allergenStr = filterAllergens.sorted().joined(separator: ",")
        let cuisinePrefs = UserPreferences.shared.cuisinePrefs.sorted().joined(separator: ",")
        return "\(dateString)|\(filterVegetarian)|\(filterVegan)|\(filterHighProtein)|\(allergenStr)|\(cuisinePrefs)"
    }

    // Snapshot of favorites at load time — keeps feed order stable until refresh
    private var loadedFavRecNums: Set<String> = []
    private var loadedFavStations: Set<String> = []

    var availableMealPeriods: [String] {
        let available = Set(allItems.map(\.mealPeriod))
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        let isWeekend = weekday == 1 || weekday == 7
        return mealPeriods.filter { period in
            available.contains(period)
            && !(isWeekend && (period == "Breakfast" || period == "Lunch"))
        }
    }


    var displayRows: [FeedRow] {
        // Filter by meal + hall (dietary/allergen filtering is done server-side)
        let filtered = allItems.filter { item in
            item.mealPeriod == selectedMealPeriod
            && selectedHallIds.contains(item.diningHallId)
        }
        // Minimal filter: meal + hall only (discovery previews)
        let minimalFiltered = allItems.filter {
            $0.mealPeriod == selectedMealPeriod && selectedHallIds.contains($0.diningHallId)
        }

        // --- Build 20-item selected pool (prioritized) ---
        let foodFavs    = filtered.filter { loadedFavRecNums.contains($0.recNum) }
        let nonFoodFavs = filtered.filter { !loadedFavRecNums.contains($0.recNum) }
        let stationFavs = nonFoodFavs.filter { loadedFavStations.contains($0.station) }
        let rest        = nonFoodFavs.filter { !loadedFavStations.contains($0.station) }
        let scored      = rest.filter { $0.tag != nil }
        let unscored    = rest.filter { $0.tag == nil }

        // Fill 20 slots in priority order: favorites → station favs → scored → unscored
        var selected: [MenuItem] = []
        var seenRecs: Set<String> = []
        for item in foodFavs + stationFavs + scored + unscored {
            guard selected.count < 20 else { break }
            if !seenRecs.contains(item.recNum) {
                seenRecs.insert(item.recNum)
                selected.append(item)
            }
        }

        // --- Build recommended groups (stations with items in selected) ---
        var recommendedGroups: [(station: String, hallId: String, items: [MenuItem])] = []
        var keyToIndex: [String: Int] = [:]
        for item in selected {
            let key = "\(item.station)_\(item.diningHallId)"
            if let idx = keyToIndex[key] {
                recommendedGroups[idx].items.append(item)
            } else {
                keyToIndex[key] = recommendedGroups.count
                recommendedGroups.append((item.station, item.diningHallId, [item]))
            }
        }
        let sortedRecommended = recommendedGroups.sorted {
            loadedFavStations.contains($0.station)
            && !loadedFavStations.contains($1.station)
        }

        // --- Build discovery groups (in minimalFiltered but not in recommended) ---
        let recommendedKeys = Set(recommendedGroups.map { "\($0.station)_\($0.hallId)" })
        var discoveryKeys: [String] = []
        var seenDiscovery: Set<String> = []
        for item in minimalFiltered {
            let key = "\(item.station)_\(item.diningHallId)"
            if !recommendedKeys.contains(key) && !seenDiscovery.contains(key) {
                discoveryKeys.append(key)
                seenDiscovery.insert(key)
            }
        }
        let discoveryGroups: [(station: String, hallId: String)] = discoveryKeys.compactMap { key in
            guard let item = minimalFiltered.first(where: { "\($0.station)_\($0.diningHallId)" == key })
            else { return nil }
            return (item.station, item.diningHallId)
        }.sorted {
            let aFav = loadedFavStations.contains($0.station)
            let bFav = loadedFavStations.contains($1.station)
            if aFav != bFav { return aFav }
            return $0.station < $1.station
        }

        // --- Flatten to FeedRow ---
        var rows: [FeedRow] = []

        for group in sortedRecommended {
            rows.append(.stationHeader(station: group.station, diningHallId: group.hallId, isDiscovery: false))
            let allStationItems = filtered.filter { $0.station == group.station && $0.diningHallId == group.hallId }
            let cap = loadedFavStations.contains(group.station) ? 6 : 4
            let items = Array(allStationItems.prefix(cap))
            items.forEach { rows.append(.menuItem($0)) }
        }

        if !discoveryGroups.isEmpty {
            if showDiscovery {
                for group in discoveryGroups {
                    rows.append(.stationHeader(station: group.station, diningHallId: group.hallId, isDiscovery: true))
                }
            } else {
                rows.append(.seeMore)
            }
        }

        return rows
    }

    func diningHallName(for id: String) -> String {
        diningHallNames[id] ?? "Unknown"
    }

    func itemsForStation(station: String, hallId: String) -> [MenuItem] {
        allItems.filter { $0.station == station && $0.diningHallId == hallId }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        return f.string(from: selectedDate)
    }

    func autoSelectMealPeriod() {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 {
            selectedMealPeriod = "Breakfast"
        } else if hour < 16 {
            selectedMealPeriod = "Lunch"
        } else {
            selectedMealPeriod = "Dinner"
        }
    }

    private static let feedCacheKey = "cached_feed_data"
    private static let feedCacheKeyId = "cached_feed_key"

    private func loadFromDisk() {
        guard let keyId = UserDefaults.standard.string(forKey: Self.feedCacheKeyId),
              keyId == currentCacheKey,
              let data = UserDefaults.standard.data(forKey: Self.feedCacheKey),
              let items = try? JSONDecoder().decode([MenuItem].self, from: data)
        else { return }
        allItems = items
        lastLoadedKey = keyId
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(allItems) else { return }
        UserDefaults.standard.set(data, forKey: Self.feedCacheKey)
        UserDefaults.standard.set(currentCacheKey, forKey: Self.feedCacheKeyId)
    }

    func loadMenus() async {
        // Try disk cache first (instant app launch)
        if allItems.isEmpty {
            loadFromDisk()
        }

        // Skip network if same date + filters already loaded
        guard lastLoadedKey != currentCacheKey else { return }

        isLoading = allItems.isEmpty  // Only show spinner if no cached data
        errorMessage = nil
        showDiscovery = false

        // Sync temp filters from saved profile preferences (once per session)
        if !hasLoadedPrefs {
            let prefs = UserPreferences.shared
            filterVegetarian = prefs.vegetarian
            filterVegan = prefs.vegan
            filterAllergens = prefs.allergens
            hasLoadedPrefs = true
        }

        // Snapshot favorites at load time so feed order stays stable until next refresh
        loadedFavRecNums = Set(FavoritesManager.shared.favoriteFoods.keys)
        loadedFavStations = FavoritesManager.shared.favoriteStations

        do {
            let userId = await AuthManager.shared.userId
            allItems = try await DiningAPIService.shared.fetchRankedMenu(
                date: dateString,
                diningHallIds: allHallIds,
                userId: userId,
                vegetarian: filterVegetarian,
                vegan: filterVegan,
                highProtein: filterHighProtein,
                allergens: filterAllergens
            )
            lastLoadedKey = currentCacheKey
            saveToDisk()
            if !availableMealPeriods.contains(selectedMealPeriod),
               let first = availableMealPeriods.first {
                selectedMealPeriod = first
            }
        } catch is CancellationError {
            // Ignore — task was superseded by a new load
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func forceReloadMenus() async {
        lastLoadedKey = nil
        hasLoadedPrefs = false
        await loadMenus()
    }

    func syncPrefsAndReloadIfNeeded() async {
        // Sync profile prefs into session filters
        let prefs = UserPreferences.shared
        filterVegetarian = prefs.vegetarian
        filterVegan = prefs.vegan
        filterAllergens = prefs.allergens

        // Check if favorites changed since last load
        let currentFavFoods = Set(FavoritesManager.shared.favoriteFoods.keys)
        let currentFavStations = FavoritesManager.shared.favoriteStations
        let favsChanged = currentFavFoods != loadedFavRecNums || currentFavStations != loadedFavStations

        if favsChanged {
            loadedFavRecNums = currentFavFoods
            loadedFavStations = currentFavStations
            lastLoadedKey = nil  // Force re-fetch since favorites affect ranking
        }

        // Re-fetch if cache key changed (prefs/filters/cuisine) or favorites changed
        await loadMenus()
    }
}
