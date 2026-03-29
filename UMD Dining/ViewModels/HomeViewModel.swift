import Foundation

enum FeedRow: Identifiable {
    case stationHeader(station: String, diningHallId: String)
    case menuItem(MenuItem)

    var id: String {
        switch self {
        case .stationHeader(let s, let h): return "header_\(s)_\(h)"
        case .menuItem(let item): return "item_\(item.id)"
        }
    }
}

@Observable
class HomeViewModel {
    var allItems: [MenuItem] = []
    var isLoading = false
    var errorMessage: String?
    var selectedMealPeriod: String = "Lunch"
    var selectedDate: Date = .now
    var selectedHallIds: Set<String> = ["19", "51", "16"]

    let diningHallNames: [String: String] = [
        "19": "Yahentamitsi",
        "51": "251 North",
        "16": "South Campus Diner"
    ]

    let allHallIds = ["19", "51", "16"]
    let mealPeriods = ["Breakfast", "Brunch", "Lunch", "Dinner"]

    // Temporary session-only filters (not saved or synced)
    var filterVegetarian: Bool = false
    var filterVegan: Bool = false
    var filterAllergens: Set<String> = []

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
        let filtered = allItems.filter { item in
            item.mealPeriod == selectedMealPeriod
            && selectedHallIds.contains(item.diningHallId)
            && !UserPreferences.shared.shouldHide(item: item)
            && !sessionShouldHide(item: item)
        }

        // Always include food favorites; top 20 of the rest (already ranked by backend)
        let foodFavs = filtered.filter { FavoritesManager.shared.isFavorite(recNum: $0.recNum) }
        let rest = filtered.filter { !FavoritesManager.shared.isFavorite(recNum: $0.recNum) }
        let selected = foodFavs + rest.prefix(20)

        // Group by (station, diningHallId) preserving insertion order
        var groups: [(station: String, hallId: String, items: [MenuItem])] = []
        var keyToIndex: [String: Int] = [:]
        for item in selected {
            let key = "\(item.station)_\(item.diningHallId)"
            if let idx = keyToIndex[key] {
                groups[idx].items.append(item)
            } else {
                keyToIndex[key] = groups.count
                groups.append((station: item.station, hallId: item.diningHallId, items: [item]))
            }
        }

        // Stable sort: favorited stations float to top
        let sorted = groups.sorted { a, b in
            FavoritesManager.shared.isFavoriteStation(a.station)
            && !FavoritesManager.shared.isFavoriteStation(b.station)
        }

        // Flatten into FeedRow array
        var rows: [FeedRow] = []
        for group in sorted {
            rows.append(.stationHeader(station: group.station, diningHallId: group.hallId))
            for item in group.items {
                rows.append(.menuItem(item))
            }
        }
        return rows
    }

    private func sessionShouldHide(item: MenuItem) -> Bool {
        if filterVegan && !item.dietaryIcons.contains("vegan") { return true }
        if filterVegetarian && !item.dietaryIcons.contains("vegetarian") { return true }
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
