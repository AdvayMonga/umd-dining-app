import Charts
import SwiftData
import SwiftUI

struct TrackerView: View {
    @Binding var tabResetID: UUID
    @Environment(NutritionTrackerManager.self) private var tracker
    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate = Date()
    @State private var showClearConfirm = false
    @State private var animateCharts = false
    @State private var entries: [TrackedEntry] = []
    @State private var scrollProxy: ScrollViewProxy?
    @State private var hasAppeared = false
    @Namespace private var namespace

    // Display values that drive chart animations (animate between these)
    @State private var displayCalorieValue: Int = 0
    @State private var displayProteinValue: Double = 0
    @State private var displayCarbsValue: Double = 0
    @State private var displayFatValue: Double = 0

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

    private var proteinMet: Bool { tracker.proteinGoal > 0 && Int(totalProtein) >= tracker.proteinGoal }
    private var carbsMet: Bool { tracker.carbsGoal > 0 && Int(totalCarbs) >= tracker.carbsGoal }
    private var fatMet: Bool { tracker.fatGoal > 0 && Int(totalFat) >= tracker.fatGoal }

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: GoalsView()) {
                        HStack(spacing: 4) {
                            Image(systemName: "target")
                                .font(.caption)
                            Text("Set Goals")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.umdRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.umdRed.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .id(tabResetID)
        .overlay {
            if showClearConfirm {
                clearConfirmOverlay
            }
        }
        .onAppear {
            tracker.setModelContext(modelContext)
            if !hasAppeared {
                // First ever appearance: animate from 0
                selectedDate = Date()
                loadEntries()
                displayCalorieValue = 0
                displayProteinValue = 0
                displayCarbsValue = 0
                displayFatValue = 0
                animateCharts = true
                withAnimation(.easeOut(duration: 0.8)) {
                    displayCalorieValue = totalCalories
                    displayProteinValue = totalProtein
                    displayCarbsValue = totalCarbs
                    displayFatValue = totalFat
                }
                hasAppeared = true
            }
        }
        .onChange(of: selectedDate) {
            // Date change: animate from current display values to new day's values
            loadEntries()
            withAnimation(.easeOut(duration: 0.8)) {
                displayCalorieValue = totalCalories
                displayProteinValue = totalProtein
                displayCarbsValue = totalCarbs
                displayFatValue = totalFat
            }
        }
        .onChange(of: tabResetID) {
            // Tab re-selected: only re-animate if coming back from another tab
            let wasOnTab = hasAppeared
            selectedDate = Date()
            loadEntries()
            if wasOnTab {
                // Came back from another tab: animate from 0, no delay
                displayCalorieValue = 0
                displayProteinValue = 0
                displayCarbsValue = 0
                displayFatValue = 0
                animateCharts = true
                withAnimation(.easeOut(duration: 0.8)) {
                    displayCalorieValue = totalCalories
                    displayProteinValue = totalProtein
                    displayCarbsValue = totalCarbs
                    displayFatValue = totalFat
                }
            }
        }
    }

    // MARK: - Content

    private var trackerContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    Color.clear.frame(height: 0).id("trackerTop")
                    dateSelector
                    calorieRingCard
                    macroBarCard
                    loggedItemsSection
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .onAppear { scrollProxy = proxy }
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

            CalendarCardButton(selection: $selectedDate)

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

    // MARK: - Calorie Ring (Full Width)

    private var calorieRingCard: some View {
        ZStack {
            Chart {
                SectorMark(
                    angle: .value("Consumed", min(displayCalorieValue, calorieGoal)),
                    innerRadius: .ratio(0.7),
                    angularInset: 2
                )
                .foregroundStyle(Color.umdRed)
                .cornerRadius(4)

                SectorMark(
                    angle: .value("Remaining", max(0, calorieGoal - displayCalorieValue)),
                    innerRadius: .ratio(0.7),
                    angularInset: 2
                )
                .foregroundStyle(Color.gray.opacity(0.15))
                .cornerRadius(4)
            }
            .frame(height: 220)
            .animation(.easeOut(duration: 0.8), value: displayCalorieValue)

            VStack(spacing: 2) {
                Text("\(totalCalories)")
                    .font(.system(size: 42, weight: .bold))
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

    // MARK: - Macro Bar Chart (Vertical, bottom-up fill with goal)

    private var macroBarCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 16) {
                macroBar(label: "Protein", consumed: displayProteinValue, goal: Double(tracker.proteinGoal), color: .blue, met: proteinMet && animateCharts)
                macroBar(label: "Carbs", consumed: displayCarbsValue, goal: Double(tracker.carbsGoal), color: .green, met: carbsMet && animateCharts)
                macroBar(label: "Fat", consumed: displayFatValue, goal: Double(tracker.fatGoal), color: .orange, met: fatMet && animateCharts)
            }
            .frame(height: 200)
            .animation(.easeOut(duration: 0.8), value: displayProteinValue)
            .animation(.easeOut(duration: 0.8), value: displayCarbsValue)
            .animation(.easeOut(duration: 0.8), value: displayFatValue)
            .animation(.easeInOut(duration: 0.5), value: tracker.proteinGoal)
            .animation(.easeInOut(duration: 0.5), value: tracker.carbsGoal)
            .animation(.easeInOut(duration: 0.5), value: tracker.fatGoal)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private func macroBar(label: String, consumed: Double, goal: Double, color: Color, met: Bool) -> some View {
        let maxVal = max(goal, consumed, 1)
        let goalRatio = goal > 0 ? goal / maxVal : 0
        let consumedRatio = consumed / maxVal

        return VStack(spacing: 6) {
            // Goal on top
            if goal > 0 {
                Text("\(Int(goal))g")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(color.opacity(0.5))
            }

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Goal background (full translucent bar)
                    if goal > 0 {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.12))
                            .frame(height: geo.size.height * goalRatio)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }

                    // Consumed fill (solid, bottom-up)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(height: geo.size.height * min(consumedRatio, 1.0))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }

            // Consumed amount at bottom
            Text("\(Int(consumed))g")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(color)

            // Label + star
            HStack(spacing: 2) {
                if met {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Logged Items

    private var loggedItemsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Logged Items")
                    .font(.callout)
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
                    diningHallName: entry.diningHall,
                    source: "tracker"
                )
                .navigationTransition(.zoom(sourceID: "tracker-\(entry.id)", in: namespace))
                ) {
                    loggedItemRow(entry)
                }
                .matchedTransitionSource(id: "tracker-\(entry.id)", in: namespace)
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
                    macroLabel("\(entry.calories) cal", color: Color.umdRed)
                    macroLabel("\(Int(entry.proteinG))g P", color: .blue)
                    macroLabel("\(Int(entry.carbsG))g C", color: .green)
                    macroLabel("\(Int(entry.fatG))g F", color: .orange)
                }
            }

            Spacer()

            Button {
                removeEntry(entry)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(Color.umdRed)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        .shadow(color: .gray.opacity(0.15), radius: 4, x: 0, y: 2)
        .transition(.asymmetric(
            insertion: .opacity,
            removal: .opacity.combined(with: .slide)
        ))
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
                    clearAllEntries()
                } label: {
                    Text("Clear All")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.umdRed)
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

    private func loadEntries() {
        entries = tracker.entries(for: selectedDate)
    }

    private func removeEntry(_ entry: TrackedEntry) {
        tracker.setModelContext(modelContext)
        tracker.removeEntry(entry)
        withAnimation(.easeInOut(duration: 0.35)) {
            entries.removeAll { $0.id == entry.id }
        }
    }

    private func clearAllEntries() {
        tracker.setModelContext(modelContext)
        tracker.clearDay(selectedDate)
        withAnimation(.easeInOut(duration: 0.35)) {
            entries.removeAll()
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

#Preview {
    TrackerView(tabResetID: .constant(UUID()))
        .environment(NutritionTrackerManager.shared)
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}
