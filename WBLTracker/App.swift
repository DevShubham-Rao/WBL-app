import SwiftUI

@main
struct WBLTrackerApp: App {
    @StateObject private var store = VisitStore()
    @StateObject private var theme = ThemeManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(theme)
        }
    }
}
