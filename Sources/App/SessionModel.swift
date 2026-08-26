import Foundation
import Observation

/// Holds the signed-in account for the process. Persisting the account list and
/// the multi-server switcher land with the rest of M1.
@Observable
@MainActor
final class SessionModel {
    enum State {
        case signedOut
        case signedIn(ServerAccount, AppUserInfo)
    }

    var state: State = .signedOut

    var account: ServerAccount? {
        if case let .signedIn(account, _) = state { return account }
        return nil
    }

    func signIn(account: ServerAccount, user: AppUserInfo) {
        state = .signedIn(account, user)
    }

    func signOut() {
        state = .signedOut
    }
}
