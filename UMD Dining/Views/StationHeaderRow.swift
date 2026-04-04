import SwiftUI

struct StationHeaderRow: View {
    let station: String
    let diningHallName: String
    let diningHallId: String
    let items: [MenuItem]
    let selectedDate: Date
    let selectedMealPeriod: String
    var namespace: Namespace.ID
    @Environment(FavoritesManager.self) private var favorites

    private var stationId: String { "\(station)-\(diningHallId)" }

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
                .navigationTransition(.zoom(sourceID: stationId, in: namespace))
            } label: {
                HStack(spacing: 6) {
                    Text(station)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.umdRed)
                    Text("·")
                        .font(.subheadline)
                        .foregroundStyle(Color.umdRed.opacity(0.5))
                    Text(diningHallName)
                        .font(.subheadline)
                        .foregroundStyle(Color.umdRed.opacity(0.75))
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
                    .foregroundStyle(Color.umdRed)
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .background(Color.umdRed.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.umdRed.opacity(0.3), lineWidth: 1))
        .matchedTransitionSource(id: stationId, in: namespace)
    }
}
