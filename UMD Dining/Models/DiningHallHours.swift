import Foundation

struct MealWindow {
    let name: String
    let openMinute: Int   // minutes from midnight
    let closeMinute: Int

    func contains(minute: Int) -> Bool {
        minute >= openMinute && minute < closeMinute
    }

    var openTimeString: String { minuteToString(openMinute) }
    var closeTimeString: String { minuteToString(closeMinute) }

    private func minuteToString(_ m: Int) -> String {
        let hour = m / 60
        let min = m % 60
        let period = hour < 12 ? "AM" : "PM"
        let displayHour = hour == 0 ? 12 : hour > 12 ? hour - 12 : hour
        return min == 0 ? "\(displayHour) \(period)" : "\(displayHour):\(String(format: "%02d", min)) \(period)"
    }
}

struct DiningHallSchedule {
    let hallId: String
    let weekdayWindows: [MealWindow]
    let weekendWindows: [MealWindow]

    struct Status {
        let isOpen: Bool
        let currentMeal: String?
        let closeTime: String?
        let nextMeal: String?
        let nextOpenTime: String?

        static let closed = Status(isOpen: false, currentMeal: nil, closeTime: nil, nextMeal: nil, nextOpenTime: nil)
    }

    func currentStatus(at date: Date = .now) -> Status {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        let windows = isWeekend ? weekendWindows : weekdayWindows
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let minute = h * 60 + m

        for window in windows {
            if window.contains(minute: minute) {
                return Status(isOpen: true, currentMeal: window.name, closeTime: window.closeTimeString, nextMeal: nil, nextOpenTime: nil)
            }
        }
        for window in windows where window.openMinute > minute {
            return Status(isOpen: false, currentMeal: nil, closeTime: nil, nextMeal: window.name, nextOpenTime: window.openTimeString)
        }
        return .closed
    }

    // Hardcoded hours — week of 4/27–5/3 (verify each semester against UMD Dining schedule)
    static let all: [String: DiningHallSchedule] = [
        "19": DiningHallSchedule(
            hallId: "19",
            weekdayWindows: [
                MealWindow(name: "Breakfast", openMinute: 7 * 60, closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch", openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 21 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Breakfast", openMinute: 7 * 60, closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch", openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 21 * 60)
            ]
        ),
        "51": DiningHallSchedule(
            hallId: "51",
            weekdayWindows: [
                MealWindow(name: "Breakfast", openMinute: 8 * 60, closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch", openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 22 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Breakfast", openMinute: 8 * 60, closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch", openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 19 * 60)
            ]
        ),
        "16": DiningHallSchedule(
            hallId: "16",
            weekdayWindows: [
                MealWindow(name: "Breakfast", openMinute: 7 * 60, closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch", openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 21 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Breakfast", openMinute: 7 * 60, closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch", openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 21 * 60)
            ]
        )
    ]
}
