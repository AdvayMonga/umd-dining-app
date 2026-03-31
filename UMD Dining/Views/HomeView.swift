import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var showSearch = false
    @State private var showFilter = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                mealPicker
                content
            }
            .background(Color(.systemGroupedBackground))
            .task {
                viewModel.autoSelectMealPeriod()
                await viewModel.loadMenus()
            }
            .onChange(of: viewModel.selectedDate) {
                Task { await viewModel.loadMenus() }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("UMD Dining")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.umdRed)

            Spacer()

            DatePicker("", selection: $viewModel.selectedDate, displayedComponents: .date)
                .labelsHidden()

            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Color.umdRed)
            }

            Button { showFilter = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.title3)
                    .foregroundStyle(Color.umdRed)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showFilter) {
            FilterOverlay(
                selectedHallIds: $viewModel.selectedHallIds,
                hallNames: viewModel.diningHallNames,
                allHallIds: viewModel.allHallIds,
                filterVegetarian: $viewModel.filterVegetarian,
                filterVegan: $viewModel.filterVegan,
                filterHighProtein: $viewModel.filterHighProtein,
                filterAllergens: $viewModel.filterAllergens
            )
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchOverlay()
        }
    }

    private var mealPicker: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.availableMealPeriods, id: \.self) { period in
                let isSelected = viewModel.selectedMealPeriod == period
                Button {
                    viewModel.selectedMealPeriod = period
                } label: {
                    Text(period)
                        .font(.body)
                        .fontWeight(isSelected ? .bold : .regular)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(isSelected ? Color(.systemBackground) : Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: isSelected ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView("Loading menus...")
            Spacer()
        } else if let error = viewModel.errorMessage {
            Spacer()
            ContentUnavailableView {
                Label("Error", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.loadMenus() }
                }
            }
            Spacer()
        } else if viewModel.displayRows.isEmpty {
            Spacer()
            ContentUnavailableView(
                "No Items",
                systemImage: "fork.knife",
                description: Text("No menu items available for this meal period.")
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.displayRows) { row in
                        switch row {
                        case .stationHeader(let station, let hallId, let isDiscovery):
                            StationHeaderRow(
                                station: station,
                                diningHallName: viewModel.diningHallName(for: hallId),
                                isExpanded: viewModel.isStationExpanded(station: station, hallId: hallId, isDiscovery: isDiscovery),
                                isDiscovery: isDiscovery,
                                onToggle: { viewModel.toggleStationExpansion(station: station, hallId: hallId, isDiscovery: isDiscovery) }
                            )
                        case .seeMore:
                            Button {
                                viewModel.showDiscovery = true
                            } label: {
                                Text("See More Stations")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.umdRed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        case .menuItem(let item):
                            NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name, station: item.station, diningHallName: viewModel.diningHallName(for: item.diningHallId))) {
                                FoodItemRow(
                                    item: item,
                                    diningHallName: viewModel.diningHallName(for: item.diningHallId)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .refreshable {
                await viewModel.loadMenus()
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(FavoritesManager.shared)
}
