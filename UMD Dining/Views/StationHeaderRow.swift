import SwiftUI

struct StationHeaderRow: View {
    let station: String
    let diningHallName: String
    let diningHallId: String
    let items: [MenuItem]
    let selectedDate: Date
    let selectedMealPeriod: String
    var namespace: Namespace.ID
    var onTap: (() -> Void)? = nil

    private var stationId: String { "\(station)-\(diningHallId)" }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(station.uppercased())
                    .font(.inter(size: 17, weight: .bold))
                    .foregroundStyle(Color.umdRed)
                    .kerning(1.5)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 2) {
                    Text("View all")
                        .font(.inter(size: 11, weight: .medium))
                        .foregroundStyle(Color.umdRed.opacity(0.7))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.umdRed.opacity(0.7))
                }
            }
            .frame(height: 36)

            Rectangle()
                .fill(Color.umdRed.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.top, 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .matchedTransitionSource(id: stationId, in: namespace)
    }
}
