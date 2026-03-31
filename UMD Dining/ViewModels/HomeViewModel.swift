import Foundation

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

    // Expansion state — reset on each load
    private var userCollapsedStations: Set<String> = []
    private var userExpandedDiscovery: Set<String> = []
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

    func toggleStationExpansion(station: String, hallId: String, isDiscovery: Bool) {
        let key = "\(station)_\(hallId)"
        if isDiscovery {
            if userExpandedDiscovery.contains(key) { userExpandedDiscovery.remove(key) }
            else { userExpandedDiscovery.insert(key) }
        } else {
            if userCollapsedStations.contains(key) { userCollapsedStations.remove(key) }
            else { userCollapsedStations.insert(key) }
        }
    }

    func isStationExpanded(station: String, hallId: String, isDiscovery: Bool) -> Bool {
        let key = "\(station)_\(hallId)"
        return isDiscovery
            ? userExpandedDiscovery.contains(key)
            : !userCollapsedStations.contains(key)
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
            let expanded = isStationExpanded(station: group.station, hallId: group.hallId, isDiscovery: false)
            rows.append(.stationHeader(station: group.station, diningHallId: group.hallId, isDiscovery: false))
            if expanded {
                let items: [MenuItem]
                if loadedFavStations.contains(group.station) {
                    // Favorited: show ALL items from this station (no cap)
                    items = filtered.filter { $0.station == group.station && $0.diningHallId == group.hallId }
                } else {
                    items = group.items
                }
                items.forEach { rows.append(.menuItem($0)) }
            }
        }

        if !discoveryGroups.isEmpty {
            if showDiscovery {
                for group in discoveryGroups {
                    let expanded = isStationExpanded(station: group.station, hallId: group.hallId, isDiscovery: true)
                    rows.append(.stationHeader(station: group.station, diningHallId: group.hallId, isDiscovery: true))
                    if expanded {
                        // 3 items from minimalFiltered — ignores dietary filters, backend already shuffled
                        minimalFiltered
                            .filter { $0.station == group.station && $0.diningHallId == group.hallId }
                            .prefix(3)
                            .forEach { rows.append(.menuItem($0)) }
                    }
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
        userCollapsedStations = []
        userExpandedDiscovery = []
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
