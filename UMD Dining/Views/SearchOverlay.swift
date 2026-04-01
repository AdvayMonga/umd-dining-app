import SwiftUI

struct SearchOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FavoritesManager.self) private var favorites
    @State private var viewModel = SearchViewModel()
    var menuItems: [MenuItem] = []
    var hallNames: [String: String] = [:]
    var selectedDate: Date = .now
    var selectedMealPeriod: String = "Lunch"

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
                    Spacer()
                    ContentUnavailableView.search(text: viewModel.query)
                    Spacer()
                } else if !viewModel.hasSearched && viewModel.stationResults.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Search for foods and stations")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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
                                        NavigationLink {
                                            StationPageView(
                                                station: station.station,
                                                diningHallId: station.diningHallId,
                                                diningHallName: station.diningHallName,
                                                initialItems: station.items,
                                                initialDate: selectedDate,
                                                initialMealPeriod: selectedMealPeriod
                                            )
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
                                        NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name)) {
                                            HStack(spacing: 12) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.name)
                                                        .font(.body)
                                                        .fontWeight(.semibold)
                                                        .foregroundStyle(.primary)

                                                    if !item.allergens.isEmpty {
                                                        Text(item.allergens)
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
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SearchOverlay()
        .environment(FavoritesManager.shared)
}
