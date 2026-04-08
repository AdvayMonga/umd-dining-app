import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int)
    case unauthorized

    nonisolated var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .decodingError(let e): return "Data error: \(e.localizedDescription)"
        case .serverError(let code): return "Server error: \(code)"
        case .unauthorized: return "Session expired. Please sign in again."
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

struct AnnouncementData: Decodable, Sendable {
    let title: String
    let message: String
    let active: Bool
}

private struct AnnouncementResponse: Decodable {
    let success: Bool
    let data: AnnouncementData
}

struct UserPreferencesData: Decodable, Sendable {
    let vegetarian: Bool
    let vegan: Bool
    let allergens: [String]
    let cuisinePrefs: [String]
    let preferredDiningHalls: [String]

    enum CodingKeys: String, CodingKey {
        case vegetarian, vegan, allergens
        case cuisinePrefs = "cuisine_prefs"
        case preferredDiningHalls = "preferred_dining_halls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vegetarian = try container.decode(Bool.self, forKey: .vegetarian)
        vegan = try container.decode(Bool.self, forKey: .vegan)
        allergens = try container.decode([String].self, forKey: .allergens)
        cuisinePrefs = try container.decodeIfPresent([String].self, forKey: .cuisinePrefs) ?? []
        preferredDiningHalls = try container.decodeIfPresent([String].self, forKey: .preferredDiningHalls) ?? []
    }
}

private struct PreferencesResponse: Decodable {
    let success: Bool
    let data: UserPreferencesData
}

private struct AuthResponse: Decodable {
    let success: Bool
    let token: String
}

private struct GuestAuthResponse: Decodable {
    let success: Bool
    let userId: String
    let token: String

    enum CodingKeys: String, CodingKey {
        case success
        case userId = "user_id"
        case token
    }
}

actor DiningAPIService {
    static let shared = DiningAPIService()

    private let baseURL = "https://api.umddining.com/api"

    // MARK: - Public endpoints

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

    func fetchRankedMenu(
        date: String,
        diningHallIds: [String],
        userId: String?,
        vegetarian: Bool = false,
        vegan: Bool = false,
        halal: Bool = false,
        highProtein: Bool = false,
        allergens: Set<String> = []
    ) async throws -> [MenuItem] {
        let encodedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? date
        var urlString = "\(baseURL)/ranked-menu?date=\(encodedDate)"
        for hallId in diningHallIds {
            urlString += "&dining_hall_ids=\(hallId)"
        }
        if vegetarian { urlString += "&vegetarian=true" }
        if vegan { urlString += "&vegan=true" }
        if halal { urlString += "&halal=true" }
        if highProtein { urlString += "&high_protein=true" }
        for allergen in allergens {
            let encoded = allergen.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? allergen
            urlString += "&allergens=\(encoded)"
        }
        let token = await AuthManager.shared.jwtToken
        let data = try await fetch(urlString, token: token)
        let response = try JSONDecoder().decode(MenuResponse.self, from: data)
        return response.data
    }

    func fetchNutrition(recNum: String) async throws -> NutritionInfo {
        let encoded = recNum.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? recNum
        let data = try await fetch("\(baseURL)/nutrition?rec_num=\(encoded)")
        let response = try JSONDecoder().decode(NutritionResponse.self, from: data)
        return response.data
    }

    func fetchTrendingSearches() async throws -> [String] {
        let data = try await fetch("\(baseURL)/trending-searches")
        struct TrendingSearchesResponse: Decodable { let success: Bool; let data: [String] }
        let response = try JSONDecoder().decode(TrendingSearchesResponse.self, from: data)
        return response.data
    }

    func searchFoods(query: String, semantic: Bool = false) async throws -> [SearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let token = await AuthManager.shared.jwtToken
        var url = "\(baseURL)/search?q=\(encoded)"
        if semantic { url += "&semantic=true" }
        let data = try await fetch(url, token: token)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.data
    }

    func fetchSimilarFoods(recNum: String, date: String? = nil) async throws -> [MenuItem] {
        let encoded = recNum.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? recNum
        var url = "\(baseURL)/nutrition/similar?rec_num=\(encoded)"
        if let date = date {
            let encodedDate = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? date
            url += "&date=\(encodedDate)"
        }
        let data = try await fetch(url)
        let response = try JSONDecoder().decode(MenuResponse.self, from: data)
        return response.data
    }

    // MARK: - Auth

    func registerGuest() async throws -> (userId: String, token: String) {
        let data = try await post("\(baseURL)/auth/guest", body: [:])
        let response = try JSONDecoder().decode(GuestAuthResponse.self, from: data)
        return (response.userId, response.token)
    }

    func upgradeGuestToApple(appleUserId: String) async throws -> String {
        let token = await AuthManager.shared.jwtToken
        let body = ["apple_user_id": appleUserId]
        let data = try await post("\(baseURL)/auth/upgrade", body: body, token: token)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        return response.token
    }

    func registerAppleUser(userId: String) async throws -> String {
        let body = ["apple_user_id": userId]
        let data = try await post("\(baseURL)/auth/apple", body: body)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        return response.token
    }

    func refreshToken() async throws -> String {
        let token = await AuthManager.shared.jwtToken
        let data = try await post("\(baseURL)/auth/refresh", body: [:], token: token)
        let response = try JSONDecoder().decode(AuthResponse.self, from: data)
        return response.token
    }

    // MARK: - Favorites (auth required)

    func fetchFavorites(userId: String) async throws -> [FavoriteItem] {
        let token = await AuthManager.shared.jwtToken
        let data = try await fetch("\(baseURL)/favorites", token: token)
        let response = try JSONDecoder().decode(FavoritesResponse.self, from: data)
        return response.data
    }

    func addFavorite(userId: String, recNum: String, name: String) async throws {
        let token = await AuthManager.shared.jwtToken
        let body = ["rec_num": recNum, "name": name]
        _ = try await post("\(baseURL)/favorites", body: body, token: token)
    }

    func removeFavorite(userId: String, recNum: String) async throws {
        let token = await AuthManager.shared.jwtToken
        let body = ["rec_num": recNum]
        _ = try await delete("\(baseURL)/favorites", body: body, token: token)
    }

    // MARK: - Station Favorites (auth required)

    func fetchStationFavorites(userId: String) async throws -> [StationFavoriteItem] {
        let token = await AuthManager.shared.jwtToken
        let data = try await fetch("\(baseURL)/station-favorites", token: token)
        let response = try JSONDecoder().decode(StationFavoritesResponse.self, from: data)
        return response.data
    }

    func addStationFavorite(userId: String, stationName: String) async throws {
        let token = await AuthManager.shared.jwtToken
        let body = ["station_name": stationName]
        _ = try await post("\(baseURL)/station-favorites", body: body, token: token)
    }

    func removeStationFavorite(userId: String, stationName: String) async throws {
        let token = await AuthManager.shared.jwtToken
        let body = ["station_name": stationName]
        _ = try await delete("\(baseURL)/station-favorites", body: body, token: token)
    }

    // MARK: - Preferences (auth required)

    func fetchPreferences(userId: String) async throws -> UserPreferencesData {
        let token = await AuthManager.shared.jwtToken
        let data = try await fetch("\(baseURL)/preferences", token: token)
        let response = try JSONDecoder().decode(PreferencesResponse.self, from: data)
        return response.data
    }

    func updatePreferences(userId: String, vegetarian: Bool, vegan: Bool, allergens: [String], cuisinePrefs: [String] = [], preferredDiningHalls: [String] = []) async throws {
        let token = await AuthManager.shared.jwtToken
        guard let url = URL(string: "\(baseURL)/preferences") else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token {
            request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "vegetarian": vegetarian,
            "vegan": vegan,
            "allergens": allergens,
            "cuisine_prefs": cuisinePrefs,
            "preferred_dining_halls": preferredDiningHalls
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { await handleUnauthorized(); throw APIError.unauthorized }
            if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
        }
    }

    // MARK: - Intake Tracking (auth required)

    func logIntake(recNum: String, name: String, date: String, mealPeriod: String?,
                   calories: Int, proteinG: Double, carbsG: Double, fatG: Double) async throws {
        let token = await AuthManager.shared.jwtToken
        guard let url = URL(string: "\(baseURL)/intake") else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token {
            request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "rec_num": recNum,
            "name": name,
            "date": date,
            "meal_period": mealPeriod ?? "",
            "calories": calories,
            "protein_g": proteinG,
            "carbs_g": carbsG,
            "fat_g": fatG,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { await handleUnauthorized(); throw APIError.unauthorized }
            if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
        }
    }

    func removeIntake(recNum: String, date: String, loggedAt: String) async throws {
        let token = await AuthManager.shared.jwtToken
        let body = ["rec_num": recNum, "date": date, "logged_at": loggedAt]
        _ = try await delete("\(baseURL)/intake", body: body, token: token)
    }

    func deleteAccount() async throws {
        let token = await AuthManager.shared.jwtToken
        _ = try await delete("\(baseURL)/auth/account", body: [:], token: token)
    }

    // MARK: - Engagement Tracking (fire-and-forget)

    nonisolated func trackItemView(recNum: String, foodName: String, source: String) {
        Task.detached(priority: .utility) {
            await self._fireAndForget("track/item-view", body: [
                "rec_num": recNum, "food_name": foodName, "source": source
            ])
        }
    }

    nonisolated func trackSearchQuery(query: String, resultCount: Int) {
        Task.detached(priority: .utility) {
            await self._fireAndForget("track/search-query", body: [
                "query": query, "result_count": resultCount
            ])
        }
    }

    private func _fireAndForget(_ path: String, body: [String: Any]) async {
        guard let url = URL(string: "\(baseURL)/\(path)") else { return }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await AuthManager.shared.jwtToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Networking

    private func fetch(_ urlString: String, token: String? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 10)
        if let t = token {
            request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 { await handleUnauthorized(); throw APIError.unauthorized }
                if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func post(_ urlString: String, body: [String: String], token: String? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token {
            request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { await handleUnauthorized(); throw APIError.unauthorized }
            if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
        }
        return data
    }

    private func delete(_ urlString: String, body: [String: String], token: String? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let t = token {
            request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { await handleUnauthorized(); throw APIError.unauthorized }
            if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
        }
        return data
    }

    @MainActor
    private func handleUnauthorized() async {
        if AuthManager.shared.isGuest { return }
        // Try refreshing the token before signing out
        if let newToken = try? await refreshToken() {
            AuthManager.shared.updateToken(newToken)
        } else {
            AuthManager.shared.signOut()
        }
    }

    // MARK: - Announcements

    func fetchAnnouncement() async -> AnnouncementData? {
        guard let data = try? await fetch("\(baseURL)/announcement") else { return nil }
        guard let response = try? JSONDecoder().decode(AnnouncementResponse.self, from: data) else { return nil }
        return response.data.active ? response.data : nil
    }
}
