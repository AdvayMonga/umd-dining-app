import Foundation

@MainActor
@Observable
class NutritionViewModel {
    var nutritionInfo: NutritionInfo?
    var isLoading = true
    var errorMessage: String?

    var similarFoods: [MenuItem]?
    var similarFoodsLoading = false

    func loadNutrition(recNum: String) async {
        isLoading = true
        errorMessage = nil
        do {
            nutritionInfo = try await DiningAPIService.shared.fetchNutrition(recNum: recNum)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadSimilarFoods(recNum: String, date: String?) async {
        similarFoodsLoading = true
        do {
            similarFoods = try await DiningAPIService.shared.fetchSimilarFoods(recNum: recNum, date: date)
        } catch {
            similarFoods = []
        }
        similarFoodsLoading = false
    }
}
