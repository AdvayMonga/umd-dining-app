import SwiftUI

struct StationHeaderRow: View {
    let station: String
    let diningHallName: String
    let diningHallId: String
    let items: [MenuItem]
    let selectedDate: Date
    let selectedMealPeriod: String
    @Environment(FavoritesManager.self) private var favorites

    var body: some View {
        HStack(spacing: 0) {
            // Station name → navigates to StationPageView
            NavigationLink {
                StationPageView(
                    station: station,
                    diningHallId: diningHallId,
                    diningHallName: diningHallName,
                    initialItems: items,
                    initialDate: selectedDate,
                    initialMealPeriod: selectedMealPeriod
                )
            } label: {
                HStack(spacing: 6) {
                    Text(station)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                    Text("·")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(diningHallName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Right: heart button
            Button {
                favorites.toggleStation(name: station)
            } label: {
                Image(systemName: favorites.isFavoriteStation(station) ? "heart.fill" : "heart")
                    .foregroundStyle(.white)
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .background(Color.umdRed)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
