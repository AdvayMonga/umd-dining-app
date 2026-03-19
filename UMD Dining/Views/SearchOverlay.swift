import SwiftUI

struct SearchOverlay: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FavoritesManager.self) private var favorites
    @State private var viewModel = SearchViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                } else if viewModel.hasSearched && viewModel.results.isEmpty {
                    Spacer()
                    ContentUnavailableView.search(text: viewModel.query)
                    Spacer()
                } else if viewModel.results.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Search for foods across all dining halls")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List(viewModel.results) { item in
                        NavigationLink(destination: NutritionDetailView(recNum: item.recNum, foodName: item.name)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .fontWeight(.semibold)
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
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "Search foods, stations...")
            .onChange(of: viewModel.query) {
                viewModel.search()
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
