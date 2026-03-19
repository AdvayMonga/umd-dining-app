import SwiftUI

struct ProfileView: View {
    @State private var preferences = UserPreferences.shared
    @Environment(FavoritesManager.self) private var favorites

    private let allergenOptions = [
        "Contains dairy",
        "Contains egg",
        "Contains gluten",
        "Contains soy"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Dietary Preferences") {
                    Toggle("Vegetarian", isOn: $preferences.vegetarian)
                    Toggle("Vegan", isOn: $preferences.vegan)
                }

                Section("Allergens to Avoid") {
                    ForEach(allergenOptions, id: \.self) { allergen in
                        Toggle(allergen.replacingOccurrences(of: "Contains ", with: ""),
                               isOn: Binding(
                                get: { preferences.allergens.contains(allergen) },
                                set: { isOn in
                                    if isOn {
                                        preferences.allergens.insert(allergen)
                                    } else {
                                        preferences.allergens.remove(allergen)
                                    }
                                }
                               ))
                    }
                }

                Section("Favorites") {
                    if favorites.favoriteFoods.isEmpty {
                        Text("No favorite foods yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(favorites.favoriteFoods.values).sorted(), id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
        .environment(FavoritesManager.shared)
}
