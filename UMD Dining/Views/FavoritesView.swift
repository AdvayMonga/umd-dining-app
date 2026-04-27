import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesManager.self) private var favorites
    @State private var searchText = ""
    @State private var availability: [String: AvailabilityInfo] = [:]
    @State private var lastFetchedRecNums: Set<String> = []

    private var filteredFoods: [(recNum: String, name: String)] {
        let sorted = favorites.sortedFoods
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredStations: [String] {
        let sorted = favorites.sortedStations
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if favorites.favoriteFoods.isEmpty && favorites.favoriteStations.isEmpty {
                ContentUnavailableView(
                    "No Favorites",
                    systemImage: "heart",
                    description: Text("Foods and stations you favorite will appear here.")
                )
            } else if filteredFoods.isEmpty && filteredStations.isEmpty && !searchText.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("No favorites matching \"\(searchText)\"")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !filteredFoods.isEmpty {
                            sectionHeader("Foods")
                            ForEach(filteredFoods, id: \.recNum) { recNum, name in
                                NavigationLink(destination: NutritionDetailView(recNum: recNum, foodName: name, source: "favorites")) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(name)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            if let info = availability[recNum] {
                                                AvailabilityLabel(availability: info)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        favorites.toggleFood(recNum: recNum, name: name)
                                    } label: {
                                        Label("Remove", systemImage: "heart.slash")
                                    }
                                }
                            }
                        }

                        if !filteredStations.isEmpty {
                            sectionHeader("Stations")
                                .padding(.top, filteredFoods.isEmpty ? 0 : 8)
                            ForEach(filteredStations, id: \.self) { station in
                                HStack {
                                    Text(station)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        favorites.toggleStation(name: station)
                                    } label: {
                                        Label("Remove", systemImage: "heart.slash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Favorites")
        .searchable(text: $searchText, prompt: "Search favorites")
        .task(id: favorites.sortedFoods.map { $0.recNum }) {
            await loadAvailability()
        }
    }

    private func loadAvailability() async {
        let recNums = Set(favorites.sortedFoods.map { $0.recNum })
        guard !recNums.isEmpty else {
            availability = [:]
            lastFetchedRecNums = []
            return
        }
        if recNums == lastFetchedRecNums { return }
        do {
            let result = try await DiningAPIService.shared.fetchAvailability(recNums: Array(recNums))
            availability = result
            lastFetchedRecNums = recNums
        } catch {
            // silent fail — leaves rows without label
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        FavoritesView()
            .environment(FavoritesManager.shared)
    }
}
