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
                allHallIds: viewModel.allHallIds
            )
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchOverlay()
        }
    }

    private var mealPicker: some View {
        Picker("Meal", selection: $viewModel.selectedMealPeriod) {
            ForEach(viewModel.availableMealPeriods, id: \.self) { period in
                Text(period).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
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
        } else if viewModel.displayItems.isEmpty {
            Spacer()
            ContentUnavailableView(
                "No Items",
                systemImage: "fork.knife",
                description: Text("No menu items available for this meal period.")
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(viewModel.displayItems) { item in
                        NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name)) {
                            FoodItemRow(
                                item: item,
                                diningHallName: viewModel.diningHallName(for: item.diningHallId)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
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
