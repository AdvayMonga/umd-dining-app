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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                    // No results — show trending fallback
                    ScrollView {
                        VStack(spacing: 20) {
                            Spacer().frame(height: 40)
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Nothing matches \"\(viewModel.query)\"")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            let trending = menuItems.filter { $0.tags.contains("Trending") }
                                .prefix(5)
                            if !trending.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Trending foods you might like")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)

                                    ForEach(Array(trending)) { item in
                                        NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name, station: item.station, diningHallName: hallNames[item.diningHallId] ?? "", source: "search")) {
                                            HStack {
                                                Text(item.name)
                                                    .font(.body)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                Text(item.station)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
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
                    // Blank state — show recent searches or placeholder
                    ScrollView {
                        VStack(spacing: 16) {
                            if viewModel.recentSearches.isEmpty {
                                Spacer().frame(height: 40)
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("Search for foods and stations")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Recent Searches")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Button {
                                            viewModel.clearRecentSearches()
                                        } label: {
                                            Text("Clear All")
                                                .font(.subheadline)
                                                .foregroundStyle(Color.umdRed)
                                        }
                                    }
                                    .padding(.horizontal, 4)

                                    FlowLayout(spacing: 10) {
                                        ForEach(viewModel.recentSearches, id: \.self) { recent in
                                            Button {
                                                viewModel.query = recent
                                                viewModel.search(menuItems: menuItems, hallNames: hallNames)
                                            } label: {
                                                Text(recent)
                                                    .font(.subheadline)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                                    .background(Color(.systemBackground))
                                                    .clipShape(Capsule())
                                                    .overlay(Capsule().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)

                                // Trending searches
                                if !viewModel.trendingSearches.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Trending Searches")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 4)

                                        FlowLayout(spacing: 10) {
                                            ForEach(viewModel.trendingSearches, id: \.self) { trending in
                                                Button {
                                                    viewModel.query = trending
                                                    viewModel.search(menuItems: menuItems, hallNames: hallNames)
                                                } label: {
                                                    Text(trending)
                                                        .font(.subheadline)
                                                        .padding(.horizontal, 14)
                                                        .padding(.vertical, 8)
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
                            }
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                    .task {
                        await viewModel.loadTrendingSearches()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            // Station results
                            if !viewModel.stationResults.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Stations")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)

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
                                                    Text(station.station)
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(.primary)
                                                    Text(station.diningHallName)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text("\(station.items.count) items")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
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

                            // Food results
                            if !viewModel.results.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Foods")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)

                                    ForEach(viewModel.results) { item in
                                        NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name, station: item.station.isEmpty ? nil : item.station, diningHallName: item.diningHallName.isEmpty ? nil : item.diningHallName, source: "search")
                                            .navigationTransition(.zoom(sourceID: "search-\(item.recNum)", in: namespace))
                                        ) {
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.name)
                                                        .font(.body)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(.primary)

                                                    if !item.station.isEmpty || !item.diningHallName.isEmpty {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "mappin.and.ellipse")
                                                                .font(.caption)
                                                                .foregroundStyle(Color.umdRed)
                                                            Text([item.station, item.diningHallName].filter { !$0.isEmpty }.joined(separator: " · "))
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                    } else {
                                                        Text("Unavailable today")
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
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
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .background(Color(.systemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                            .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
                                        }
                                        .matchedTransitionSource(id: "search-\(item.recNum)", in: namespace)
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "Search foods, stations...")
            .onChange(of: viewModel.query) {
                viewModel.search(menuItems: menuItems, hallNames: hallNames)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if let onDismiss { onDismiss() } else { dismiss() }
                    }
                }
            }
        }
    }
}

#Preview {
    SearchOverlay()
        .environment(FavoritesManager.shared)
}
