import Foundation

struct SearchResult: Decodable, Identifiable, Sendable {
    let name: String
    let recNum: String
    let allergens: String
    let ingredients: String
    let nutrition: [String: String]
    let nutritionFetched: Bool

    var id: String { recNum }

    enum CodingKeys: String, CodingKey {
        case name
        case recNum = "rec_num"
        case allergens
        case ingredients
        case nutrition
        case nutritionFetched = "nutrition_fetched"
    }
}
