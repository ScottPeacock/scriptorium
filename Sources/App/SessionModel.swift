import Foundation
import Observation

/// Everything a signed-in session needs, assembled once so views can reach the
/// service and cover loader without rebuilding clients per screen.
@MainActor
struct ServerConnection {
    let account: ServerAccount
    let user: AppUserInfo
    let client: GrimmoryClient
    let library: LibraryService
    let covers: CoverLoader
    let downloads: DownloadManager

    init(account: ServerAccount, user: AppUserInfo, client: GrimmoryClient) throws {
        self.account = account
        self.user = user
        self.client = client
        library = LibraryService(client: client)
        covers = CoverLoader(client: client, accountID: account.id)
        downloads = try DownloadManager(
            client: client,
            database: Database(accountID: account.id),
            accountID: account.id
        )
    }
}

@Observable
@MainActor
final class SessionModel {
    enum State {
        case restoring
        case signedOut
        case signedIn(ServerConnection)
    }

    private(set) var state: State = .restoring
    private let accounts = AccountStore()

    var connection: ServerConnection? {
        if case let .signedIn(connection) = state {
            return connection
        }
        return nil
    }

    /// Reconnects to the last-used server if its tokens are still in the
    /// keychain. Nothing is validated here — the first authenticated request
    /// will refresh or fail, and the UI handles that.
    func restore() async {
        guard let account = accounts.currentAccount else {
            state = .signedOut
            return
        }
        let store = TokenStore(account: account)
        guard await store.load() != nil else {
            state = .signedOut
            return
        }

        let client = GrimmoryClient(baseURL: account.baseURL, tokenStore: store)
        do {
            let user: AppUserInfo = try await client.send(.currentUser)
            state = try .signedIn(ServerConnection(account: account, user: user, client: client))
        } catch {
            // Expired beyond refresh, or the server is unreachable. Either way
            // the user starts at the connect screen.
            state = .signedOut
        }
    }

    func signIn(account: ServerAccount, user: AppUserInfo, client: GrimmoryClient) throws {
        accounts.save(account)
        state = try .signedIn(ServerConnection(account: account, user: user, client: client))
    }

    func signOut() async {
        if let connection {
            await connection.covers.clearCache()
            await TokenStore(account: connection.account).clear()
            accounts.remove(connection.account)
        }
        state = .signedOut
    }
}
