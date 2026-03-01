import Foundation

@Observable
class NutritionViewModel {
    var nutritionInfo: NutritionInfo?
    var isLoading = false
    var errorMessage: String?

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
}
