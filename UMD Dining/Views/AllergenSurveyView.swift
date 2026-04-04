import SwiftUI

struct AllergenOption: Identifiable {
    let id: String
    let label: String
    let icon: String
}

struct AllergenSurveyView: View {
    var onComplete: () -> Void
    var isOnboarding: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    private let allergens: [AllergenOption] = [
        AllergenOption(id: "Contains dairy", label: "Dairy", icon: "🥛"),
        AllergenOption(id: "Contains egg", label: "Egg", icon: "🥚"),
        AllergenOption(id: "Contains fish", label: "Fish", icon: "🐟"),
        AllergenOption(id: "Contains gluten", label: "Gluten", icon: "🌾"),
        AllergenOption(id: "Contains shellfish", label: "Shellfish", icon: "🦐"),
        AllergenOption(id: "Contains sesame", label: "Sesame", icon: "🫘"),
        AllergenOption(id: "Contains soy", label: "Soy", icon: "🫛"),
        AllergenOption(id: "Contains nuts", label: "Nuts", icon: "🥜"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)

            Text("Any allergies?")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.umdRed)

            Text("We'll hide foods containing these from your feed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer().frame(height: 24)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(allergens) { allergen in
                        allergenCard(allergen)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    var toSave = selected
                    if toSave.contains("Contains nuts") { toSave.insert("Contains peanuts") }
                    UserPreferences.shared.allergens = toSave
                    onComplete()
                    dismiss()
                } label: {
                    Text(isOnboarding ? (selected.isEmpty ? "No Allergies" : "Continue") : "Done")
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
            var prefs = UserPreferences.shared.allergens
            // Map peanuts back to the grouped nuts key for display
            if prefs.contains("Contains peanuts") { prefs.insert("Contains nuts") }
            selected = prefs
        }
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
            VStack(spacing: 8) {
                Text(allergen.icon)
                    .font(.system(size: 36))
                Text(allergen.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
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
