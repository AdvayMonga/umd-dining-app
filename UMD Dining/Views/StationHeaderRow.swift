import SwiftUI

struct StationHeaderRow: View {
    let station: String
    let diningHallName: String
    @Environment(FavoritesManager.self) private var favorites

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(station)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                Text(diningHallName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button {
                favorites.toggleStation(name: station)
            } label: {
                Image(systemName: favorites.isFavoriteStation(station) ? "heart.fill" : "heart")
                    .foregroundStyle(.white)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.umdRed)
    }
}
