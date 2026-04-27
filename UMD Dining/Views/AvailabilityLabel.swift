import SwiftUI

struct AvailabilityLabel: View {
    let availability: AvailabilityInfo?
    var fallbackStation: String = ""
    var fallbackDiningHallName: String = ""
    var font: Font = .caption
    var iconFont: Font = .caption2
    var forceColor: Color? = nil

    private var text: String {
        if let a = availability {
            return a.displayLabel
        }
        let parts = [fallbackStation, fallbackDiningHallName].filter { !$0.isEmpty }
        if parts.isEmpty { return "Unavailable today" }
        return parts.joined(separator: " · ")
    }

    private var icon: String {
        if let a = availability {
            if a.availableToday { return "mappin.and.ellipse" }
            if a.unavailableThisWeek { return "xmark.circle" }
            return "calendar"
        }
        return "mappin.and.ellipse"
    }

    private var color: Color {
        if let forceColor { return forceColor }
        if let a = availability {
            if a.availableToday { return Color.umdRed }
            if a.unavailableThisWeek { return .secondary }
            return .secondary
        }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(iconFont)
            Text(text)
                .font(font)
        }
        .foregroundStyle(color)
    }
}
