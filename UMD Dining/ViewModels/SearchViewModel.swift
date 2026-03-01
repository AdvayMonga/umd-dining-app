import Foundation

@Observable
class SearchViewModel {
    var query: String = ""
    var results: [SearchResult] = []
    var isLoading = false
    var errorMessage: String?
    var hasSearched = false

    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            hasSearched = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isLoading = true
            hasSearched = true
            do {
                results = try await DiningAPIService.shared.searchFoods(query: trimmed)
            } catch is CancellationError {
                // Ignore cancellation
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
