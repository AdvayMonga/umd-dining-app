import Charts
import SwiftData
import SwiftUI

struct TrackerView: View {
    @Environment(NutritionTrackerManager.self) private var tracker
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate = Date()
    @State private var showClearConfirm = false

    private var entries: [TrackedEntry] {
        tracker.entries(for: selectedDate)
    }

    private var totalCalories: Int {
        entries.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        entries.reduce(0) { $0 + $1.proteinG }
    }

    private var totalCarbs: Double {
        entries.reduce(0) { $0 + $1.carbsG }
    }

    private var totalFat: Double {
        entries.reduce(0) { $0 + $1.fatG }
    }

    private var calorieGoal: Int {
        tracker.calorieGoalSetting
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    emptyState
                } else {
                    trackerContent
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tracker")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        NavigationLink(destination: GoalsView()) {
                            Image(systemName: "target")
                                .foregroundStyle(Color.umdRed)
                        }
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
        }
        .overlay {
            if showClearConfirm {
                clearConfirmOverlay
            }
        }
        .onAppear {
            tracker.setModelContext(modelContext)
            selectedDate = Date()
        }
    }

    // MARK: - Content

    private var trackerContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                dateSelector
                calorieRingCard
                macroSummaryCard
                macroBarCard
                loggedItemsSection
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            dateSelector
                .padding(.horizontal, 12)
                .padding(.top, 8)
            Spacer()
            ContentUnavailableView(
                "No Food Tracked",
                systemImage: "fork.knife",
                description: Text("Tap + on any food item to start tracking your daily intake.")
            )
            Spacer()
        }
    }

    // MARK: - Date Selector

    private var dateSelector: some View {
        HStack {
            Button {
                withAnimation { selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)! }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.umdRed)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(dateLabel)
                .font(.title3)
                .fontWeight(.bold)

            Spacer()

            Button {
                withAnimation { selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)! }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(isToday ? Color.gray.opacity(0.3) : Color.umdRed)
                    .frame(width: 44, height: 44)
            }
            .disabled(isToday)
        }
    }

    private var dateLabel: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    // MARK: - Calorie Ring

    private var calorieRingCard: some View {
        VStack(spacing: 8) {
            Text("Calories")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            ZStack {
                Chart {
                    SectorMark(
                        angle: .value("Consumed", min(totalCalories, calorieGoal)),
                        innerRadius: .ratio(0.7),
                        angularInset: 2
                    )
                    .foregroundStyle(Color.umdRed)
                    .cornerRadius(4)

                    SectorMark(
                        angle: .value("Remaining", max(0, calorieGoal - totalCalories)),
                        innerRadius: .ratio(0.7),
                        angularInset: 2
                    )
                    .foregroundStyle(Color.gray.opacity(0.15))
                    .cornerRadius(4)
                }
                .frame(height: 200)
                .animation(.easeInOut(duration: 0.5), value: totalCalories)

                VStack(spacing: 2) {
                    Text("\(totalCalories)")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Color.umdRed)
                    Text("/ \(calorieGoal) cal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - Macro Summary Pills

    private var macroSummaryCard: some View {
        HStack(spacing: 10) {
            macroPill(label: "Protein", consumed: Int(totalProtein), goal: tracker.proteinGoal, color: .blue)
            macroPill(label: "Carbs", consumed: Int(totalCarbs), goal: tracker.carbsGoal, color: .green)
            macroPill(label: "Fat", consumed: Int(totalFat), goal: tracker.fatGoal, color: .orange)
        }
    }

    private func macroPill(label: String, consumed: Int, goal: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text("\(consumed)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Text(" / \(goal)g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Macro Bar Chart (Vertical with Goal Lines)

    private var macroBarCard: some View {
        VStack(spacing: 8) {
            Text("Macros")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                Chart {
                    // Protein
                    BarMark(x: .value("Macro", "Protein"), y: .value("Grams", totalProtein))
                        .foregroundStyle(.blue)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text("\(Int(totalProtein))g")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    if tracker.proteinGoal > 0 {
                        RuleMark(y: .value("Goal", tracker.proteinGoal))
                            .foregroundStyle(.blue.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }

                    // Carbs
                    BarMark(x: .value("Macro", "Carbs"), y: .value("Grams", totalCarbs))
                        .foregroundStyle(.green)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text("\(Int(totalCarbs))g")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                        }
                    if tracker.carbsGoal > 0 {
                        RuleMark(y: .value("Goal", tracker.carbsGoal))
                            .foregroundStyle(.green.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }

                    // Fat
                    BarMark(x: .value("Macro", "Fat"), y: .value("Grams", totalFat))
                        .foregroundStyle(.orange)
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text("\(Int(totalFat))g")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.orange)
                        }
                    if tracker.fatGoal > 0 {
                        RuleMark(y: .value("Goal", tracker.fatGoal))
                            .foregroundStyle(.orange.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.caption)
                    }
                }
                .frame(height: 200)
                .animation(.easeInOut(duration: 0.5), value: totalProtein)
                .animation(.easeInOut(duration: 0.5), value: totalCarbs)
                .animation(.easeInOut(duration: 0.5), value: totalFat)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - Logged Items

    private var loggedItemsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Logged Items")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(entries.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.umdRed.opacity(0.15))
                    .foregroundStyle(Color.umdRed)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 4)

            ForEach(entries) { entry in
                NavigationLink(destination: NutritionDetailView(
                    recNum: entry.recNum,
                    foodName: entry.foodName,
                    diningHallName: entry.diningHall
                )) {
                    loggedItemRow(entry)
                }
                .buttonStyle(.plain)
            }

            if !entries.isEmpty {
                Button {
                    showClearConfirm = true
                } label: {
                    Text("Clear All")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.umdRed)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loggedItemRow(_ entry: TrackedEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.foodName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(timeString(from: entry.loggedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    macroLabel("\(Int(entry.proteinG))g P", color: .blue)
                    macroLabel("\(Int(entry.carbsG))g C", color: .green)
                    macroLabel("\(Int(entry.fatG))g F", color: .orange)
                }
            }

            Spacer()

            Text("\(entry.calories)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Color.umdRed)

            Text("cal")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                tracker.setModelContext(modelContext)
                withAnimation { tracker.removeEntry(entry) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
                    .font(.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    private func macroLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Clear Confirm Overlay

    private var clearConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showClearConfirm = false }

            VStack(spacing: 16) {
                Text("Clear All Items?")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("This will remove all \(entries.count) logged items for \(dateLabel.lowercased()).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showClearConfirm = false
                    tracker.setModelContext(modelContext)
                    withAnimation { tracker.clearDay(selectedDate) }
                } label: {
                    Text("Clear All")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showClearConfirm = false
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Helpers

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

#Preview {
    TrackerView()
        .environment(NutritionTrackerManager.shared)
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}
