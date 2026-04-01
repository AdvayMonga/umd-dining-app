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
        "Contains fish",
        "Contains gluten",
        "Contains shellfish",
        "Contains sesame",
        "Contains soy"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // --- Dining Halls ---
                    sectionCard("Dining Halls") {
                        ForEach(allHallIds, id: \.self) { hallId in
                            let name = hallNames[hallId] ?? hallId
                            selectablePill(name, isOn: Binding(
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

                        Button {
                            selectedHallIds = Set(allHallIds)
                        } label: {
                            Text("Select All")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.umdRed)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.umdRed, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    // --- Dietary Preferences ---
                    sectionCard("Dietary Preferences") {
                        selectablePill("Vegetarian", isOn: $filterVegetarian)
                        selectablePill("Vegan", isOn: $filterVegan)
                        selectablePill("High Protein (20g+)", isOn: $filterHighProtein)
                    }

                    // --- Allergens ---
                    sectionCard("Allergens to Avoid") {
                        ForEach(allergenOptions, id: \.self) { allergen in
                            selectablePill(
                                allergen.replacingOccurrences(of: "Contains ", with: ""),
                                isOn: Binding(
                                    get: { filterAllergens.contains(allergen) },
                                    set: { isOn in
                                        if isOn {
                                            filterAllergens.insert(allergen)
                                        } else {
                                            filterAllergens.remove(allergen)
                                        }
                                    }
                                )
                            )
                        }
                    }

                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func selectablePill(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.umdRed)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isOn.wrappedValue ? Color.umdRed.opacity(0.12) : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn.wrappedValue ? Color.umdRed : Color(.systemGray4), lineWidth: isOn.wrappedValue ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn.wrappedValue)
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
