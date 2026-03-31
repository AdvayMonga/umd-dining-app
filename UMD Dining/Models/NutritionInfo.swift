import Foundation

struct NutritionInfo: Decodable, Sendable {
    let name: String
    let recNum: String
    let allergens: String
    let ingredients: String
    let nutrition: [String: String]

    enum CodingKeys: String, CodingKey {
        case name
        case recNum = "rec_num"
        case allergens
        case ingredients
        case nutrition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        recNum = try container.decode(String.self, forKey: .recNum)
        allergens = try container.decodeIfPresent(String.self, forKey: .allergens) ?? ""
        ingredients = try container.decodeIfPresent(String.self, forKey: .ingredients) ?? ""
        nutrition = try container.decodeIfPresent([String: String].self, forKey: .nutrition) ?? [:]
    }
}
