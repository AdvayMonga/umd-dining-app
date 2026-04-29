import SwiftUI

struct FilterOverlay: View {
    @Binding var filterVegetarian: Bool
    @Binding var filterVegan: Bool
    @Binding var filterHalal: Bool
    @Binding var filterHighProtein: Bool
    @Binding var filterAllergens: Set<String>

    var onDismiss: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showSaved = false

    private let allergenOptions = [
        "Contains dairy",
        "Contains egg",
        "Contains fish",
        "Contains gluten",
        "Contains nuts",
        "Contains Shellfish",
        "Contains sesame",
        "Contains soy"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // --- Dietary Preferences ---
                    sectionCard("Dietary Preferences") {
                        selectablePill("Vegetarian", isOn: $filterVegetarian)
                        selectablePill("Vegan", isOn: $filterVegan)
                        selectablePill("Halal", isOn: $filterHalal)
                        selectablePill("High Protein (15g+)", isOn: $filterHighProtein)
                    }

                    // --- Allergens ---
                    sectionCard("Allergens to Avoid") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(allergenOptions, id: \.self) { allergen in
                                selectablePill(
                                    allergen.replacingOccurrences(of: "Contains ", with: "").replacingOccurrences(of: "tree nuts", with: "Nuts").capitalized,
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
                    }

                    // Set as Defaults
                    Button {
                        let prefs = UserPreferences.shared
                        prefs.vegetarian = filterVegetarian
                        prefs.vegan = filterVegan
                        prefs.halal = filterHalal
                        prefs.allergens = filterAllergens

                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSaved = true
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { showSaved = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if showSaved {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                Text("Saved!")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            } else {
                                Text("Set as Defaults")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(showSaved ? .green : Color.umdRed)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(showSaved ? Color.green.opacity(0.5) : Color.umdRed.opacity(0.5), lineWidth: 1.5)
                        )
                        .contentTransition(.interpolate)
                    }
                    .buttonStyle(.plain)

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
                    Button("Done") {
                        if let onDismiss { onDismiss() } else { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.callout)
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
        filterVegetarian: .constant(false),
        filterVegan: .constant(false),
        filterHalal: .constant(false),
        filterHighProtein: .constant(false),
        filterAllergens: .constant([])
    )
}
