import SwiftUI

struct FoodItemRow: View {
    let item: MenuItem
    let diningHallName: String
    @Environment(FavoritesManager.self) private var favorites

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text("\(item.station) · \(diningHallName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        favorites.toggleStation(name: item.station)
                    } label: {
                        Image(systemName: favorites.isFavoriteStation(item.station) ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(favorites.isFavoriteStation(item.station) ? .yellow : .gray.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                if !item.dietaryIcons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.dietaryIcons, id: \.self) { icon in
                            Text(shortLabel(for: icon))
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color(for: icon).opacity(0.15))
                                .foregroundStyle(color(for: icon))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            Button {
                favorites.toggleFood(recNum: item.recNum, name: item.name)
            } label: {
                Image(systemName: favorites.isFavorite(recNum: item.recNum) ? "heart.fill" : "heart")
                    .foregroundStyle(favorites.isFavorite(recNum: item.recNum) ? .red : .gray)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
    }

    private func shortLabel(for icon: String) -> String {
        switch icon {
        case "vegan": return "V"
        case "vegetarian": return "VG"
        case "Contains dairy": return "Dairy"
        case "Contains egg": return "Egg"
        case "Contains gluten": return "Gluten"
        case "Contains soy": return "Soy"
        default: return icon
        }
    }

    private func color(for icon: String) -> Color {
        switch icon {
        case "vegan", "vegetarian": return .green
        default: return .orange
        }
    }
}

#Preview {
    FoodItemRow(
        item: MenuItem(
            name: "Grilled Chicken Breast",
            recNum: "12345",
            diningHallId: "19",
            date: "3/18/2026",
            mealPeriod: "Lunch",
            station: "Grill",
            dietaryIcons: ["vegetarian", "Contains dairy"],
            nutritionFetched: false,
            allergens: nil,
            ingredients: nil,
            nutrition: nil
        ),
        diningHallName: "Yahentamitsi Dining Hall"
    )
    .environment(FavoritesManager.shared)
}
