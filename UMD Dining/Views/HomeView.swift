import SwiftData
import SwiftUI

struct HomeView: View {
    @Binding var tabSelection: Int
    let myTab: Int
    @State private var viewModel = HomeViewModel()
    @State private var showSearch = false
    @State private var showFilter = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
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
            .onChange(of: tabSelection) {
                if tabSelection == myTab {
                    navPath = NavigationPath()
                    showSearch = false
                    showFilter = false
                    withAnimation { scrollProxy?.scrollTo("top", anchor: .top) }
                }
            }
            .onChange(of: viewModel.selectedMealPeriod) {
                withAnimation { scrollProxy?.scrollTo("top", anchor: .top) }
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

            CalendarCardButton(selection: $viewModel.selectedDate)

            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(Color.umdRed)
                    .frame(width: 44, height: 44)
            }

            Button { showFilter = true } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.title2)
                    .foregroundStyle(Color.umdRed)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .sheet(isPresented: $showFilter, onDismiss: {
            Task { await viewModel.loadMenus() }
        }) {
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
            SearchOverlay(
                menuItems: viewModel.allItems,
                hallNames: viewModel.diningHallNames,
                selectedDate: viewModel.selectedDate,
                selectedMealPeriod: viewModel.selectedMealPeriod
            )
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        Color.clear.frame(height: 0).id("top")
                        ForEach(viewModel.displayRows) { row in
                        switch row {
                        case .stationHeader(let station, let hallId, _):
                            StationHeaderRow(
                                station: station,
                                diningHallName: viewModel.diningHallName(for: hallId),
                                diningHallId: hallId,
                                items: viewModel.itemsForStation(station: station, hallId: hallId),
                                selectedDate: viewModel.selectedDate,
                                selectedMealPeriod: viewModel.selectedMealPeriod
                            )
                        case .seeMore:
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    viewModel.showDiscovery = true
                                }
                            } label: {
                                Text("See More Stations")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.umdRed)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                    .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        case .menuItem(let item):
                            NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name, station: item.station, diningHallName: viewModel.diningHallName(for: item.diningHallId), source: "home")) {
                                FoodItemRow(
                                    item: item,
                                    diningHallName: viewModel.diningHallName(for: item.diningHallId)
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .refreshable {
                    await viewModel.forceReloadMenus()
                }
                .onAppear { scrollProxy = proxy }
            }
        }
    }
}

#Preview {
    HomeView(tabSelection: .constant(0), myTab: 0)
        .environment(FavoritesManager.shared)
        .environment(NutritionTrackerManager.shared)
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}
