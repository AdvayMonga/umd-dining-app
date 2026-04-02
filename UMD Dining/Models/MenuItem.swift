import Foundation

struct MenuItem: Codable, Identifiable, Sendable {
    let name: String
    let recNum: String
    let diningHallId: String
    let date: String
    let mealPeriod: String
    let station: String
    let dietaryIcons: [String]
    let nutritionFetched: Bool
    let allergens: String?
    let ingredients: String?
    let nutrition: [String: String]?
    let tag: String?
    let tags: [String]

    var id: String { recNum }

    enum CodingKeys: String, CodingKey {
        case name
        case recNum = "rec_num"
        case diningHallId = "dining_hall_id"
        case date
        case mealPeriod = "meal_period"
        case station
        case dietaryIcons = "dietary_icons"
        case nutritionFetched = "nutrition_fetched"
        case allergens
        case ingredients
        case nutrition
        case tag
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        recNum = try container.decode(String.self, forKey: .recNum)
        diningHallId = try container.decode(String.self, forKey: .diningHallId)
        date = try container.decode(String.self, forKey: .date)
        mealPeriod = try container.decode(String.self, forKey: .mealPeriod)
        station = try container.decode(String.self, forKey: .station)
        dietaryIcons = try container.decode([String].self, forKey: .dietaryIcons)
        nutritionFetched = try container.decodeIfPresent(Bool.self, forKey: .nutritionFetched) ?? false
        allergens = try container.decodeIfPresent(String.self, forKey: .allergens)
        ingredients = try container.decodeIfPresent(String.self, forKey: .ingredients)
        nutrition = try container.decodeIfPresent([String: String].self, forKey: .nutrition)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}
