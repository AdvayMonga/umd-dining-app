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
        .gesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .local)
                .onEnded { value in
                    if value.translation.width < -30 && selectedTab < tabCount - 1 {
                        selectedTab += 1
                        tabResetID = UUID()
                    }
                    if value.translation.width > 30 && selectedTab > 0 {
                        selectedTab -= 1
                        tabResetID = UUID()
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
