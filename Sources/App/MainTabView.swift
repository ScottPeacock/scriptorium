import SwiftUI

struct MainTabView: View {
    let connection: ServerConnection

    var body: some View {
        // The iOS 18 `Tab` builder would read better, but the deployment
        // target is 17 — plenty of people read on older hardware.
        TabView {
            HomeView(connection: connection)
                .tabItem { Label("Home", systemImage: "house") }

            BrowseView(connection: connection)
                .tabItem { Label("Browse", systemImage: "square.grid.2x2") }

            SearchView(connection: connection)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            SettingsView(connection: connection)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environment(\.coverLoader, connection.covers)
    }
}
