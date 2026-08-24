import SwiftData
import SwiftUI

struct ContentView: View {
    let initialHallId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(NutritionTrackerManager.self) private var tracker
    @State private var selectedTab = 0
    @State private var tabResetID = UUID()
    @AppStorage("hasCompletedTutorial") private var hasCompletedTutorial = true

    init(initialHallId: String) {
        self.initialHallId = initialHallId
        UITabBar.appearance().isHidden = true
    }

    private var tabBinding: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                guard newValue != selectedTab else { return }
                selectedTab = newValue
                tabResetID = UUID()
            }
        )
    }

    var body: some View {
        ZStack {
            TabView(selection: tabBinding) {
                HomeView(tabResetID: $tabResetID, initialHallId: initialHallId)
                    .tag(0)

                TrackerView(tabResetID: $tabResetID)
                    .tag(1)

                ProfileView(tabResetID: $tabResetID)
                    .tag(2)
            }
            .onAppear {
                tracker.setModelContext(modelContext)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 60)
            }

            VStack {
                Spacer()
                CustomTabBar(selectedTab: tabBinding)
            }

            if !hasCompletedTutorial {
                TutorialOverlayView(isShowing: Binding(
                    get: { !hasCompletedTutorial },
                    set: { if !$0 { hasCompletedTutorial = true } }
                ))
                .zIndex(100)
            }
        }
    }
}

private struct TabBarItem: View {
    let icon: String
    let tag: Int
    @Binding var selectedTab: Int

    private var isSelected: Bool { selectedTab == tag }

    var body: some View {
        Button {
            selectedTab = tag
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? Color.umdRed : Color.clear)
                    .frame(width: 28, height: 3)

                Image(systemName: isSelected ? "\(icon).fill" : icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? Color.umdRed : Color(.systemGray3))
                    .frame(height: 26)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CustomTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                TabBarItem(icon: "house", tag: 0, selectedTab: $selectedTab)
                TabBarItem(icon: "chart.bar", tag: 1, selectedTab: $selectedTab)
                TabBarItem(icon: "person", tag: 2, selectedTab: $selectedTab)
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(
            Color(.systemBackground)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

#Preview {
    ContentView(initialHallId: "19")
        .environment(FavoritesManager.shared)
        .environment(NutritionTrackerManager.shared)
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}
