import SwiftData
import SwiftUI

struct NutritionDetailView: View {
    let recNum: String
    let foodName: String
    var station: String? = nil
    var diningHallName: String? = nil
    var source: String = "unknown"
    @State private var viewModel = NutritionViewModel()
    @Environment(FavoritesManager.self) private var favorites
    @Environment(NutritionTrackerManager.self) private var tracker
    @Environment(\.modelContext) private var modelContext
    @State private var showAddedToTracker = false
    @State private var showServingPicker = false
    @State private var servingCount: Double = 1.0

    // Already shown elsewhere — exclude from table
    private let excludeFromTable = ["Calories", "Total Fat", "Total Carbohydrate", "Protein",
                                     "Serving Size", "Servings Per Container"]

    // Key nutrients shown by default
    private let keyNutrients = ["Cholesterol", "Sodium", "Total Sugars", "Saturated Fat", "Calcium", "Potassium"]

    @State private var showAllNutrition = false
    @State private var showSimilarFoods = false

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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // Add to tracker button
                    Button {
                        servingCount = 1.0
                        showServingPicker = true
                    } label: {
                        if showAddedToTracker {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "plus.circle")
                                .foregroundStyle(Color.umdRed)
                        }
                    }
                    .disabled(viewModel.nutritionInfo == nil || showAddedToTracker)

                    // Favorite button
                    Button {
                        favorites.toggleFood(recNum: recNum, name: foodName)
                    } label: {
                        Image(systemName: favorites.isFavorite(recNum: recNum) ? "heart.fill" : "heart")
                            .foregroundStyle(favorites.isFavorite(recNum: recNum) ? Color.umdRed : .gray)
                    }
                }
            }
        }
        .task {
            await viewModel.loadNutrition(recNum: recNum)
            DiningAPIService.shared.trackItemView(recNum: recNum, foodName: foodName, source: source)
        }
        .task {
            let dateForSimilar: String? = (station == nil) ? todayDateString() : nil
            await viewModel.loadSimilarFoods(recNum: recNum, date: dateForSimilar)
        }
        .fullScreenCover(isPresented: $showServingPicker) {
            if let info = viewModel.nutritionInfo {
                ServingPickerSheet(
                    foodName: foodName,
                    nutrition: info.nutrition,
                    servingCount: $servingCount,
                    onLog: {
                        tracker.setModelContext(modelContext)
                        tracker.addEntry(name: foodName, recNum: recNum, nutrition: info.nutrition,
                                         mealPeriod: nil, diningHall: diningHallName,
                                         servingMultiplier: servingCount)
                        Task { await NutritionCache.shared.set(recNum, info) }
                        showServingPicker = false
                        servingCount = 1.0
                        withAnimation(.spring(duration: 0.3)) { showAddedToTracker = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { showAddedToTracker = false }
                        }
                    },
                    onCancel: {
                        showServingPicker = false
                        servingCount = 1.0
                    }
                )
                .presentationBackground(.clear)
            }
        }
    }

    private func nutritionContent(_ info: NutritionInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Food name — wraps for long names
                Text(foodName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)

                // Hero card — serving info left, calories right
                let servingSize = nutritionValue("Serving Size", from: info.nutrition)
                let servingsPerContainer = nutritionValue("Servings Per Container", from: info.nutrition)
                let calories = nutritionValue("Calories", from: info.nutrition)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let size = servingSize {
                            Text("Serving Size: \(size)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                        }
                        if let count = servingsPerContainer {
                            let number = count.filter { $0.isNumber || $0 == "." }
                            Text("\(number.isEmpty ? count : number) servings per container")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if station != nil || diningHallName != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption)
                                    .foregroundStyle(Color.umdRed)
                                Text([station, diningHallName].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.umdRed)
                            }
                        } else {
                            Text("Unavailable today")
                                .font(.subheadline)
                                .foregroundStyle(Color.umdRed)
                        }
                    }
                    Spacer()
                    if let cal = calories {
                        VStack(spacing: 0) {
                            Text(cal)
                                .font(.system(size: 48, weight: .bold))
                                .foregroundStyle(Color.umdRed)
                            Text("Calories")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.umdRed.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                if info.nutrition.isEmpty || calories == nil {
                    Text("Nutrition unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    // Macros bar
                    macrosSection(info.nutrition)

                    // Similar foods dropdown
                    similarFoodsSection

                    // Full nutrition table
                    nutritionTable(info.nutrition)
                }

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
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private static let hallNames: [String: String] = [
        "19": "Yahentamitsi Dining Hall",
        "51": "251 North",
        "16": "South Campus Diner",
    ]

    private var similarFoodsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showSimilarFoods.toggle() }
            } label: {
                HStack {
                    Text("Similar Foods")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if viewModel.similarFoodsLoading {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else if let foods = viewModel.similarFoods {
                        Text("(\(foods.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: showSimilarFoods ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(Color.umdRed)
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            if showSimilarFoods, let foods = viewModel.similarFoods, !foods.isEmpty {
                VStack(spacing: 8) {
                    ForEach(foods) { item in
                        let hallName = Self.hallNames[item.diningHallId] ?? ""
                        NavigationLink(destination: NutritionDetailView(
                            recNum: item.recNum,
                            foodName: item.name,
                            station: item.station.isEmpty ? nil : item.station,
                            diningHallName: hallName.isEmpty ? nil : hallName,
                            source: "similar"
                        )) {
                            FoodItemRow(item: item, diningHallName: hallName)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        return formatter.string(from: Date())
    }

    private func nutritionTable(_ nutrition: [String: String]) -> some View {
        let visibleKey = keyNutrients.filter { nutritionValue($0, from: nutrition) != nil }
        let extraKeys = nutrition.keys.sorted().filter { key in
            let norm = normalizedKey(key).lowercased()
            let isExcluded = excludeFromTable.contains(where: { $0.lowercased() == norm })
            let isKey = keyNutrients.contains(where: { $0.lowercased() == norm })
            return !isExcluded && !isKey
        }

        return VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)

            ForEach(visibleKey, id: \.self) { key in
                if let value = nutritionValue(key, from: nutrition) {
                    nutritionRow(label: normalizedKey(key), value: value)
                }
            }

            if !extraKeys.isEmpty {
                Button {
                    withAnimation { showAllNutrition.toggle() }
                } label: {
                    HStack {
                        Text(showAllNutrition ? "Show Less" : "Show All Nutrition")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: showAllNutrition ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.umdRed)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }

                if showAllNutrition {
                    ForEach(extraKeys, id: \.self) { key in
                        if let value = nutrition[key] {
                            nutritionRow(label: normalizedKey(key), value: value)
                        }
                    }
                }
            }
        }
    }

    private func nutritionRow(label: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
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

    private func nutritionValue(_ key: String, from nutrition: [String: String]) -> String? {
        let raw: String?
        if let v = nutrition[key] {
            raw = v
        } else {
            let normalized = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            raw = nutrition.first(where: {
                $0.key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == normalized
            })?.value
        }
        guard let value = raw else { return nil }
        // Hide zero values like "0g", "0mg", "0.0mg"
        let digits = value.filter { $0.isNumber || $0 == "." }
        if let num = Double(digits), num == 0 { return nil }
        return value
    }

    private func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: "."))
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

#Preview {
    NavigationStack {
        NutritionDetailView(recNum: "12345", foodName: "Grilled Chicken Breast")
    }
    .environment(FavoritesManager.shared)
    .environment(NutritionTrackerManager.shared)
    .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}

#Preview("With Mock Data") {
    NavigationStack {
        NutritionDetailView(recNum: "mock", foodName: "Chicken Congee")
    }
    .environment(FavoritesManager.shared)
    .environment(NutritionTrackerManager.shared)
    .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}
