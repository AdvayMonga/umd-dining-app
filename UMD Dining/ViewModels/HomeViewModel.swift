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
        // 1. Apply all active filters
        let filtered = allItems.filter { item in
            item.mealPeriod == selectedMealPeriod
            && selectedHallIds.contains(item.diningHallId)
            && !UserPreferences.shared.shouldHide(item: item)
            && !sessionShouldHide(item: item)
        }

        // 2. Separate favorites from non-favorites; scored from untagged
        let foodFavs = filtered.filter { FavoritesManager.shared.isFavorite(recNum: $0.recNum) }
        let nonFavs  = filtered.filter { !FavoritesManager.shared.isFavorite(recNum: $0.recNum) }
        let scored   = nonFavs.filter { $0.tag != nil }  // score > 0, tag assigned by backend
        let unscored = nonFavs.filter { $0.tag == nil }  // score == 0, untagged entrees (sides already removed by backend)

        // 3. Take up to 20 scored items, balanced across selected halls
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

        // 4. Fill remaining slots with untagged entrees (backend already shuffled them by date)
        let needed = max(0, 20 - picked.count)
        picked += unscored.prefix(needed)

        // 5. Combine: food favorites always first, then the 20 picked items
        let selected = foodFavs + picked

        // 6. Group by (station, diningHallId) preserving insertion order
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

        // 7. Float favorited stations to top (stable sort)
        let sorted = groups.sorted {
            FavoritesManager.shared.isFavoriteStation($0.station)
            && !FavoritesManager.shared.isFavoriteStation($1.station)
        }

        // 8. Flatten to FeedRow
        var rows: [FeedRow] = []
        for group in sorted {
            rows.append(.stationHeader(station: group.station, diningHallId: group.hallId))
            group.items.forEach { rows.append(.menuItem($0)) }
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
