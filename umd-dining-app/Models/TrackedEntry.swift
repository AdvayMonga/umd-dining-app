import Foundation
import SwiftData

@Model
class DailyLog {
    var date: Date
    @Relationship(deleteRule: .cascade, inverse: \TrackedEntry.dailyLog)
    var entries: [TrackedEntry] = []
    var calorieGoal: Int?

    var totalCalories: Int { entries.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { entries.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { entries.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { entries.reduce(0) { $0 + $1.fatG } }

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }
}

@Model
class TrackedEntry {
    var recNum: String
    var foodName: String
    var loggedAt: Date
    var servingMultiplier: Double = 1.0
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var mealPeriod: String?
    var diningHall: String?
    var serverID: String?

    var dailyLog: DailyLog?

    init(recNum: String, foodName: String, calories: Int, proteinG: Double,
         carbsG: Double, fatG: Double, mealPeriod: String? = nil, diningHall: String? = nil) {
        self.recNum = recNum
        self.foodName = foodName
        self.loggedAt = Date()
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.mealPeriod = mealPeriod
        self.diningHall = diningHall
    }

    /// Parse a nutrition string like "25g", "150", "10mg", "< 1g" into a Double.
    static func parseNumeric(_ raw: String?) -> Double {
        guard let raw = raw else { return 0 }
        let cleaned = raw
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
        let digits = cleaned.filter { $0.isNumber || $0 == "." }
        return Double(digits) ?? 0
    }

    /// Create a TrackedEntry from a raw nutrition dictionary (from MenuItem or NutritionInfo).
    static func from(nutrition: [String: String], name: String, recNum: String,
                     mealPeriod: String? = nil, diningHall: String? = nil,
                     servingMultiplier: Double = 1.0) -> TrackedEntry {
        let baseCal = parseNumeric(nutritionValue("Calories", from: nutrition))
        let baseProtein = parseNumeric(nutritionValue("Protein", from: nutrition))
        let baseCarbs = parseNumeric(nutritionValue("Total Carbohydrate", from: nutrition))
        let baseFat = parseNumeric(nutritionValue("Total Fat", from: nutrition))

        let entry = TrackedEntry(recNum: recNum, foodName: name,
                                  calories: Int(baseCal * servingMultiplier),
                                  proteinG: baseProtein * servingMultiplier,
                                  carbsG: baseCarbs * servingMultiplier,
                                  fatG: baseFat * servingMultiplier,
                                  mealPeriod: mealPeriod, diningHall: diningHall)
        entry.servingMultiplier = servingMultiplier
        return entry
    }

    /// Lookup a nutrition key with normalization (handles "Protein" vs "Protein." etc).
    private static func nutritionValue(_ key: String, from nutrition: [String: String]) -> String? {
        if let v = nutrition[key] { return v }
        let normalized = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return nutrition.first(where: {
            $0.key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == normalized
        })?.value
    }
}
