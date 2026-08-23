import Foundation

struct AvailabilityInfo: Codable, Hashable, Sendable {
    let availableToday: Bool
    let station: String
    let diningHallId: String
    let diningHallName: String
    let nextAvailableDate: String?
    let unavailableThisWeek: Bool

    enum CodingKeys: String, CodingKey {
        case availableToday = "available_today"
        case station
        case diningHallId = "dining_hall_id"
        case diningHallName = "dining_hall_name"
        case nextAvailableDate = "next_available_date"
        case unavailableThisWeek = "unavailable_this_week"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        availableToday = try c.decodeIfPresent(Bool.self, forKey: .availableToday) ?? false
        station = try c.decodeIfPresent(String.self, forKey: .station) ?? ""
        diningHallId = try c.decodeIfPresent(String.self, forKey: .diningHallId) ?? ""
        diningHallName = try c.decodeIfPresent(String.self, forKey: .diningHallName) ?? ""
        nextAvailableDate = try c.decodeIfPresent(String.self, forKey: .nextAvailableDate)
        unavailableThisWeek = try c.decodeIfPresent(Bool.self, forKey: .unavailableThisWeek) ?? false
    }

    init(availableToday: Bool, station: String, diningHallId: String, diningHallName: String,
         nextAvailableDate: String?, unavailableThisWeek: Bool) {
        self.availableToday = availableToday
        self.station = station
        self.diningHallId = diningHallId
        self.diningHallName = diningHallName
        self.nextAvailableDate = nextAvailableDate
        self.unavailableThisWeek = unavailableThisWeek
    }

    private static let inputFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        f.locale = Locale.current
        return f
    }()

    private var locationText: String {
        let shortHall = diningHallName.replacingOccurrences(of: " Dining Hall", with: "")
        let parts = [station, shortHall].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    var displayLabel: String {
        if availableToday {
            return locationText
        }
        if let raw = nextAvailableDate, let d = Self.inputFormatter.date(from: raw) {
            let when = Self.displayFormatter.string(from: d)
            let loc = locationText
            return loc.isEmpty ? "Next: \(when)" : "Next: \(loc) on \(when)"
        }
        return "Unavailable this week"
    }

    var isEmpty: Bool {
        !availableToday && nextAvailableDate == nil && !unavailableThisWeek && station.isEmpty
    }
}
