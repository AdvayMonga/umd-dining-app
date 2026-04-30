import SwiftUI

struct FilterOverlay: View {
    @Binding var filterVegetarian: Bool
    @Binding var filterVegan: Bool
    @Binding var filterHalal: Bool
    @Binding var filterGlutenFree: Bool
    @Binding var filterDairyFree: Bool
    @Binding var filterHighProtein: Bool
    @Binding var filterAllergens: Set<String>

    var onDismiss: (() -> Void)?

    private let allergenOptions: [(label: String, key: String)] = [
        ("Dairy",     "Contains dairy"),
        ("Egg",       "Contains egg"),
        ("Fish",      "Contains fish"),
        ("Gluten",    "Contains gluten"),
        ("Nuts",      "Contains nuts"),
        ("Shellfish", "Contains Shellfish"),
        ("Sesame",    "Contains sesame"),
        ("Soy",       "Contains soy"),
    ]

    private var activeFilterCount: Int {
        (filterVegetarian ? 1 : 0) + (filterVegan ? 1 : 0) + (filterHalal ? 1 : 0)
        + (filterGlutenFree ? 1 : 0) + (filterDairyFree ? 1 : 0)
        + (filterHighProtein ? 1 : 0) + filterAllergens.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // MARK: Dietary Preferences
                    filterSection(title: "Dietary Preferences", icon: "leaf.fill", iconColor: Color.umdRed) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            dietaryPill("Vegetarian",   isOn: $filterVegetarian)
                            dietaryPill("Vegan",        isOn: $filterVegan)
                            dietaryPill("Halal Friendly", isOn: $filterHalal)
                            dietaryPill("Gluten Free",  isOn: $filterGlutenFree)
                            dietaryPill("Dairy Free",   isOn: $filterDairyFree)
                        }
                    }

                    Divider()

                    // MARK: Allergens to Avoid
                    filterSection(
                        title: "Allergens to Avoid",
                        icon: "exclamationmark.triangle.fill",
                        iconColor: Color(red: 180/255, green: 83/255, blue: 9/255),
                        subtitle: "Items containing these ingredients will be hidden from your menu."
                    ) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(allergenOptions, id: \.key) { option in
                                allergenPill(option.label, key: option.key)
                            }
                        }
                    }

                    Divider()

                    // MARK: Preferences
                    filterSection(title: "Preferences", icon: "dumbbell.fill", iconColor: Color(red: 55/255, green: 65/255, blue: 81/255)) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            dietaryPill("High Protein", isOn: $filterHighProtein, color: Color(red: 55/255, green: 65/255, blue: 81/255))
                        }
                    }

                    // MARK: Dining Safety Advisory
                    safetyAdvisory

                    Spacer().frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100) // space for sticky button
            }
            .background(Color.umdBackground)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        filterVegetarian = false
                        filterVegan = false
                        filterHalal = false
                        filterGlutenFree = false
                        filterDairyFree = false
                        filterHighProtein = false
                        filterAllergens = []
                    } label: {
                        Text("Reset")
                            .foregroundStyle(activeFilterCount > 0 ? Color.umdRed : .secondary)
                    }
                    .disabled(activeFilterCount == 0)
                }
            }
            .overlay(alignment: .bottom) {
                applyButton
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        Button { onDismiss?() } label: {
            HStack(spacing: 8) {
                Text(activeFilterCount > 0 ? "Apply \(activeFilterCount) Filter\(activeFilterCount == 1 ? "" : "s")" : "Apply Filters")
                    .font(.inter(size: 16, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.umdRed)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [Color.umdBackground.opacity(0), Color.umdBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Safety Advisory

    private var safetyAdvisory: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color(red: 107/255, green: 114/255, blue: 128/255))
                .font(.system(size: 18))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text("Dining Safety")
                    .font(.inter(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Maryland Dining does not guarantee allergen-free preparation. Cross-contamination may occur. Consult dining staff if you have a severe allergy.")
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.umdBorder, lineWidth: 1))
    }

    // MARK: - Section Header

    private func filterSection<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title.uppercased())
                    .font(.inter(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.5)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.inter(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.top, -6)
            }
            content()
        }
    }

    // MARK: - Pill Components

    private func dietaryPill(_ label: String, isOn: Binding<Bool>, color: Color = Color.umdRed) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack {
                Text(label)
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? color : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isOn.wrappedValue ? color.opacity(0.08) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn.wrappedValue ? color : Color.umdBorder, lineWidth: isOn.wrappedValue ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn.wrappedValue)
    }

    private func allergenPill(_ label: String, key: String) -> some View {
        let isOn = filterAllergens.contains(key)
        let color = Color(red: 180/255, green: 83/255, blue: 9/255)
        return Button {
            if isOn { filterAllergens.remove(key) }
            else { filterAllergens.insert(key) }
        } label: {
            HStack {
                Text(label)
                    .font(.inter(size: 14, weight: .medium))
                    .foregroundStyle(isOn ? color : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isOn ? color.opacity(0.08) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isOn ? color : Color.umdBorder, lineWidth: isOn ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

#Preview {
    FilterOverlay(
        filterVegetarian: .constant(false),
        filterVegan: .constant(false),
        filterHalal: .constant(false),
        filterGlutenFree: .constant(false),
        filterDairyFree: .constant(false),
        filterHighProtein: .constant(false),
        filterAllergens: .constant([])
    )
}
