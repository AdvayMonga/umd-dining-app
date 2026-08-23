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
    let weekdayWindows: [MealWindow]             // Mon–Thu
    let fridayWindows: [MealWindow]?             // Fri only; nil = same as weekday
    let weekendWindows: [MealWindow]             // Sat–Sun

    init(hallId: String, weekdayWindows: [MealWindow], fridayWindows: [MealWindow]? = nil, weekendWindows: [MealWindow]) {
        self.hallId = hallId
        self.weekdayWindows = weekdayWindows
        self.fridayWindows = fridayWindows
        self.weekendWindows = weekendWindows
    }

    struct Status {
        let isOpen: Bool
        let isClosingSoon: Bool   // last meal of the day, closes within 30 min
        let currentMeal: String?
        let closeTime: String?    // current meal's close (unused in UI but kept for flexibility)
        let dayCloseTime: String? // last meal's close = when the hall closes for the day
        let nextMeal: String?
        let nextOpenTime: String?

        static let closed = Status(isOpen: false, isClosingSoon: false, currentMeal: nil, closeTime: nil, dayCloseTime: nil, nextMeal: nil, nextOpenTime: nil)
    }

    func currentStatus(at date: Date = .now) -> Status {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)  // 1=Sun, 6=Fri, 7=Sat
        let isWeekend = weekday == 1 || weekday == 7
        let isFriday = weekday == 6
        let windows = isWeekend ? weekendWindows : (isFriday ? (fridayWindows ?? weekdayWindows) : weekdayWindows)
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let minute = h * 60 + m

        let dayCloseTime = windows.last?.closeTimeString

        for (i, window) in windows.enumerated() {
            if window.contains(minute: minute) {
                let isLastMeal = i == windows.count - 1
                let isClosingSoon = isLastMeal && (window.closeMinute - minute) <= 30
                return Status(
                    isOpen: true,
                    isClosingSoon: isClosingSoon,
                    currentMeal: window.name,
                    closeTime: window.closeTimeString,
                    dayCloseTime: dayCloseTime,
                    nextMeal: nil,
                    nextOpenTime: nil
                )
            }
        }
        for window in windows where window.openMinute > minute {
            return Status(isOpen: false, isClosingSoon: false, currentMeal: nil, closeTime: nil, dayCloseTime: dayCloseTime, nextMeal: window.name, nextOpenTime: window.openTimeString)
        }
        return .closed
    }

    // Hardcoded hours — week of 4/27–5/3 (verify each semester against UMD Dining schedule)
    static let all: [String: DiningHallSchedule] = [
        "19": DiningHallSchedule(
            hallId: "19",
            weekdayWindows: [
                MealWindow(name: "Breakfast", openMinute: 7 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 21 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Brunch", openMinute: 10 * 60, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 21 * 60)
            ]
        ),
        "51": DiningHallSchedule(
            hallId: "51",
            weekdayWindows: [                                            // Mon–Thu
                MealWindow(name: "Breakfast", openMinute: 8 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 22 * 60)
            ],
            fridayWindows: [                                             // Fri dinner ends at 7
                MealWindow(name: "Breakfast", openMinute: 8 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 19 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Breakfast", openMinute: 8 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 19 * 60)
            ]
        ),
        "16": DiningHallSchedule(
            hallId: "16",
            weekdayWindows: [
                MealWindow(name: "Breakfast", openMinute: 7 * 60,       closeMinute: 10 * 60 + 30),
                MealWindow(name: "Lunch",     openMinute: 10 * 60 + 30, closeMinute: 16 * 60),
                MealWindow(name: "Dinner",    openMinute: 16 * 60,      closeMinute: 21 * 60)
            ],
            weekendWindows: [
                MealWindow(name: "Brunch", openMinute: 10 * 60, closeMinute: 16 * 60),
                MealWindow(name: "Dinner", openMinute: 16 * 60, closeMinute: 21 * 60)
            ]
        )
    ]
}
