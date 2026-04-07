import SwiftUI

struct AllergenOption: Identifiable {
    let id: String
    let label: String
}

struct AllergenSurveyView: View {
    var onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var isVegetarian = false
    @State private var isVegan = false
    @State private var isHalal = false

    private let allergens: [AllergenOption] = [
        AllergenOption(id: "Contains dairy", label: "Dairy"),
        AllergenOption(id: "Contains egg", label: "Egg"),
        AllergenOption(id: "Contains fish", label: "Fish"),
        AllergenOption(id: "Contains gluten", label: "Gluten"),
        AllergenOption(id: "Contains nuts", label: "Nuts"),
        AllergenOption(id: "Contains Shellfish", label: "Shellfish"),
        AllergenOption(id: "Contains sesame", label: "Sesame"),
        AllergenOption(id: "Contains soy", label: "Soy"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            Text("Dietary Preferences")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.umdRed)

            Text("We'll personalize your feed based on these")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer().frame(height: 24)

            ScrollView {
                VStack(spacing: 16) {
                    // Dietary options
                    HStack(spacing: 12) {
                        dietaryCard("Vegetarian", isOn: $isVegetarian)
                        dietaryCard("Vegan", isOn: $isVegan)
                        dietaryCard("Halal", isOn: $isHalal)
                    }
                    .padding(.horizontal)

                    Text("Allergens to Avoid")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(allergens) { allergen in
                            allergenCard(allergen)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    UserPreferences.shared.vegetarian = isVegetarian
                    UserPreferences.shared.vegan = isVegan
                    UserPreferences.shared.halal = isHalal
                    UserPreferences.shared.allergens = selected
                    onComplete()
                    dismiss()
                } label: {
                    Text(selected.isEmpty ? "No Allergies" : "Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.umdRed)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if !selected.isEmpty {
                    Button {
                        selected.removeAll()
                    } label: {
                        Text("Clear All")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            selected = UserPreferences.shared.allergens
            isVegetarian = UserPreferences.shared.vegetarian
            isVegan = UserPreferences.shared.vegan
            isHalal = UserPreferences.shared.halal
        }
    }

    private func dietaryCard(_ label: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isOn.wrappedValue ? Color.umdRed.opacity(0.12) : Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isOn.wrappedValue ? Color.umdRed : Color(.systemGray4), lineWidth: isOn.wrappedValue ? 2 : 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func allergenCard(_ allergen: AllergenOption) -> some View {
        let isSelected = selected.contains(allergen.id)
        return Button {
            if isSelected {
                selected.remove(allergen.id)
            } else {
                selected.insert(allergen.id)
            }
        } label: {
            Text(allergen.label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
            .background(isSelected ? Color.umdRed.opacity(0.12) : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.umdRed : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AllergenSurveyView(onComplete: {})
}
