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
    @State private var resolvedCalories: String?

    private var displayCalories: String? {
        // Prefer nutrition bundled inline in API response (e.g. from fetchMenu)
        if let n = item.nutrition,
           let raw = n["Calories"] ?? n["calories"] {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && t != "0" { return t }
        }
        return resolvedCalories
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Left: name + calories + tags
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.inter(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 17/255, green: 24/255, blue: 39/255))
                    .fixedSize(horizontal: false, vertical: true)

                if let cal = displayCalories {
                    Text("\(cal) CAL")
                        .font(.inter(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 107/255, green: 114/255, blue: 128/255))
                        .kerning(0.3)
                } else {
                    Text(" ")
                        .font(.inter(size: 12, weight: .medium))
                }

                tagRow
            }

            Spacer(minLength: 8)

            // Right: action group (+ and heart side-by-side per spec)
            HStack(spacing: 10) {
                trackerButton
                favoriteButton
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.umdRed.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .overlay {
            if showHeartAnimation {
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red.opacity(0.85))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        // Lazily resolve calories — fetches from NutritionCache or API as item scrolls into view.
        // LazyVStack ensures this only runs for visible items; NutritionCache prevents duplicate calls.
        .task(id: item.recNum) {
            guard displayCalories == nil else { return }
            await resolveCalories()
        }
        .onTapGesture(count: 2) {
            favorites.toggleFood(recNum: item.recNum, name: item.name)
            withAnimation(.spring(duration: 0.35)) { showHeartAnimation = true }
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.easeOut(duration: 0.25)) { showHeartAnimation = false }
            }
        }
        .onTapGesture(count: 1) { onTap?() }
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

    // MARK: - Tag Row

    @ViewBuilder
    private var tagRow: some View {
        let dietaryTags = item.dietaryIcons.filter { !DietaryStyles.isAllergen($0) }
        let allergenTags = item.dietaryIcons.filter { DietaryStyles.isAllergen($0) }
        let highProtein = item.tags.contains("High Protein")

        if !dietaryTags.isEmpty || !allergenTags.isEmpty || highProtein {
            FlowLayout(spacing: 4) {
                ForEach(dietaryTags, id: \.self) { icon in
                    tagPill(text: DietaryStyles.dietaryShortLabel(for: icon),
                            textColor: DietaryStyles.dietaryColor(for: icon),
                            bgColor: DietaryStyles.dietaryBgColor(for: icon))
                }
                if highProtein {
                    tagPill(text: "HIGH PROTEIN",
                            textColor: Color(red: 55/255, green: 65/255, blue: 81/255),
                            bgColor: Color(red: 243/255, green: 244/255, blue: 246/255))
                }
                ForEach(allergenTags, id: \.self) { icon in
                    tagPill(text: DietaryStyles.allergenAbbrev(for: icon),
                            textColor: Color(red: 55/255, green: 65/255, blue: 81/255),
                            bgColor: Color(red: 243/255, green: 244/255, blue: 246/255))
                }
            }
        }
    }

    private func tagPill(text: String, textColor: Color, bgColor: Color) -> some View {
        Text(text.uppercased())
            .font(.inter(size: 10, weight: .medium))
            .foregroundStyle(textColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Action Buttons

    private var trackerButton: some View {
        Button {
            guard !isAdding && !showAdded else { return }
            Task { await fetchAndShowPicker() }
        } label: {
            ZStack {
                if isAdding {
                    Circle().fill(Color.umdRed.opacity(0.15)).frame(width: 36, height: 36)
                    ProgressView().frame(width: 18, height: 18)
                } else if showAdded {
                    Circle().fill(Color.green).frame(width: 36, height: 36)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().fill(Color.umdRed).frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var favoriteButton: some View {
        Button {
            favorites.toggleFood(recNum: item.recNum, name: item.name)
        } label: {
            ZStack {
                Circle()
                    .stroke(favorites.isFavorite(recNum: item.recNum) ? Color.umdRed : Color.umdRed.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 36, height: 36)
                Image(systemName: favorites.isFavorite(recNum: item.recNum) ? "heart.fill" : "heart")
                    .font(.system(size: 14))
                    .foregroundStyle(favorites.isFavorite(recNum: item.recNum) ? Color.umdRed : Color(red: 107/255, green: 114/255, blue: 128/255))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calorie Resolution

    private func resolveCalories() async {
        // 1. Check NutritionCache (populated by prior + taps or station page visits)
        if let cached = await NutritionCache.shared.get(item.recNum) {
            setCalories(from: cached.nutrition)
            if resolvedCalories != nil { return }
        }
        // 2. Fetch from API — runs as item scrolls into view in LazyVStack
        guard let info = try? await DiningAPIService.shared.fetchNutrition(recNum: item.recNum) else { return }
        await NutritionCache.shared.set(item.recNum, info)
        setCalories(from: info.nutrition)
    }

    private func setCalories(from nutrition: [String: String]) {
        let raw = nutrition["Calories"] ?? nutrition["calories"] ?? ""
        let t = raw.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty && t != "0" { resolvedCalories = t }
    }

    // MARK: - Nutrition Fetch for Tracker

    private func fetchAndShowPicker() async {
        isAdding = true
        var nutrition: [String: String]?

        if let n = item.nutrition, !n.isEmpty {
            nutrition = n
        } else if let cached = await NutritionCache.shared.get(item.recNum) {
            nutrition = cached.nutrition
        } else {
            do {
                let info = try await DiningAPIService.shared.fetchNutrition(recNum: item.recNum)
                await NutritionCache.shared.set(item.recNum, info)
                nutrition = info.nutrition
                setCalories(from: info.nutrition)
            } catch {
                isAdding = false
                return
            }
        }

        guard let nutrition, !nutrition.isEmpty else { isAdding = false; return }
        isAdding = false
        servingCount = 1.0
        pendingNutrition = nutrition
        showServingPicker = true
    }
}

// MARK: - Serving Picker Sheet

struct ServingPickerSheet: View {
    let foodName: String
    let nutrition: [String: String]
    @Binding var servingCount: Double
    let onLog: () -> Void
    let onCancel: () -> Void

    private var servingSize: String? { nutritionValue("Serving Size", from: nutrition) }

    private var scaledServingSize: String? {
        guard let size = servingSize else { return nil }
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
        } else { num = Double(numStr) ?? 1 }
        let scaled = num * servingCount
        let formatted = scaled.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(scaled))" : String(format: "%.1f", scaled)
        return "\(formatted) \(unit)".trimmingCharacters(in: .whitespaces)
    }

    private func normalizeUnit(_ raw: String) -> String {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
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

    private func maxForUnit(_ unit: String) -> Double {
        switch unit {
        case "oz", "fl oz": return 20; case "ea": return 12; case "slice": return 10
        case "half": return 10; case "cup": return 8; case "tbsp": return 16
        case "tsp": return 24; case "ml": return 500; case "g": return 500
        default: return 10
        }
    }

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
            let fp = numStr.split(separator: "/")
            if fp.count == 2, let n = Double(fp[0]), let d = Double(fp[1]), d != 0 {
                num = n / d
            } else { num = 1 }
        } else { num = Double(numStr) ?? 1 }
        guard num > 0 else { return 10 }
        return max(1, min(ceil(maxForUnit(unit) / num), 20))
    }

    private var previewCalories: Int { Int(TrackedEntry.parseNumeric(nutritionValue("Calories", from: nutrition)) * servingCount) }
    private var previewProtein: Int  { Int(TrackedEntry.parseNumeric(nutritionValue("Protein", from: nutrition)) * servingCount) }
    private var previewCarbs: Int    { Int(TrackedEntry.parseNumeric(nutritionValue("Total Carbohydrate", from: nutrition)) * servingCount) }
    private var previewFat: Int      { Int(TrackedEntry.parseNumeric(nutritionValue("Total Fat", from: nutrition)) * servingCount) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { onCancel() }
            VStack(spacing: 16) {
                Text("Log Food").font(.inter(size: 18, weight: .bold))
                VStack(spacing: 4) {
                    Text(foodName).font(.inter(size: 15, weight: .semibold)).multilineTextAlignment(.center)
                    if let size = scaledServingSize {
                        Text("Serving Size: \(size)").font(.inter(size: 12)).foregroundStyle(.secondary)
                            .contentTransition(.numericText()).animation(.easeInOut(duration: 0.2), value: servingCount)
                    }
                }
                VStack(spacing: 8) {
                    Text(servingCount.truncatingRemainder(dividingBy: 1) == 0
                         ? "\(Int(servingCount))" : String(format: "%.1f", servingCount))
                        .font(.inter(size: 32, weight: .bold)).foregroundStyle(Color.umdRed)
                        .contentTransition(.numericText()).animation(.easeInOut(duration: 0.2), value: servingCount)
                    Text("servings").font(.inter(size: 12)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        macroPill(value: "\(previewCalories)", label: "Calories", color: Color.umdRed)
                        macroPill(value: "\(previewProtein)g", label: "Protein", color: .blue)
                        macroPill(value: "\(previewCarbs)g", label: "Carbs", color: .green)
                        macroPill(value: "\(previewFat)g", label: "Fat", color: .orange)
                    }
                    .contentTransition(.numericText()).animation(.easeInOut(duration: 0.2), value: servingCount)
                    Slider(value: $servingCount, in: 0.5...sliderMax, step: 0.5).tint(Color.umdRed)
                }
                HStack(spacing: 12) {
                    Button { onCancel() } label: {
                        Text("Cancel").font(.inter(size: 16, weight: .semibold)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color(.systemGray5)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                    Button { onLog() } label: {
                        Text("Log").font(.inter(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color.umdRed).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 20)
            .padding(.horizontal, 30)
        }
    }

    private func macroPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.inter(size: 13, weight: .bold))
            Text(label).font(.inter(size: 10, weight: .medium))
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 6)
        .background(color.opacity(0.15)).foregroundStyle(color).clipShape(Capsule())
    }

    private func nutritionValue(_ key: String, from nutrition: [String: String]) -> String? {
        if let v = nutrition[key] { return v }
        let norm = key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return nutrition.first(where: {
            $0.key.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == norm
        })?.value
    }
}
