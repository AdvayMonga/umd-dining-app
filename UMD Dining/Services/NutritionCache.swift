import Foundation

/// Session-scoped in-memory cache for fetched nutrition data.
/// Prevents duplicate API calls when the "+" button is tapped on the same food multiple times.
actor NutritionCache {
    static let shared = NutritionCache()

    private var cache: [String: NutritionInfo] = [:]

    func get(_ recNum: String) -> NutritionInfo? {
        cache[recNum]
    }

    func set(_ recNum: String, _ info: NutritionInfo) {
        cache[recNum] = info
    }
}
