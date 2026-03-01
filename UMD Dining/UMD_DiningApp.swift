import SwiftUI

@main
struct UMD_DiningApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(FavoritesManager.shared)
        }
    }
}
