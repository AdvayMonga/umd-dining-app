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

private struct FavoritesResponse: Decodable {
    let success: Bool
    let data: [FavoriteItem]
}

struct FavoriteItem: Decodable, Sendable {
    let recNum: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case recNum = "rec_num"
        case name
    }
}

private struct StationFavoritesResponse: Decodable {
    let success: Bool
    let data: [StationFavoriteItem]
}

struct StationFavoriteItem: Decodable, Sendable {
    let stationName: String

    enum CodingKeys: String, CodingKey {
        case stationName = "station_name"
    }
}

private struct SuccessResponse: Decodable {
    let success: Bool
}

struct UserPreferencesData: Decodable, Sendable {
    let vegetarian: Bool
    let vegan: Bool
    let allergens: [String]
}

private struct PreferencesResponse: Decodable {
    let success: Bool
    let data: UserPreferencesData
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

    // MARK: - Auth & Favorites

    func registerAppleUser(userId: String) async throws {
        let body = ["apple_user_id": userId]
        _ = try await post("\(baseURL)/auth/apple", body: body)
    }

    func fetchFavorites(userId: String) async throws -> [FavoriteItem] {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        let data = try await fetch("\(baseURL)/favorites?user_id=\(encoded)")
        let response = try JSONDecoder().decode(FavoritesResponse.self, from: data)
        return response.data
    }

    func addFavorite(userId: String, recNum: String, name: String) async throws {
        let body = ["user_id": userId, "rec_num": recNum, "name": name]
        _ = try await post("\(baseURL)/favorites", body: body)
    }

    func removeFavorite(userId: String, recNum: String) async throws {
        let body = ["user_id": userId, "rec_num": recNum]
        _ = try await delete("\(baseURL)/favorites", body: body)
    }

    // MARK: - Station Favorites

    func fetchStationFavorites(userId: String) async throws -> [StationFavoriteItem] {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        let data = try await fetch("\(baseURL)/station-favorites?user_id=\(encoded)")
        let response = try JSONDecoder().decode(StationFavoritesResponse.self, from: data)
        return response.data
    }

    func addStationFavorite(userId: String, stationName: String) async throws {
        let body = ["user_id": userId, "station_name": stationName]
        _ = try await post("\(baseURL)/station-favorites", body: body)
    }

    func removeStationFavorite(userId: String, stationName: String) async throws {
        let body = ["user_id": userId, "station_name": stationName]
        _ = try await delete("\(baseURL)/station-favorites", body: body)
    }

    // MARK: - Preferences

    func fetchPreferences(userId: String) async throws -> UserPreferencesData {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? userId
        let data = try await fetch("\(baseURL)/preferences?user_id=\(encoded)")
        let response = try JSONDecoder().decode(PreferencesResponse.self, from: data)
        return response.data
    }

    func updatePreferences(userId: String, vegetarian: Bool, vegan: Bool, allergens: [String]) async throws {
        guard let url = URL(string: "\(baseURL)/preferences") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "user_id": userId,
            "vegetarian": vegetarian,
            "vegan": vegan,
            "allergens": allergens
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
    }

    // MARK: - Networking

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

    private func post(_ urlString: String, body: [String: String]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        return data
    }

    private func delete(_ urlString: String, body: [String: String]) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.serverError(http.statusCode)
        }
        return data
    }
}
