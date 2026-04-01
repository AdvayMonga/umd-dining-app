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
        didSet { saveGoals(); if !hasCustomMacros { recalculateMacros() } }
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

    var hasCustomMacros: Bool {
        didSet { saveGoals(); if !hasCustomMacros { recalculateMacros() } }
    }

    private init() {
        let goalRaw = UserDefaults.standard.string(forKey: "goal_weightGoal") ?? "maintain"
        self.weightGoal = WeightGoal(rawValue: goalRaw) ?? .maintain
        self.calorieGoalSetting = UserDefaults.standard.object(forKey: "goal_calories") as? Int ?? 2000
        self.hasCustomMacros = UserDefaults.standard.bool(forKey: "goal_customMacros")
        self.proteinGoal = UserDefaults.standard.object(forKey: "goal_protein") as? Int ?? 0
        self.carbsGoal = UserDefaults.standard.object(forKey: "goal_carbs") as? Int ?? 0
        self.fatGoal = UserDefaults.standard.object(forKey: "goal_fat") as? Int ?? 0

        // Calculate defaults if never set
        if proteinGoal == 0 && carbsGoal == 0 && fatGoal == 0 {
            recalculateMacros()
        }
    }

    func recalculateMacros() {
        let split = weightGoal.macroSplit
        let cal = Double(calorieGoalSetting)
        proteinGoal = Int(cal * split.protein / 4)
        carbsGoal = Int(cal * split.carbs / 4)
        fatGoal = Int(cal * split.fat / 9)
    }

    private func saveGoals() {
        UserDefaults.standard.set(weightGoal.rawValue, forKey: "goal_weightGoal")
        UserDefaults.standard.set(calorieGoalSetting, forKey: "goal_calories")
        UserDefaults.standard.set(hasCustomMacros, forKey: "goal_customMacros")
        UserDefaults.standard.set(proteinGoal, forKey: "goal_protein")
        UserDefaults.standard.set(carbsGoal, forKey: "goal_carbs")
        UserDefaults.standard.set(fatGoal, forKey: "goal_fat")
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
