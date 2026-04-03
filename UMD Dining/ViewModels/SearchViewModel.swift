import Foundation

struct StationSearchResult: Identifiable {
    let station: String
    let diningHallId: String
    let diningHallName: String
    let items: [MenuItem]
    var id: String { "\(station)_\(diningHallId)" }
}

@Observable
class SearchViewModel {
    var query: String = ""
    var results: [SearchResult] = []
    var stationResults: [StationSearchResult] = []
    var isLoading = false
    var errorMessage: String?
    var hasSearched = false

    private var searchTask: Task<Void, Never>?

    func search(menuItems: [MenuItem] = [], hallNames: [String: String] = [:]) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            stationResults = []
            hasSearched = false
            return
        }

        // Client-side station search from loaded menu data
        let lowered = trimmed.lowercased()
        var seenStations: Set<String> = []
        var stations: [StationSearchResult] = []
        for item in menuItems {
            let key = "\(item.station)_\(item.diningHallId)"
            if !seenStations.contains(key) && item.station.lowercased().contains(lowered) {
                seenStations.insert(key)
                let items = menuItems.filter { $0.station == item.station && $0.diningHallId == item.diningHallId }
                stations.append(StationSearchResult(
                    station: item.station,
                    diningHallId: item.diningHallId,
                    diningHallName: hallNames[item.diningHallId] ?? "Unknown",
                    items: items
                ))
            }
        }
        stationResults = stations

        // Server-side food search (two-phase: fast text, then semantic)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            isLoading = true
            hasSearched = true

            // Phase 1: Fast text + ingredient + personalization results
            do {
                results = try await DiningAPIService.shared.searchFoods(query: trimmed)
                errorMessage = nil
                DiningAPIService.shared.trackSearchQuery(query: trimmed, resultCount: results.count)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false

            // Phase 2: Semantic re-rank (runs in background, replaces results)
            guard !Task.isCancelled else { return }
            do {
                let semanticResults = try await DiningAPIService.shared.searchFoods(query: trimmed, semantic: true)
                guard !Task.isCancelled else { return }
                results = semanticResults
            } catch {
                // Semantic failure is silent — phase 1 results remain
            }
        }
    }
}
