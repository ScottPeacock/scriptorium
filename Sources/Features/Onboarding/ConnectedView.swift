import SwiftUI

/// Placeholder landing screen proving the connection works end to end.
/// The library browser (M2) replaces this.
struct ConnectedView: View {
    @Environment(SessionModel.self) private var session
    let account: ServerAccount
    let user: AppUserInfo

    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    LabeledContent("Address", value: account.baseURL.absoluteString)
                    LabeledContent("Signed in as", value: account.username)
                }
                Section("Permissions") {
                    LabeledContent("Administrator", value: user.isAdmin ? "Yes" : "No")
                    LabeledContent("Can download", value: user.canDownload ? "Yes" : "No")
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task {
                            await TokenStore(account: account).clear()
                            session.signOut()
                        }
                    }
                }
            }
            .navigationTitle("Connected")
        }
    }
}
