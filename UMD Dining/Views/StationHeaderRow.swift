import SwiftUI

struct StationHeaderRow: View {
    let station: String
    let diningHallName: String
    let isExpanded: Bool
    let isDiscovery: Bool
    let onToggle: () -> Void
    @Environment(FavoritesManager.self) private var favorites

    var body: some View {
        HStack {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .foregroundStyle(.white.opacity(0.85))
                .font(.caption.weight(.semibold))
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
        .padding(.horizontal, 14)
        .background(Color.umdRed)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }
}
