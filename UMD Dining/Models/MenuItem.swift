import Foundation

struct MenuItem: Decodable, Identifiable, Sendable {
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
    }
}
