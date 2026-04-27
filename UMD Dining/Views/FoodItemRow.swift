import SwiftData
import SwiftUI

struct FoodItemRow: View {
    let item: MenuItem
    let diningHallName: String
    var onTap: (() -> Void)? = nil
    @Environment(FavoritesManager.self) private var favorites
    @Environment(NutritionTrackerManager.self) private var tracker
    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var showAdded = false
    @State private var showServingPicker = false
    @State private var servingCount: Double = 1.0
    @State private var pendingNutrition: [String: String]?
    @State private var showHeartAnimation = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if !item.tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(item.tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                if let icon = DietaryStyles.tagIcon(for: tag) {
                                    Image(systemName: icon)
                                        .font(.system(size: 8, weight: .bold))
                                }
                                Text(DietaryStyles.tagLabel(for: tag))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(DietaryStyles.tagColor(for: tag).opacity(0.15))
                            .foregroundStyle(DietaryStyles.tagColor(for: tag))
                            .clipShape(Capsule())
                        }
                    }
                }

                Text(item.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                AvailabilityLabel(
                    availability: item.availability,
                    fallbackStation: item.station,
                    fallbackDiningHallName: diningHallName
                )

                if !item.dietaryIcons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.dietaryIcons, id: \.self) { icon in
                            Text(DietaryStyles.dietaryLabel(for: icon))
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DietaryStyles.dietaryColor(for: icon).opacity(0.15))
                                .foregroundStyle(DietaryStyles.dietaryColor(for: icon))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            // Add to tracker button
            Button {
                guard !isAdding && !showAdded else { return }
                Task { await fetchAndShowPicker() }
            } label: {
                if isAdding {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else if showAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.umdRed)
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)

            Button {
                favorites.toggleFood(recNum: item.recNum, name: item.name)
            } label: {
                Image(systemName: favorites.isFavorite(recNum: item.recNum) ? "heart.fill" : "heart")
                    .foregroundStyle(favorites.isFavorite(recNum: item.recNum) ? .red : .gray)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
        .overlay {
            if showHeartAnimation {
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red.opacity(0.85))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            favorites.toggleFood(recNum: item.recNum, name: item.name)
            withAnimation(.spring(duration: 0.35)) { showHeartAnimation = true }
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeOut(duration: 0.25)) { showHeartAnimation = false }
            }
        }
        .onTapGesture(count: 1) {
            onTap?()
        }
        .fullScreenCover(isPresented: $showServingPicker) {
            if let nutrition = pendingNutrition {
                ServingPickerSheet(
                    foodName: item.name,
                    nutrition: nutrition,
                    servingCount: $servingCount,
                    onLog: {
                        tracker.setModelContext(modelContext)
                        tracker.addEntry(name: item.name, recNum: item.recNum, nutrition: nutrition,
                                         mealPeriod: item.mealPeriod, diningHall: diningHallName,
                                         servingMultiplier: servingCount)
                        showServingPicker = false
                        servingCount = 1.0
                        Task {
                            withAnimation(.spring(duration: 0.3)) { showAdded = true }
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { showAdded = false }
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

    private func fetchAndShowPicker() async {
        isAdding = true

        var nutrition: [String: String]?

        if let n = item.nutrition, !n.isEmpty {
            nutrition = n
        } else {
            if let cached = await NutritionCache.shared.get(item.recNum) {
                nutrition = cached.nutrition
            } else {
                do {
                    let info = try await DiningAPIService.shared.fetchNutrition(recNum: item.recNum)
                    await NutritionCache.shared.set(item.recNum, info)
                    nutrition = info.nutrition
                } catch {
                    isAdding = false
                    return
                }
            }
        }

        guard let nutrition, !nutrition.isEmpty else {
            isAdding = false
            return
        }

        isAdding = false
        servingCount = 1.0
        pendingNutrition = nutrition
        showServingPicker = true
    }

}

// MARK: - Serving Picker Overlay

struct ServingPickerSheet: View {
    let foodName: String
    let nutrition: [String: String]
    @Binding var servingCount: Double
    let onLog: () -> Void
    let onCancel: () -> Void

    private var servingSize: String? {
        nutritionValue("Serving Size", from: nutrition)
    }

    private var scaledServingSize: String? {
        guard let size = servingSize else { return nil }
        // Extract numeric portion and unit, e.g. "4 1/2 oz" -> (4.5, "oz")
        let pattern = #"^([\d]+(?:\s*[\d]*/[\d]+)?)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: size, range: NSRange(size.startIndex..., in: size)),
              let numRange = Range(match.range(at: 1), in: size) else {
            if servingCount == 1.0 { return normalizeUnit(size) }
            let label = servingCount.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(servingCount))" : String(format: "%.1f", servingCount)
            return "\(label) x \(normalizeUnit(size))"
        }
        let numStr = String(size[numRange]).trimmingCharacters(in: .whitespaces)
        let unitRange = Range(match.range(at: 2), in: size)
        let rawUnit = unitRange.map { String(size[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        let unit = normalizeUnit(rawUnit)

        // Parse number — handle "4 1/2" (whole + fraction) or "1/2" (fraction only)
        let num: Double
        let parts = numStr.split(separator: " ")
        if parts.count == 2, parts[1].contains("/") {
            let whole = Double(parts[0]) ?? 0
            let fracParts = parts[1].split(separator: "/")
            if fracParts.count == 2, let n = Double(fracParts[0]), let d = Double(fracParts[1]), d != 0 {
                num = whole + n / d
            } else {
                num = whole
            }
        } else if numStr.contains("/") {
            let fracParts = numStr.split(separator: "/")
            if fracParts.count == 2, let n = Double(fracParts[0]), let d = Double(fracParts[1]), d != 0 {
                num = n / d
            } else {
                num = 1
            }
        } else {
            num = Double(numStr) ?? 1
        }

        let scaled = num * servingCount
        let formatted = scaled.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(scaled))" : String(format: "%.1f", scaled)
        return "\(formatted) \(unit)".trimmingCharacters(in: .whitespaces)
    }

    private func normalizeUnit(_ raw: String) -> String {
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch lowered {
        case "oz", "oz.", "ounce", "ounces": return "oz"
        case "ea", "ea.", "each", "pc", "pcs", "piece", "pieces": return "ea"
        case "cup", "cups": return "cup"
        case "tbsp", "tablespoon", "tablespoons": return "tbsp"
        case "tsp", "teaspoon", "teaspoons": return "tsp"
        case "ml", "milliliter", "milliliters": return "ml"
        case "g", "gram", "grams": return "g"
        case "half": return "half"
        case "slice", "slices": return "slice"
        case "fl oz", "fluid oz": return "fl oz"
        default: return raw
        }
    }

    /// Max quantity target for each unit type
    private func maxForUnit(_ unit: String) -> Double {
        switch unit {
        case "oz", "fl oz":  return 20
        case "ea":           return 12
        case "slice":        return 10
        case "half":         return 10
        case "cup":          return 8
        case "tbsp":         return 16
        case "tsp":          return 24
        case "ml":           return 500
        case "g":            return 500
        default:             return 10
        }
    }

    /// Compute max servings for the slider based on serving size and unit
    private var sliderMax: Double {
        guard let size = servingSize else { return 10 }
        let pattern = #"^([\d]+(?:\s*[\d]*/[\d]+)?)\s*(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: size, range: NSRange(size.startIndex..., in: size)),
              let numRange = Range(match.range(at: 1), in: size) else { return 10 }
        let numStr = String(size[numRange]).trimmingCharacters(in: .whitespaces)
        let unitRange = Range(match.range(at: 2), in: size)
        let rawUnit = unitRange.map { String(size[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        let unit = normalizeUnit(rawUnit)

        let num: Double
        let parts = numStr.split(separator: " ")
        if parts.count == 2, parts[1].contains("/") {
            let whole = Double(parts[0]) ?? 0
            let fracParts = parts[1].split(separator: "/")
            if fracParts.count == 2, let n = Double(fracParts[0]), let d = Double(fracParts[1]), d != 0 {
                num = whole + n / d
            } else { num = whole }
        } else if numStr.contains("/") {
            let fracParts = numStr.split(separator: "/")
            if fracParts.count == 2, let n = Double(fracParts[0]), let d = Double(fracParts[1]), d != 0 {
                num = n / d
            } else { num = 1 }
        } else {
            num = Double(numStr) ?? 1
        }

        guard num > 0 else { return 10 }
        let maxServings = ceil(maxForUnit(unit) / num)
        return max(1, min(maxServings, 20)) // cap at 20 servings
    }

    private var previewCalories: Int {
        Int(TrackedEntry.parseNumeric(nutritionValue("Calories", from: nutrition)) * servingCount)
    }

    private var previewProtein: Int {
        Int(TrackedEntry.parseNumeric(nutritionValue("Protein", from: nutrition)) * servingCount)
    }

    private var previewCarbs: Int {
        Int(TrackedEntry.parseNumeric(nutritionValue("Total Carbohydrate", from: nutrition)) * servingCount)
    }

    private var previewFat: Int {
        Int(TrackedEntry.parseNumeric(nutritionValue("Total Fat", from: nutrition)) * servingCount)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 16) {
                // Header
                Text("Log Food")
                    .font(.title3)
                    .fontWeight(.bold)

                // Food info
                VStack(spacing: 4) {
                    Text(foodName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    if let size = scaledServingSize {
                        Text("Serving Size: \(size)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: servingCount)
                    }
                }

                // Serving slider
                VStack(spacing: 8) {
                    Text(servingCount.truncatingRemainder(dividingBy: 1) == 0
                         ? "\(Int(servingCount))"
                         : String(format: "%.1f", servingCount))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.umdRed)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: servingCount)

                    Text("servings")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Macro preview
                    HStack(spacing: 8) {
                        macroPill(value: "\(previewCalories)", label: "Calories", color: Color.umdRed)
                        macroPill(value: "\(previewProtein)g", label: "Protein", color: .blue)
                        macroPill(value: "\(previewCarbs)g", label: "Carbs", color: .green)
                        macroPill(value: "\(previewFat)g", label: "Fat", color: .orange)
                    }
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: servingCount)

                    Slider(
                        value: $servingCount,
                        in: 0.5...sliderMax,
                        step: 0.5
                    )
                    .tint(Color.umdRed)
                }

                // Buttons
                HStack(spacing: 12) {
                    Button {
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onLog()
                    } label: {
                        Text("Log")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.umdRed)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(.horizontal, 30)
        }
    }

    private func macroPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func nutritionValue(_ key: String, from nutrition: [String: String]) -> String? {
        if let v = nutrition[key] { return v }
        let normalized = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return nutrition.first(where: {
            $0.key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == normalized
        })?.value
    }
}
