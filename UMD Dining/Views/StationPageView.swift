import SwiftUI

struct StationPageView: View {
    let station: String
    let diningHallId: String
    let diningHallName: String
    let initialItems: [MenuItem]
    let initialDate: Date
    let initialMealPeriod: String
    @Environment(FavoritesManager.self) private var favorites

    @State private var allItems: [MenuItem] = []
    @State private var selectedDate: Date = .now
    @State private var selectedMealPeriod: String = "Lunch"
    @State private var selectedItem: MenuItem?
    @Namespace private var namespace

    private let mealPeriodOrder = ["Breakfast", "Brunch", "Lunch", "Dinner"]

    private var availableMealPeriods: [String] {
        let periods = Set(allItems.map(\.mealPeriod))
        return mealPeriodOrder.filter { periods.contains($0) }
    }

    private var filteredItems: [MenuItem] {
        allItems.filter { $0.mealPeriod == selectedMealPeriod }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date picker + location
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(Color.umdRed)
                        Text(diningHallName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                CalendarCardButton(selection: $selectedDate)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Meal period picker
            HStack(spacing: 8) {
                ForEach(availableMealPeriods, id: \.self) { period in
                    let isSelected = selectedMealPeriod == period
                    Button {
                        selectedMealPeriod = period
                    } label: {
                        Text(period)
                            .font(.body)
                            .fontWeight(isSelected ? .bold : .regular)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(isSelected ? Color(.systemBackground) : Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(.systemGray4), lineWidth: isSelected ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            // Food items
            if filteredItems.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Items",
                    systemImage: "fork.knife",
                    description: Text("This station has no items for \(selectedMealPeriod).")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            FoodItemRow(
                                item: item,
                                diningHallName: diningHallName,
                                onTap: { selectedItem = item }
                            )
                            .matchedTransitionSource(id: item.recNum, in: namespace)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(item: $selectedItem) { item in
            NutritionDetailView(recNum: item.recNum, foodName: item.name, station: item.station, diningHallName: diningHallName, source: "station")
                .navigationTransition(.zoom(sourceID: item.recNum, in: namespace))
        }
        .navigationTitle(station)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    favorites.toggleStation(name: station)
                } label: {
                    Image(systemName: favorites.isFavoriteStation(station) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.isFavoriteStation(station) ? Color.umdRed : .gray)
                }
            }
        }
        .task {
            selectedDate = initialDate
            selectedMealPeriod = initialMealPeriod
            await loadItems()
        }
        .onChange(of: selectedDate) {
            Task { await loadItems() }
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        return f.string(from: selectedDate)
    }

    private func loadItems() async {
        do {
            let menuItems = try await DiningAPIService.shared.fetchMenu(
                date: dateString,
                diningHallId: diningHallId
            )
            allItems = menuItems.filter { $0.station == station }
            if !availableMealPeriods.contains(selectedMealPeriod),
               let first = availableMealPeriods.first {
                selectedMealPeriod = first
            }
        } catch {
            // Keep current items on error
        }
    }
}
