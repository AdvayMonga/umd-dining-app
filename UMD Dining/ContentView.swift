import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NutritionTrackerManager.self) private var tracker
    @State private var selectedTab = 0
    @State private var tabResetID = UUID()

    private let tabCount = 3

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
        TabView(selection: tabBinding) {
            HomeView(tabResetID: $tabResetID)
                .tabItem {
                    Label("Home", systemImage: "fork.knife")
                }
                .tag(0)

            TrackerView(tabResetID: $tabResetID)
                .tabItem {
                    Label("Tracker", systemImage: "chart.bar.fill")
                }
                .tag(1)

            ProfileView(tabResetID: $tabResetID)
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(2)
        }
        .tint(.umdRed)
        .onAppear {
            tracker.setModelContext(modelContext)
        }
    }
}

#Preview {
    ContentView()
        .environment(FavoritesManager.shared)
        .environment(NutritionTrackerManager.shared)
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}
