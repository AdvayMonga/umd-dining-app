import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NutritionTrackerManager.self) private var tracker
    @State private var selectedTab = 0

    private let tabCount = 3

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(tabSelection: $selectedTab, myTab: 0)
                .tabItem {
                    Label("Home", systemImage: "fork.knife")
                }
                .tag(0)

            TrackerView(tabSelection: $selectedTab, myTab: 1)
                .tabItem {
                    Label("Tracker", systemImage: "chart.bar.fill")
                }
                .tag(1)

            ProfileView(tabSelection: $selectedTab, myTab: 2)
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(2)
        }
        .tint(.umdRed)
        .onAppear {
            tracker.setModelContext(modelContext)
        }
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    // Swipe left → next tab
                    if value.translation.width < -30 && selectedTab < tabCount - 1 {
                        withAnimation { selectedTab += 1 }
                    }
                    // Swipe right → previous tab
                    if value.translation.width > 30 && selectedTab > 0 {
                        withAnimation { selectedTab -= 1 }
                    }
                }
        )
    }
}

#Preview {
    ContentView()
        .environment(FavoritesManager.shared)
        .environment(NutritionTrackerManager.shared)
        .modelContainer(for: [DailyLog.self, TrackedEntry.self])
}
