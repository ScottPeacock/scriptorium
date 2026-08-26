import Foundation
import Observation

@Observable
@MainActor
final class AddServerViewModel {
    enum Phase: Equatable {
        case enteringAddress
        case probing
        case enteringCredentials(PublicSettingsSnapshot)
        case signingIn
    }

    /// PublicSettings is Decodable-only; this is the bit the UI branches on.
    struct PublicSettingsSnapshot: Equatable {
        let oidcEnabled: Bool
        let supportsLocalLogin: Bool
    }

    var address = ""
    var username = ""
    var password = ""
    var phase: Phase = .enteringAddress
    var errorMessage: String?

    private var resolvedBaseURL: URL?
    private let probe = ServerProbe()
    private let auth = AuthService()

    var canProbe: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty && phase == .enteringAddress
    }

    var canSignIn: Bool {
        if case .enteringCredentials = phase {
            return !username.isEmpty && !password.isEmpty
        }
        return false
    }

    func connect() async {
        guard let url = ServerAccount.normalizeBaseURL(address) else {
            errorMessage = APIError.invalidServerURL.localizedDescription
            return
        }
        errorMessage = nil
        phase = .probing

        do {
            let result = try await probe.probe(baseURL: url)
            resolvedBaseURL = url
            phase = .enteringCredentials(
                .init(
                    oidcEnabled: result.settings.oidcEnabled,
                    supportsLocalLogin: result.settings.supportsLocalLogin
                )
            )
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            phase = .enteringAddress
        }
    }

    func signIn(into session: SessionModel) async {
        guard let baseURL = resolvedBaseURL else { return }
        let previousPhase = phase
        errorMessage = nil
        phase = .signingIn

        do {
            let token = try await auth.login(baseURL: baseURL, username: username, password: password)

            let account = ServerAccount(
                displayName: baseURL.host() ?? "Grimmory",
                baseURL: baseURL,
                username: username
            )
            let store = TokenStore(account: account)
            try await store.store(token)

            let client = GrimmoryClient(baseURL: baseURL, tokenStore: store)
            let user: AppUserInfo = try await client.send(.currentUser)

            password = ""
            session.signIn(account: account, user: user)
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            phase = previousPhase
        }
    }

    func editAddress() {
        phase = .enteringAddress
        errorMessage = nil
    }
}
