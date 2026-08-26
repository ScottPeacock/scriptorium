import SwiftUI

struct RootView: View {
    @Environment(SessionModel.self) private var session

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
    }
}
