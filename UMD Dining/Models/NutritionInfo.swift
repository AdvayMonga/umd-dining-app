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
}
