import Foundation

struct SearchResult: Decodable, Identifiable, Sendable {
    let name: String
    let recNum: String
    let allergens: String
    let ingredients: String
    let nutrition: [String: String]
    let nutritionFetched: Bool
    let station: String
    let diningHallId: String
    let diningHallName: String
    let dietaryIcons: [String]
    let availability: AvailabilityInfo?

    var id: String { recNum }

    enum CodingKeys: String, CodingKey {
        case name
        case recNum = "rec_num"
        case allergens
        case ingredients
        case nutrition
        case nutritionFetched = "nutrition_fetched"
        case station
        case diningHallId = "dining_hall_id"
        case diningHallName = "dining_hall_name"
        case dietaryIcons = "dietary_icons"
        case availability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        recNum = try container.decode(String.self, forKey: .recNum)
        allergens = try container.decodeIfPresent(String.self, forKey: .allergens) ?? ""
        ingredients = try container.decodeIfPresent(String.self, forKey: .ingredients) ?? ""
        nutrition = try container.decodeIfPresent([String: String].self, forKey: .nutrition) ?? [:]
        nutritionFetched = try container.decodeIfPresent(Bool.self, forKey: .nutritionFetched) ?? false
        station = try container.decodeIfPresent(String.self, forKey: .station) ?? ""
        diningHallId = try container.decodeIfPresent(String.self, forKey: .diningHallId) ?? ""
        diningHallName = try container.decodeIfPresent(String.self, forKey: .diningHallName) ?? ""
        dietaryIcons = try container.decodeIfPresent([String].self, forKey: .dietaryIcons) ?? []
        availability = try container.decodeIfPresent(AvailabilityInfo.self, forKey: .availability)
    }
}
