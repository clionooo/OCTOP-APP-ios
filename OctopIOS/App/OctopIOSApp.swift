import SwiftUI

@main
struct OctopIOSApp: App {
    @StateObject private var store = ServerStore()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .onAppear { settings.applyIdleTimer() }
        }
    }
}
