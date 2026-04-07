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
                    HStack(spacing: 4) {
                        ForEach(item.tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                if let icon = tagIcon(for: tag) {
                                    Image(systemName: icon)
                                        .font(.system(size: 8, weight: .bold))
                                }
                                Text(tagLabel(for: tag))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(tagColor(for: tag).opacity(0.15))
                            .foregroundStyle(tagColor(for: tag))
                            .clipShape(Capsule())
                        }
                    }
                }

                Text(item.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if !item.station.isEmpty || !diningHallName.isEmpty {
                    Text([item.station, diningHallName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unavailable today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !item.dietaryIcons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.dietaryIcons, id: \.self) { icon in
                            Text(shortLabel(for: icon))
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color(for: icon).opacity(0.15))
                                .foregroundStyle(color(for: icon))
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

    private func tagLabel(for tag: String) -> String {
        tag.replacingOccurrences(of: "HalalFriendly", with: "Halal Friendly")
           .replacingOccurrences(of: "Contains ", with: "")
           .capitalized
    }

    private func tagIcon(for tag: String) -> String? {
        switch tag {
        case "Favorite": return "heart.fill"
        case "Recommended": return "star.fill"
        case "Trending": return "flame.fill"
        case "High Protein": return "dumbbell.fill"
        default: return nil
        }
    }

    private func tagColor(for tag: String) -> Color {
        switch tag {
        case "Favorite":     return .pink
        case "Trending":     return .orange
        case "Recommended":  return .teal
        case "High Protein": return .blue
        default:             return .gray
        }
    }

    private func shortLabel(for icon: String) -> String {
        switch icon {
        case "HalalFriendly": return "Halal"
        case "vegan": return "V"
        case "vegetarian": return "VG"
        case "Contains dairy": return "Dairy"
        case "Contains egg": return "Egg"
        case "Contains fish": return "Fish"
        case "Contains gluten": return "Gluten"
        case "Contains nuts": return "Nuts"
        case "Contains Shellfish": return "Shellfish"
        case "Contains sesame": return "Sesame"
        case "Contains soy": return "Soy"
        default: return icon
        }
    }

    private func color(for icon: String) -> Color {
        switch icon {
        case "vegan", "vegetarian": return .green
        default: return .gray
        }
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
        if servingCount == 1.0 { return size }
        let label = servingCount.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(servingCount))" : String(format: "%.1f", servingCount)
        return "\(label) x \(size)"
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

                    Slider(
                        value: $servingCount,
                        in: 0.5...5.0,
                        step: 0.5
                    )
                    .tint(Color.umdRed)
                }

                // Macro preview
                HStack(spacing: 6) {
                    macroPill("\(previewCalories) cal", color: Color.umdRed)
                    macroPill("\(previewProtein)g P", color: .blue)
                    macroPill("\(previewCarbs)g C", color: .green)
                    macroPill("\(previewFat)g F", color: .orange)
                }
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: servingCount)

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

    private func macroPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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
