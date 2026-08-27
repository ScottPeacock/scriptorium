import SwiftUI

struct RootView: View {
    @Environment(SessionModel.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    var body: some View {
        Group {
            switch session.state {
            case .restoring:
                ProgressView()
            case .signedOut:
                AddServerView()
            case let .signedIn(connection):
                MainTabView(connection: connection)
            }
        }
        .task {
            if case .restoring = session.state {
                await session.restore()
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            // Returning to the app is a good moment to drain anything the
            // network was down for.
            guard phase == .active, let connection = session.connection else { return }
            Task { await connection.progress.flush() }
        }
    }
}
