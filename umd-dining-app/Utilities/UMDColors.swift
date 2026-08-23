import SwiftUI
import UIKit

// MARK: - Brand Colors

extension Color {
    static let umdRed        = Color(red: 226/255, green: 24/255,  blue: 51/255)   // #E21833
    static let umdRedActive  = Color(red: 185/255, green: 28/255,  blue: 28/255)   // #B91C1C
    static let umdGold       = Color(red: 255/255, green: 210/255, blue: 0/255)    // #FFD200

    // Adaptive: #F9FAFB in light, system dark grouped background in dark
    static let umdBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.systemGroupedBackground
            : UIColor(red: 249/255, green: 250/255, blue: 251/255, alpha: 1)
    })

    // Adaptive: #F3F4F6 in light, secondary system background in dark
    static let umdSurface = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.secondarySystemBackground
            : UIColor(red: 243/255, green: 244/255, blue: 246/255, alpha: 1)
    })

    // Adaptive border
    static let umdBorder = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.systemGray4
            : UIColor(red: 229/255, green: 231/255, blue: 235/255, alpha: 1)
    })
}

// MARK: - CalendarCardButton (used in StationPageView and TrackerView)

struct CalendarCardButton: View {
    @Binding var selection: Date

    private var displayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selection)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.subheadline)
                .foregroundStyle(Color.umdRed)
            Text(displayText)
                .font(.custom("Inter18pt-SemiBold", size: 15))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .gray.opacity(0.12), radius: 3, x: 0, y: 1)
        .overlay {
            DatePicker("", selection: $selection, displayedComponents: .date)
                .labelsHidden()
                .tint(Color.umdRed)
                .colorMultiply(.clear)
        }
    }
}
