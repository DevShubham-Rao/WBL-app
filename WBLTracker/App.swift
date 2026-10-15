import SwiftUI

@main
struct WBLTrackerApp: App {
    @StateObject private var store = VisitStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store) }
    }
}
