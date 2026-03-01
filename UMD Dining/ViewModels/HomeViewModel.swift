import Foundation

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

    private var shuffleSeed = UInt64.random(in: 0...UInt64.max)

    var availableMealPeriods: [String] {
        let available = Set(allItems.map(\.mealPeriod))
        return mealPeriods.filter { available.contains($0) }
    }

    var displayItems: [MenuItem] {
        let filtered = allItems.filter { item in
            item.mealPeriod == selectedMealPeriod
            && selectedHallIds.contains(item.diningHallId)
            && !UserPreferences.shared.shouldHide(item: item)
        }

        let favorites = filtered.filter { FavoritesManager.shared.isFavorite(recNum: $0.recNum) }
        let nonFavorites = filtered.filter { !FavoritesManager.shared.isFavorite(recNum: $0.recNum) }

        var rng = SeededRNG(seed: shuffleSeed)
        let shuffled = nonFavorites.shuffled(using: &rng)

        return favorites + shuffled
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
        shuffleSeed = UInt64.random(in: 0...UInt64.max)

        do {
            let results = try await withThrowingTaskGroup(of: [MenuItem].self) { group in
                for hallId in allHallIds {
                    group.addTask {
                        try await DiningAPIService.shared.fetchMenu(
                            date: self.dateString, diningHallId: hallId
                        )
                    }
                }
                var all: [MenuItem] = []
                for try await items in group {
                    all.append(contentsOf: items)
                }
                return all
            }
            allItems = results
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

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
