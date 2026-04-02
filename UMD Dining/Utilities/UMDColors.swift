import SwiftUI

extension Color {
    static let umdRed = Color(red: 226/255, green: 24/255, blue: 51/255)
    static let umdGold = Color(red: 255/255, green: 213/255, blue: 0/255)
}

/// A DatePicker disguised as a card-style button matching FoodItemRow aesthetic.
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
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
        .overlay {
            DatePicker("", selection: $selection, displayedComponents: .date)
                .labelsHidden()
                .tint(Color.umdRed)
                .colorMultiply(.clear)
        }
    }
}
