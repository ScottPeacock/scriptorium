import SwiftUI

struct RootView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        switch session.state {
        case .signedOut:
            AddServerView()
        case let .signedIn(account, user):
            ConnectedView(account: account, user: user)
        }
    }
}
