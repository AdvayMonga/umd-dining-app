import SwiftUI

struct DiningHallPickerView: View {
    let userName: String?
    let selectedHallId: String?
    let onSelect: (String) -> Void

    private let halls: [(id: String, name: String, imageAlignment: Alignment)] = [
        ("19", "Yahentamitsi",      .center),
        ("51", "251 North",         .top),
        ("16", "South Campus Diner", .center)
    ]

    private var displayName: String {
        guard let name = userName, !name.isEmpty else { return "Terp" }
        return name.components(separatedBy: " ").first ?? name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Greeting — shown on launch picker only
            if userName != nil {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WELCOME BACK, \(displayName.uppercased())!")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .tracking(0.5)
                    Text("Hungry today?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }

            // Section label + View Hours link
            HStack {
                Text("Dining Halls")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Link("View Hours", destination: URL(string: "https://dining.umd.edu/hours-locations/dining-halls")!)
                    .font(.subheadline)
                    .foregroundStyle(Color.umdRed)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Cards — fill remaining space, no scroll needed
            VStack(spacing: 8) {
                ForEach(halls, id: \.id) { hall in
                    DiningHallCard(
                        hallId: hall.id,
                        hallName: hall.name,
                        imageAlignment: hall.imageAlignment,
                        onTap: { onSelect(hall.id) }
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .frame(maxHeight: .infinity)
        }
        // Stretch to full screen; background fills behind safe areas
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

struct DiningHallCard: View {
    let hallId: String
    let hallName: String
    let imageAlignment: Alignment
    let onTap: () -> Void

    private var status: DiningHallSchedule.Status {
        DiningHallSchedule.all[hallId]?.currentStatus() ?? .closed
    }

    private var statusText: String {
        if status.isOpen, let close = status.dayCloseTime, let meal = status.currentMeal {
            return "Open until \(close) · \(meal)"
        } else if let nextTime = status.nextOpenTime {
            return "Opens at \(nextTime)"
        } else {
            return "Closed today"
        }
    }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                ZStack {
                    Color(.systemGray4)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(alignment: imageAlignment) {
                            Image("hall_\(hallId)")
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width)
                        }
                        .clipped()

                    // Gradient scrim at bottom for text legibility
                    VStack(spacing: 0) {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: min(geo.size.height * 0.55, 90))
                    }

                    // Top-right: OPEN / CLOSING SOON / CLOSED badge
                    VStack {
                        HStack {
                            Spacer()
                            Text(status.isClosingSoon ? "CLOSING SOON" : status.isOpen ? "OPEN" : "CLOSED")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(status.isClosingSoon ? Color.orange : status.isOpen ? Color.green : Color.red.opacity(0.9))
                                .clipShape(Capsule())
                        }
                        .padding(10)
                        Spacer()
                    }

                    // Bottom-left: status hours ABOVE hall name
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(statusText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white.opacity(0.88))
                                Text(hallName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DiningHallPickerView(
        userName: "Tory",
        selectedHallId: nil,
        onSelect: { _ in }
    )
}
