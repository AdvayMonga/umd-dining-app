import SwiftUI

struct SearchOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FavoritesManager.self) private var favorites
    @State private var viewModel = SearchViewModel()
    var menuItems: [MenuItem] = []
    var hallNames: [String: String] = [:]
    var selectedDate: Date = .now
    var selectedMealPeriod: String = "Lunch"
    var onDismiss: (() -> Void)?
    @Namespace private var namespace
    @State private var showSearchFilter = false
    @FocusState private var isSearchFocused: Bool

    private var hasActiveFilters: Bool {
        viewModel.filterVegetarian || viewModel.filterVegan || viewModel.filterHalal || !viewModel.filterAllergens.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom search bar row
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search foods, stations...", text: $viewModel.query)
                            .focused($isSearchFocused)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onChange(of: viewModel.query) {
                                viewModel.search(menuItems: menuItems, hallNames: hallNames)
                            }
                        if !viewModel.query.isEmpty {
                            Button { viewModel.query = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button { showSearchFilter = true } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.title2)
                            .foregroundStyle(Color.umdRed)
                            .frame(width: 44, height: 44)
                            .overlay(alignment: .topTrailing) {
                                if !viewModel.filtersMatchDefaults {
                                    Circle()
                                        .fill(Color.umdRed)
                                        .frame(width: 8, height: 8)
                                        .offset(x: -4, y: 4)
                                }
                            }
                    }

                    Button {
                        if let onDismiss { onDismiss() } else { dismiss() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))

                // Active filter chips
                if hasActiveFilters {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if viewModel.filterVegetarian {
                                activeFilterChip("Vegetarian") {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        viewModel.filterVegetarian = false
                                    }
                                }
                            }
                            if viewModel.filterVegan {
                                activeFilterChip("Vegan") {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        viewModel.filterVegan = false
                                    }
                                }
                            }
                            if viewModel.filterHalal {
                                activeFilterChip("Halal") {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        viewModel.filterHalal = false
                                    }
                                }
                            }
                            ForEach(viewModel.filterAllergens.sorted(), id: \.self) { allergen in
                                activeFilterChip("No \(allergen.replacingOccurrences(of: "Contains ", with: "").capitalized)") {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        _ = viewModel.filterAllergens.remove(allergen)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.systemBackground))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider()

                // Content
                if viewModel.isLoading && viewModel.stationResults.isEmpty {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Spacer()
                    ContentUnavailableView {
                        Label("Search Failed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { viewModel.search(menuItems: menuItems, hallNames: hallNames) }
                    }
                    Spacer()
                } else if viewModel.hasSearched && viewModel.results.isEmpty && viewModel.stationResults.isEmpty {
                    ScrollView {
                        VStack(spacing: 20) {
                            Spacer().frame(height: 40)
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Nothing matches \"\(viewModel.query)\"")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            let trending = menuItems.filter { $0.tags.contains("Trending") }.prefix(5)
                            if !trending.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Trending foods you might like")
                                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary).padding(.horizontal, 4)
                                    ForEach(Array(trending)) { item in
                                        NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name, station: item.station, diningHallName: hallNames[item.diningHallId] ?? "", source: "search")) {
                                            HStack {
                                                Text(item.name).font(.body).fontWeight(.semibold).foregroundStyle(.primary)
                                                Spacer()
                                                Text(item.station).font(.caption).foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 12).padding(.horizontal, 16)
                                            .background(Color(.systemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                } else if !viewModel.hasSearched && viewModel.stationResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Recent searches — only shown when non-empty
                            if !viewModel.recentSearches.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Recent Searches").font(.headline).foregroundStyle(.primary)
                                        Spacer()
                                        Button { viewModel.clearRecentSearches() } label: {
                                            Text("Clear All").font(.subheadline).foregroundStyle(Color.umdRed)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    FlowLayout(spacing: 10) {
                                        ForEach(viewModel.recentSearches, id: \.self) { recent in
                                            Button {
                                                viewModel.query = recent
                                                viewModel.search(menuItems: menuItems, hallNames: hallNames)
                                            } label: {
                                                Text(recent).font(.subheadline)
                                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                                    .background(Color(.systemBackground))
                                                    .clipShape(Capsule())
                                                    .overlay(Capsule().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                            }

                            // Trending searches — always shown independently
                            if !viewModel.trendingSearches.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Trending Searches").font(.headline).foregroundStyle(.primary).padding(.horizontal, 4)
                                    FlowLayout(spacing: 10) {
                                        ForEach(viewModel.trendingSearches, id: \.self) { trending in
                                            Button {
                                                viewModel.query = trending
                                                viewModel.search(menuItems: menuItems, hallNames: hallNames)
                                            } label: {
                                                Text(trending).font(.subheadline)
                                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                                    .background(Color(.systemBackground))
                                                    .clipShape(Capsule())
                                                    .overlay(Capsule().stroke(Color.umdRed.opacity(0.3), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                            }

                            // Empty placeholder only when both are empty
                            if viewModel.recentSearches.isEmpty && viewModel.trendingSearches.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                                    Text("Search for foods and stations").foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                            }
                        }
                        .padding(.top, 12)
                    }
                    .background(Color(.systemGroupedBackground))
                    .task { await viewModel.loadTrendingSearches() }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if !viewModel.stationResults.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Stations")
                                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary).padding(.horizontal, 4)
                                    ForEach(viewModel.stationResults) { station in
                                        let stationId = "\(station.station)-\(station.diningHallId)"
                                        NavigationLink {
                                            StationPageView(
                                                station: station.station,
                                                diningHallId: station.diningHallId,
                                                diningHallName: station.diningHallName,
                                                initialItems: station.items,
                                                initialDate: selectedDate,
                                                initialMealPeriod: selectedMealPeriod
                                            )
                                            .navigationTransition(.zoom(sourceID: stationId, in: namespace))
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(station.station).font(.subheadline).fontWeight(.semibold).foregroundStyle(.primary)
                                                    Text(station.diningHallName).font(.caption).foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text("\(station.items.count) items").font(.caption).foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 12).padding(.horizontal, 16)
                                            .background(Color(.systemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                            .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
                                        }
                                        .matchedTransitionSource(id: stationId, in: namespace)
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if !viewModel.results.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Foods")
                                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary).padding(.horizontal, 4)
                                    ForEach(viewModel.results) { item in
                                        NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name, station: item.station.isEmpty ? nil : item.station, diningHallName: item.diningHallName.isEmpty ? nil : item.diningHallName, source: "search")
                                            .navigationTransition(.zoom(sourceID: "search-\(item.recNum)", in: namespace))
                                        ) {
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.name).font(.body).fontWeight(.semibold).foregroundStyle(.primary)
                                                    if !item.station.isEmpty || !item.diningHallName.isEmpty {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "mappin.and.ellipse").font(.caption).foregroundStyle(Color.umdRed)
                                                            Text([item.station, item.diningHallName].filter { !$0.isEmpty }.joined(separator: " · "))
                                                                .font(.caption).foregroundStyle(.secondary)
                                                        }
                                                    } else {
                                                        Text("Unavailable today").font(.caption).foregroundStyle(.secondary)
                                                    }
                                                }
                                                Spacer()
                                                Button {
                                                    favorites.toggleFood(recNum: item.recNum, name: item.name)
                                                } label: {
                                                    Image(systemName: favorites.isFavorite(recNum: item.recNum) ? "heart.fill" : "heart")
                                                        .foregroundStyle(favorites.isFavorite(recNum: item.recNum) ? .red : .gray)
                                                        .font(.title3)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.vertical, 12).padding(.horizontal, 16)
                                            .background(Color(.systemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                            .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
                                        }
                                        .matchedTransitionSource(id: "search-\(item.recNum)", in: namespace)
                                        .buttonStyle(.plain)
                                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.results.map(\.id))
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSearchFilter) {
                FilterOverlay(
                    selectedHallIds: .constant([]),
                    hallNames: [:],
                    allHallIds: [],
                    filterVegetarian: $viewModel.filterVegetarian,
                    filterVegan: $viewModel.filterVegan,
                    filterHalal: $viewModel.filterHalal,
                    filterHighProtein: .constant(false),
                    filterAllergens: $viewModel.filterAllergens,
                    showDiningHalls: false,
                    onDismiss: { showSearchFilter = false }
                )
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            isSearchFocused = true
        }
    }

    private func activeFilterChip(_ label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.umdRed)
        .clipShape(Capsule())
        .sensoryFeedback(.selection, trigger: label)
    }
}

#Preview {
    SearchOverlay()
        .environment(FavoritesManager.shared)
}
