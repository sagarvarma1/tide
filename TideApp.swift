import SwiftUI

@main
struct TideApp: App {
    @AppStorage("hasSelectedLocation") private var hasSelectedLocation = false
    
    init() {
        // Register for background tasks when the app launches
        TideBackgroundManager.shared.registerBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            if hasSelectedLocation {
                ContentView()
                    .onAppear {
                        // Schedule background refresh when the app appears
                        TideBackgroundManager.shared.scheduleBackgroundRefresh()
                    }
            } else {
                WelcomeView()
            }
        }
    }
}
