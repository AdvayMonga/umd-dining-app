import Foundation
import SwiftData

enum WeightGoal: String, CaseIterable {
    case lose, maintain, gain

    var label: String {
        switch self {
        case .lose: return "Lose"
        case .maintain: return "Maintain"
        case .gain: return "Gain"
        }
    }

    var macroSplit: (protein: Double, carbs: Double, fat: Double) {
        switch self {
        case .lose:     return (0.40, 0.35, 0.25)
        case .maintain: return (0.30, 0.40, 0.30)
        case .gain:     return (0.25, 0.45, 0.30)
        }
    }
}

@MainActor
@Observable
class NutritionTrackerManager {
    static let shared = NutritionTrackerManager()

    var modelContext: ModelContext?

    // MARK: - Goals (persisted via UserDefaults)

    var weightGoal: WeightGoal {
        didSet { saveGoals(); recalculateAutoGoals() }
    }

    var calorieGoalSetting: Int {
        didSet { saveGoals(); if !hasCustomMacros { recalculateMacros() } }
    }

    var proteinGoal: Int {
        didSet { saveGoals() }
    }

    var carbsGoal: Int {
        didSet { saveGoals() }
    }

    var fatGoal: Int {
        didSet { saveGoals() }
    }

    var hasCustomGoals: Bool {
        didSet { saveGoals(); recalculateAutoGoals() }
    }

    var hasCustomMacros: Bool {
        didSet { saveGoals(); if !hasCustomMacros { recalculateMacros() } }
    }

    var weightLbs: Int {
        didSet { saveGoals(); recalculateAutoGoals() }
    }

    var heightInches: Int {
        didSet { saveGoals(); recalculateAutoGoals() }
    }

    private init() {
        let goalRaw = UserDefaults.standard.string(forKey: "goal_weightGoal") ?? "maintain"
        self.weightGoal = WeightGoal(rawValue: goalRaw) ?? .maintain
        self.calorieGoalSetting = UserDefaults.standard.object(forKey: "goal_calories") as? Int ?? 2000
        self.hasCustomGoals = UserDefaults.standard.bool(forKey: "goal_customGoals")
        self.hasCustomMacros = UserDefaults.standard.bool(forKey: "goal_customMacros")
        self.proteinGoal = UserDefaults.standard.object(forKey: "goal_protein") as? Int ?? 0
        self.carbsGoal = UserDefaults.standard.object(forKey: "goal_carbs") as? Int ?? 0
        self.fatGoal = UserDefaults.standard.object(forKey: "goal_fat") as? Int ?? 0
        self.weightLbs = UserDefaults.standard.object(forKey: "goal_weightLbs") as? Int ?? 160
        self.heightInches = UserDefaults.standard.object(forKey: "goal_heightInches") as? Int ?? 68

        // Calculate defaults if never set
        if proteinGoal == 0 && carbsGoal == 0 && fatGoal == 0 {
            recalculateAutoGoals()
        }
    }

    /// Recalculates both calories (if auto) and macros (if auto)
    func recalculateAutoGoals() {
        if !hasCustomGoals {
            recalculateCalories()
        }
        if !hasCustomMacros {
            recalculateMacros()
        }
    }

    /// Mifflin-St Jeor TDEE estimate (assumes moderate activity, age ~20 for college students)
    func recalculateCalories() {
        let weightKg = Double(weightLbs) * 0.453592
        let heightCm = Double(heightInches) * 2.54
        let age = 20.0

        // Mifflin-St Jeor (average of male/female since we don't ask sex)
        let bmrMale = 10 * weightKg + 6.25 * heightCm - 5 * age + 5
        let bmrFemale = 10 * weightKg + 6.25 * heightCm - 5 * age - 161
        let bmr = (bmrMale + bmrFemale) / 2

        // Moderate activity multiplier (college student walking campus)
        let tdee = bmr * 1.55

        let adjusted: Double
        switch weightGoal {
        case .lose:     adjusted = tdee - 500    // ~1 lb/week deficit
        case .maintain: adjusted = tdee
        case .gain:     adjusted = tdee + 350    // lean bulk surplus
        }

        // Round to nearest 50
        calorieGoalSetting = Int((adjusted / 50).rounded() * 50)
    }

    func recalculateMacros() {
        let weight = Double(weightLbs)
        let cal = Double(calorieGoalSetting)

        // Protein based on body weight (g per lb varies by goal)
        let proteinPerLb: Double
        switch weightGoal {
        case .lose:     proteinPerLb = 1.1
        case .maintain: proteinPerLb = 0.9
        case .gain:     proteinPerLb = 1.0
        }
        let proteinGrams = weight * proteinPerLb
        let proteinCals = proteinGrams * 4

        // Fat: 25-30% of total calories depending on goal
        let fatPct: Double
        switch weightGoal {
        case .lose:     fatPct = 0.25
        case .maintain: fatPct = 0.30
        case .gain:     fatPct = 0.28
        }
        let fatCals = cal * fatPct
        let fatGrams = fatCals / 9

        // Carbs: remaining calories
        let carbCals = max(cal - proteinCals - fatCals, 0)
        let carbGrams = carbCals / 4

        proteinGoal = Int(proteinGrams)
        fatGoal = Int(fatGrams)
        carbsGoal = Int(carbGrams)
    }

    private func saveGoals() {
        UserDefaults.standard.set(weightGoal.rawValue, forKey: "goal_weightGoal")
        UserDefaults.standard.set(calorieGoalSetting, forKey: "goal_calories")
        UserDefaults.standard.set(hasCustomGoals, forKey: "goal_customGoals")
        UserDefaults.standard.set(hasCustomMacros, forKey: "goal_customMacros")
        UserDefaults.standard.set(proteinGoal, forKey: "goal_protein")
        UserDefaults.standard.set(carbsGoal, forKey: "goal_carbs")
        UserDefaults.standard.set(fatGoal, forKey: "goal_fat")
        UserDefaults.standard.set(weightLbs, forKey: "goal_weightLbs")
        UserDefaults.standard.set(heightInches, forKey: "goal_heightInches")
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - CRUD

    func addEntry(name: String, recNum: String, nutrition: [String: String],
                  mealPeriod: String? = nil, diningHall: String? = nil,
                  servingMultiplier: Double = 1.0) {
        guard let context = modelContext else { return }

        let entry = TrackedEntry.from(nutrition: nutrition, name: name, recNum: recNum,
                                       mealPeriod: mealPeriod, diningHall: diningHall,
                                       servingMultiplier: servingMultiplier)

        let log = fetchOrCreateDailyLog(for: Date(), context: context)
        entry.dailyLog = log
        context.insert(entry)
        try? context.save()

        // Fire-and-forget sync to backend
        let date = formatDate(Date())
        let calories = entry.calories
        let protein = entry.proteinG
        let carbs = entry.carbsG
        let fat = entry.fatG
        Task {
            try? await DiningAPIService.shared.logIntake(
                recNum: recNum, name: name, date: date,
                mealPeriod: mealPeriod, calories: calories,
                proteinG: protein, carbsG: carbs, fatG: fat
            )
        }
    }

    func removeEntry(_ entry: TrackedEntry) {
        guard let context = modelContext else { return }

        let recNum = entry.recNum
        let date = formatDate(entry.loggedAt)
        let loggedAt = entry.loggedAt.ISO8601Format()

        context.delete(entry)
        try? context.save()

        // Fire-and-forget sync to backend
        Task {
            try? await DiningAPIService.shared.removeIntake(
                recNum: recNum, date: date, loggedAt: loggedAt
            )
        }
    }

    func clearDay(_ date: Date) {
        guard let context = modelContext else { return }
        if let log = fetchDailyLog(for: date, context: context) {
            context.delete(log)
            try? context.save()
        }
    }

    // MARK: - Queries

    func dailyLog(for date: Date) -> DailyLog? {
        guard let context = modelContext else { return nil }
        return fetchDailyLog(for: date, context: context)
    }

    func entries(for date: Date) -> [TrackedEntry] {
        guard let context = modelContext else { return [] }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        let descriptor = FetchDescriptor<TrackedEntry>(
            predicate: #Predicate { $0.loggedAt >= start && $0.loggedAt < end },
            sortBy: [SortDescriptor(\.loggedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Helpers

    private func fetchDailyLog(for date: Date, context: ModelContext) -> DailyLog? {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        return try? context.fetch(descriptor).first
    }

    private func fetchOrCreateDailyLog(for date: Date, context: ModelContext) -> DailyLog {
        if let existing = fetchDailyLog(for: date, context: context) {
            return existing
        }
        let log = DailyLog(date: date)
        context.insert(log)
        return log
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        return formatter.string(from: date)
    }
}
