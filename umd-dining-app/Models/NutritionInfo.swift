import Foundation

struct NutritionInfo: Decodable, Sendable {
    let name: String
    let recNum: String
    let allergens: String
    let ingredients: String
    let nutrition: [String: String]
    let nextAvailable: String?
    let dietaryIcons: [String]
    let availability: AvailabilityInfo?

    enum CodingKeys: String, CodingKey {
        case name
        case recNum = "rec_num"
        case allergens
        case ingredients
        case nutrition
        case nextAvailable = "next_available"
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
        nextAvailable = try container.decodeIfPresent(String.self, forKey: .nextAvailable)
        dietaryIcons = try container.decodeIfPresent([String].self, forKey: .dietaryIcons) ?? []
        availability = try container.decodeIfPresent(AvailabilityInfo.self, forKey: .availability)
    }
}
