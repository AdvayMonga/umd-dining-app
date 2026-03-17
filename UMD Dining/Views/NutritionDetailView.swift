import SwiftUI

struct NutritionDetailView: View {
    let recNum: String
    let foodName: String
    @State private var viewModel = NutritionViewModel()

    private let macroKeys = ["Calories", "Total Fat", "Saturated Fat", "Trans Fat",
                             "Cholesterol", "Sodium", "Total Carbohydrate",
                             "Dietary Fiber", "Total Sugars", "Protein"]

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading nutrition info...")
            } else if let error = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadNutrition(recNum: recNum) }
                    }
                }
            } else if let info = viewModel.nutritionInfo {
                nutritionContent(info)
            }
        }
        .navigationTitle(foodName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadNutrition(recNum: recNum)
        }
    }

    private func nutritionContent(_ info: NutritionInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Calories hero
                if let calories = nutritionValue("Calories", from: info.nutrition) {
                    HStack {
                        Spacer()
                        VStack {
                            Text(calories)
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(Color.umdRed)
                            Text("Calories")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                }

                // Macros bar
                macrosSection(info.nutrition)

                // Full nutrition table
                nutritionTable(info.nutrition)

                // Allergens
                if !info.allergens.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allergens")
                            .font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(info.allergens.components(separatedBy: ", "), id: \.self) { allergen in
                                Text(allergen.trimmingCharacters(in: .whitespaces))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Ingredients
                if !info.ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ingredients")
                            .font(.headline)
                        Text(info.ingredients)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    private func macrosSection(_ nutrition: [String: String]) -> some View {
        HStack(spacing: 20) {
            macroItem(label: "Protein", value: nutritionValue("Protein", from: nutrition), color: .blue)
            macroItem(label: "Carbs", value: nutritionValue("Total Carbohydrate", from: nutrition), color: .green)
            macroItem(label: "Fat", value: nutritionValue("Total Fat", from: nutrition), color: .orange)
        }
        .padding(.horizontal)
    }

    private func macroItem(label: String, value: String?, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value ?? "--")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func nutritionTable(_ nutrition: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)

            ForEach(orderedNutritionKeys(nutrition), id: \.self) { key in
                if let value = nutritionValue(key, from: nutrition), normalizedKey(key) != "Calories" {
                    HStack {
                        Text(normalizedKey(key))
                            .font(.subheadline)
                        Spacer()
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    Divider().padding(.horizontal)
                }
            }
        }
    }

    private func nutritionValue(_ key: String, from nutrition: [String: String]) -> String? {
        if let v = nutrition[key] { return v }
        let normalized = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        for (k, v) in nutrition {
            if k.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == normalized {
                return v
            }
        }
        return nil
    }

    private func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func orderedNutritionKeys(_ nutrition: [String: String]) -> [String] {
        let ordered = macroKeys.filter { nutritionValue($0, from: nutrition) != nil }
        let remaining = nutrition.keys.sorted().filter { key in
            !macroKeys.contains(where: { $0.lowercased() == normalizedKey(key).lowercased() })
        }
        return ordered + remaining
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
