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
    var selectedHallId: String

    let diningHallNames: [String: String] = [
        "19": "Yahentamitsi",
        "51": "251 North",
        "16": "South Campus Diner"
    ]

    let allHallIds = ["19", "51", "16"]

    init(selectedHallId: String) {
        self.selectedHallId = selectedHallId
    }
    let mealPeriods = ["Breakfast", "Brunch", "Lunch", "Dinner"]

    // Temporary session-only filters — defaults loaded from profile prefs
    var filterVegetarian: Bool = false
    var filterVegan: Bool = false
    var filterHalal: Bool = false
    var filterGlutenFree: Bool = false
    var filterDairyFree: Bool = false
    var filterHighProtein: Bool = false
    var filterAllergens: Set<String> = []

    var showDiscovery: Bool = false

    // Cache: skip network call if same date + filters already loaded
    private var lastLoadedKey: String?
    private var hasLoadedPrefs = false

    var filtersMatchDefaults: Bool {
        let prefs = UserPreferences.shared
        return filterVegetarian == prefs.vegetarian
            && filterVegan == prefs.vegan
            && filterHalal == prefs.halal
            && filterGlutenFree == prefs.glutenFree
            && filterDairyFree == prefs.dairyFree
            && filterAllergens == prefs.allergens
            && !filterHighProtein
    }

    private var currentCacheKey: String {
        let allergenStr = filterAllergens.sorted().joined(separator: ",")
        let cuisinePrefs = UserPreferences.shared.cuisinePrefs.sorted().joined(separator: ",")
        let hallPrefs = UserPreferences.shared.preferredDiningHalls.sorted().joined(separator: ",")
        return "\(dateString)|\(filterVegetarian)|\(filterVegan)|\(filterHalal)|\(filterGlutenFree)|\(filterDairyFree)|\(filterHighProtein)|\(allergenStr)|\(cuisinePrefs)|\(hallPrefs)"
    }

    // Snapshot of favorites at load time — keeps feed order stable until refresh
    private var loadedFavRecNums: Set<String> = []
    private var loadedFavStations: Set<String> = []

    var availableMealPeriods: [String] {
        let hallItems = allItems.filter { $0.diningHallId == selectedHallId }
        let available = Set(hallItems.map(\.mealPeriod))
        let weekday = Calendar.current.component(.weekday, from: selectedDate)
        let isWeekend = weekday == 1 || weekday == 7
        return mealPeriods.filter { period in
            available.contains(period)
            && !(isWeekend && (period == "Breakfast" || period == "Lunch"))
        }
    }


    private static let sideStationKeywords = [
        "sauce", "condiment", "dressing", "topping", "side dish", "sides",
        "beverage", "drink"
    ]

    private static let sideItemKeywords = [
        "dressing", "ranch", "vinaigrette", "sauce", "salsa", "mayo", "ketchup",
        "mustard", "hot sauce", "butter", "creamer", "syrup", "gravy", "aioli",
        "marinade", "relish", "hummus", "spread"
    ]

    private func isSideStation(_ name: String) -> Bool {
        let lower = name.lowercased()
        return Self.sideStationKeywords.contains { lower.contains($0) }
    }

    private func isSideItem(_ name: String) -> Bool {
        let lower = name.lowercased()
        return Self.sideItemKeywords.contains { lower.contains($0) }
    }

    // Max stations shown in the home feed before "See More" appears
    private static let maxRecommendedStations = 5

    var displayRows: [FeedRow] {
        // Filter by meal + hall, excluding side stations and side items
        let filtered = allItems.filter { item in
            item.mealPeriod == selectedMealPeriod
            && item.diningHallId == selectedHallId
            && !isSideStation(item.station)
            && !isSideItem(item.name)
        }
        // Minimal filter for building station list (no dietary filter applied)
        let minimalFiltered = allItems.filter {
            $0.mealPeriod == selectedMealPeriod
            && $0.diningHallId == selectedHallId
            && !isSideStation($0.station)
        }

        // --- Build all unique stations in order (favored first) ---
        var allStationKeys: [String] = []
        var seenKeys: Set<String> = []
        for item in minimalFiltered {
            let key = "\(item.station)_\(item.diningHallId)"
            if !seenKeys.contains(key) { allStationKeys.append(key); seenKeys.insert(key) }
        }
        let allStations: [(station: String, hallId: String)] = allStationKeys.compactMap { key in
            guard let item = minimalFiltered.first(where: { "\($0.station)_\($0.diningHallId)" == key })
            else { return nil }
            return (item.station, item.diningHallId)
        }.sorted {
            let aFav = loadedFavStations.contains($0.station)
            let bFav = loadedFavStations.contains($1.station)
            if aFav != bFav { return aFav }
            return false
        }

        // Split into recommended (first N) and discovery (rest)
        let cap = Self.maxRecommendedStations
        let recommendedStations = Array(allStations.prefix(cap))
        let discoveryStations   = allStations.count > cap ? Array(allStations.dropFirst(cap)) : []

        // --- Flatten to FeedRow ---
        var rows: [FeedRow] = []

        for group in recommendedStations {
            let stationItems = filtered.filter { $0.station == group.station && $0.diningHallId == group.hallId }
            guard !stationItems.isEmpty else { continue }
            rows.append(.stationHeader(station: group.station, diningHallId: group.hallId, isDiscovery: false))
            // Show max 3 items per station (4 for favorited stations)
            let itemCap = loadedFavStations.contains(group.station) ? 4 : 3
            Array(stationItems.prefix(itemCap)).forEach { rows.append(.menuItem($0)) }
        }

        if !discoveryStations.isEmpty {
            if showDiscovery {
                for group in discoveryStations {
                    let stationItems = filtered.filter { $0.station == group.station && $0.diningHallId == group.hallId }
                    guard !stationItems.isEmpty else { continue }
                    rows.append(.stationHeader(station: group.station, diningHallId: group.hallId, isDiscovery: true))
                    let itemCap = loadedFavStations.contains(group.station) ? 4 : 3
                    Array(stationItems.prefix(itemCap)).forEach { rows.append(.menuItem($0)) }
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
            filterHalal = prefs.halal
            filterGlutenFree = prefs.glutenFree
            filterDairyFree = prefs.dairyFree
            filterAllergens = prefs.allergens
            hasLoadedPrefs = true
        }

        // Snapshot favorites at load time so feed order stays stable until next refresh
        loadedFavRecNums = Set(FavoritesManager.shared.favoriteFoods.keys)
        loadedFavStations = FavoritesManager.shared.favoriteStations

        do {
            let userId = await AuthManager.shared.userId
            var effectiveAllergens = filterAllergens
            if filterGlutenFree { effectiveAllergens.insert("Contains gluten") }
            if filterDairyFree { effectiveAllergens.insert("Contains dairy") }
            allItems = try await DiningAPIService.shared.fetchRankedMenu(
                date: dateString,
                diningHallIds: allHallIds,
                userId: userId,
                vegetarian: filterVegetarian,
                vegan: filterVegan,
                halal: filterHalal,
                highProtein: filterHighProtein,
                allergens: effectiveAllergens
            )
            lastLoadedKey = currentCacheKey
            if filtersMatchDefaults {
                saveToDisk()
            }
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
        filterHalal = prefs.halal
        filterGlutenFree = prefs.glutenFree
        filterDairyFree = prefs.dairyFree
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
