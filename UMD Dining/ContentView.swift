import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NutritionTrackerManager.self) private var tracker

    var body: some View {
        TabView {
            Tab("Home", systemImage: "fork.knife") {
                HomeView()
            }
            Tab("Tracker", systemImage: "chart.bar.fill") {
                TrackerView()
            }
            Tab("Profile", systemImage: "person") {
                ProfileView()
            }
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
