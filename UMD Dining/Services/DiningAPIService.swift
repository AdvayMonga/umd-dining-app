import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int)

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .decodingError(let e): return "Data error: \(e.localizedDescription)"
        case .serverError(let code): return "Server error: \(code)"
        }
    }
}

private struct DiningHallsResponse: Decodable {
    let success: Bool
    let data: [DiningHall]
}

private struct MenuResponse: Decodable {
    let success: Bool
    let data: [MenuItem]
}

private struct NutritionResponse: Decodable {
    let success: Bool
    let data: NutritionInfo
}

private struct SearchResponse: Decodable {
    let success: Bool
    let data: [SearchResult]
}

actor DiningAPIService {
    static let shared = DiningAPIService()

    private let baseURL = "http://umd-dining-api-prod.eba-zfimp7uy.us-east-1.elasticbeanstalk.com/api"

    func fetchDiningHalls() async throws -> [DiningHall] {
        let data = try await fetch("\(baseURL)/dining-halls")
        let response = try JSONDecoder().decode(DiningHallsResponse.self, from: data)
        return response.data
    }

    func fetchMenu(date: String, diningHallId: String) async throws -> [MenuItem] {
        let encodedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? date
        let data = try await fetch("\(baseURL)/menu?date=\(encodedDate)&dining_hall_id=\(diningHallId)")
        let response = try JSONDecoder().decode(MenuResponse.self, from: data)
        return response.data
    }

    func fetchNutrition(recNum: String) async throws -> NutritionInfo {
        let encoded = recNum.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? recNum
        let data = try await fetch("\(baseURL)/nutrition?rec_num=\(encoded)")
        let response = try JSONDecoder().decode(NutritionResponse.self, from: data)
        return response.data
    }

    func searchFoods(query: String) async throws -> [SearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let data = try await fetch("\(baseURL)/search?q=\(encoded)")
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.data
    }

    private func fetch(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw APIError.serverError(http.statusCode)
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
}
