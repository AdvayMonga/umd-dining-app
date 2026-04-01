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
        // Full filters: meal + hall + dietary/allergen
        let filtered = allItems.filter { item in
            item.mealPeriod == selectedMealPeriod
            && selectedHallIds.contains(item.diningHallId)
            && !UserPreferences.shared.shouldHide(item: item)
            && !sessionShouldHide(item: item)
        }
        // Minimal filter: meal + hall only (discovery previews ignore dietary filters)
        let minimalFiltered = allItems.filter {
            $0.mealPeriod == selectedMealPeriod && selectedHallIds.contains($0.diningHallId)
        }

        // --- Build 20-item selected pool ---
        let foodFavs    = filtered.filter { loadedFavRecNums.contains($0.recNum) }
        let nonFoodFavs = filtered.filter { !loadedFavRecNums.contains($0.recNum) }
        let stationFavs = nonFoodFavs.filter { loadedFavStations.contains($0.station) }
        let rest        = nonFoodFavs.filter { !loadedFavStations.contains($0.station) }
        let scored      = rest.filter { $0.tag != nil }
        let unscored    = rest.filter { $0.tag == nil }

        let slotsPerHall = max(4, 20 / max(1, selectedHallIds.count))
        var hallCounts: [String: Int] = [:]
        var picked: [MenuItem] = []
        for item in scored {
            guard picked.count < 20 else { break }
            let count = hallCounts[item.diningHallId, default: 0]
            if count < slotsPerHall {
                picked.append(item)
                hallCounts[item.diningHallId] = count + 1
            }
        }
        picked += unscored.prefix(max(0, 20 - picked.count))
        let selected = foodFavs + stationFavs + picked

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
                    let discoveryItems = minimalFiltered.filter { $0.station == group.station && $0.diningHallId == group.hallId }
                    Array(discoveryItems.prefix(3)).forEach { rows.append(.menuItem($0)) }
                }
            } else {
                rows.append(.seeMore)
            }
        }

        return rows
    }

    private func sessionShouldHide(item: MenuItem) -> Bool {
        if filterVegan && !item.dietaryIcons.contains("vegan") { return true }
        if filterVegetarian && !item.dietaryIcons.contains("vegetarian") { return true }
        if filterHighProtein {
            let proteinStr = item.nutrition?["Protein"] ?? item.nutrition?["Protein."] ?? ""
            let digits = proteinStr.filter { $0.isNumber || $0 == "." }
            let grams = Double(digits) ?? 0
            if grams < 20 { return true }
        }
        for allergen in filterAllergens {
            if item.dietaryIcons.contains(allergen) { return true }
        }
        return false
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

    func loadMenus() async {
        isLoading = true
        errorMessage = nil
        allItems = []
        showDiscovery = false

        // Sync temp filters from saved profile preferences
        let prefs = UserPreferences.shared
        filterVegetarian = prefs.vegetarian
        filterVegan = prefs.vegan
        filterAllergens = prefs.allergens

        // Snapshot favorites at load time so feed order stays stable until next refresh
        loadedFavRecNums = Set(FavoritesManager.shared.favoriteFoods.keys)
        loadedFavStations = FavoritesManager.shared.favoriteStations

        do {
            let userId = await AuthManager.shared.userId
            allItems = try await DiningAPIService.shared.fetchRankedMenu(
                date: dateString,
                diningHallIds: allHallIds,
                userId: userId
            )
            if !availableMealPeriods.contains(selectedMealPeriod),
               let first = availableMealPeriods.first {
                selectedMealPeriod = first
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
