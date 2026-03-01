import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "fork.knife") {
                HomeView()
            }
            Tab("Profile", systemImage: "person") {
                ProfileView()
            }
        }
        .tint(.umdRed)
    }
}

#Preview {
    ContentView()
        .environment(FavoritesManager.shared)
}
