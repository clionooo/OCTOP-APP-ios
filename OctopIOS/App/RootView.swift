import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationView {
            ServerListView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}
