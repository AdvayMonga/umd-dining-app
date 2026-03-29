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

    // Temporary session-only filters (not saved or synced)
    var filterVegetarian: Bool = false
    var filterVegan: Bool = false
    var filterAllergens: Set<String> = []

    var availableMealPeriods: [String] {
        let available = Set(allItems.map(\.mealPeriod))
        return mealPeriods.filter { available.contains($0) }
    }

    // Preserve backend order — just filter locally for meal period, hall, and preferences
    var displayItems: [MenuItem] {
        allItems.filter { item in
            item.mealPeriod == selectedMealPeriod
            && selectedHallIds.contains(item.diningHallId)
            && !UserPreferences.shared.shouldHide(item: item)
            && !sessionShouldHide(item: item)
        }
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
