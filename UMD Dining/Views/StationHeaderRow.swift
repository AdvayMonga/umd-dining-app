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
    var onTap: (() -> Void)? = nil
    @State private var showHeartAnimation = false

    private var stationId: String { "\(station)-\(diningHallId)" }

    var body: some View {
        HStack(spacing: 0) {
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
        .overlay {
            if showHeartAnimation {
                Image(systemName: "heart.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.umdRed.opacity(0.85))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            favorites.toggleStation(name: station)
            withAnimation(.spring(duration: 0.35)) { showHeartAnimation = true }
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeOut(duration: 0.25)) { showHeartAnimation = false }
            }
        }
        .onTapGesture(count: 1) {
            onTap?()
        }
        .matchedTransitionSource(id: stationId, in: namespace)
    }
}
