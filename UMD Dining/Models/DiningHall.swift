import Foundation

struct DiningHall: Decodable, Identifiable, Sendable {
    let hallId: String
    let name: String
    let location: String

    var id: String { hallId }

    enum CodingKeys: String, CodingKey {
        case hallId = "hall_id"
        case name
        case location
    }
}
