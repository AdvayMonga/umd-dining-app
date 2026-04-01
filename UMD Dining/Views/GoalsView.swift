import SwiftUI

struct GoalsView: View {
    @Environment(NutritionTrackerManager.self) private var tracker

    private let calorieOptions: [Int] = Array(stride(from: 1000, through: 5000, by: 50))
    private let macroOptions: [Int] = Array(stride(from: 0, through: 500, by: 5))

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                weightGoalSection
                calorieSection
                macroSection
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Set Goals")
    }

    // MARK: - Weight Goal

    private var weightGoalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight Goal")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(WeightGoal.allCases, id: \.self) { goal in
                    goalPill(goal)
                }
            }
        }
    }

    private func goalPill(_ goal: WeightGoal) -> some View {
        @Bindable var tracker = tracker
        let isSelected = tracker.weightGoal == goal

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { tracker.weightGoal = goal }
        } label: {
            HStack {
                Text(goal.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.umdRed)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.umdRed.opacity(0.12) : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.umdRed : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Calorie Goal

    private var calorieSection: some View {
        @Bindable var tracker = tracker

        return VStack(alignment: .leading, spacing: 8) {
            Text("Daily Calories")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                Text("\(tracker.calorieGoalSetting)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.umdRed)

                Picker("Calories", selection: $tracker.calorieGoalSetting) {
                    ForEach(calorieOptions, id: \.self) { cal in
                        Text("\(cal)").tag(cal)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                Text("calories per day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
    }

    // MARK: - Macro Goals

    private var macroSection: some View {
        @Bindable var tracker = tracker

        return VStack(alignment: .leading, spacing: 8) {
            Text("Macros")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                // Auto / Custom toggle
                HStack(spacing: 8) {
                    macroModePill("Auto", isSelected: !tracker.hasCustomMacros) {
                        withAnimation(.easeInOut(duration: 0.2)) { tracker.hasCustomMacros = false }
                    }
                    macroModePill("Custom", isSelected: tracker.hasCustomMacros) {
                        withAnimation(.easeInOut(duration: 0.2)) { tracker.hasCustomMacros = true }
                    }
                }

                if tracker.hasCustomMacros {
                    macroPickerRow(label: "Protein", value: $tracker.proteinGoal, color: .blue)
                    macroPickerRow(label: "Carbs", value: $tracker.carbsGoal, color: .green)
                    macroPickerRow(label: "Fat", value: $tracker.fatGoal, color: .orange)
                } else {
                    macroDisplayRow(label: "Protein", value: tracker.proteinGoal, color: .blue)
                    macroDisplayRow(label: "Carbs", value: tracker.carbsGoal, color: .green)
                    macroDisplayRow(label: "Fat", value: tracker.fatGoal, color: .orange)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
    }

    private func macroModePill(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.umdRed)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.umdRed.opacity(0.12) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.umdRed : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func macroPickerRow(label: String, value: Binding<Int>, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Spacer()
                Text("\(value.wrappedValue)g")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }

            Picker(label, selection: value) {
                ForEach(macroOptions, id: \.self) { g in
                    Text("\(g)g").tag(g)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 100)
        }
        .padding(.vertical, 4)
    }

    private func macroDisplayRow(label: String, value: Int, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
            Spacer()
            Text("\(value)g")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        GoalsView()
    }
    .environment(NutritionTrackerManager.shared)
}
