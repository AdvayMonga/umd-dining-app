import SwiftUI

struct FilterOverlay: View {
    @Binding var selectedHallIds: Set<String>
    let hallNames: [String: String]
    let allHallIds: [String]

    @Binding var filterVegetarian: Bool
    @Binding var filterVegan: Bool
    @Binding var filterHighProtein: Bool
    @Binding var filterAllergens: Set<String>

    @Environment(\.dismiss) private var dismiss

    private let allergenOptions = [
        "Contains dairy",
        "Contains egg",
        "Contains gluten",
        "Contains soy"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Dining Halls") {
                    ForEach(allHallIds, id: \.self) { hallId in
                        let name = hallNames[hallId] ?? hallId
                        Toggle(name, isOn: Binding(
                            get: { selectedHallIds.contains(hallId) },
                            set: { isOn in
                                if isOn {
                                    selectedHallIds.insert(hallId)
                                } else if selectedHallIds.count > 1 {
                                    selectedHallIds.remove(hallId)
                                }
                            }
                        ))
                    }

                    Button("Select All") {
                        selectedHallIds = Set(allHallIds)
                    }
                }

                Section("Dietary Preferences") {
                    Toggle("Vegetarian", isOn: $filterVegetarian)
                    Toggle("Vegan", isOn: $filterVegan)
                    Toggle("High Protein (20g+)", isOn: $filterHighProtein)
                }

                Section("Allergens to Avoid") {
                    ForEach(allergenOptions, id: \.self) { allergen in
                        Toggle(allergen.replacingOccurrences(of: "Contains ", with: ""),
                               isOn: Binding(
                                get: { filterAllergens.contains(allergen) },
                                set: { isOn in
                                    if isOn {
                                        filterAllergens.insert(allergen)
                                    } else {
                                        filterAllergens.remove(allergen)
                                    }
                                }
                               ))
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    FilterOverlay(
        selectedHallIds: .constant(Set(["19", "51", "16"])),
        hallNames: ["19": "Yahentamitsi", "51": "251 North", "16": "South Campus Diner"],
        allHallIds: ["19", "51", "16"],
        filterVegetarian: .constant(false),
        filterVegan: .constant(false),
        filterHighProtein: .constant(false),
        filterAllergens: .constant([])
    )
}
