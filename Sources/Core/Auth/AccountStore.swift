import Foundation

/// Persists the configured servers. Tokens are deliberately not here — those
/// live in the keychain, keyed by account id.
struct AccountStore {
    private let defaults: UserDefaults
    private let accountsKey = "servers"
    private let currentKey = "currentServerID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var accounts: [ServerAccount] {
        guard let data = defaults.data(forKey: accountsKey),
              let decoded = try? JSONDecoder().decode([ServerAccount].self, from: data)
        else { return [] }
        return decoded
    }

    var currentAccount: ServerAccount? {
        guard let raw = defaults.string(forKey: currentKey), let id = UUID(uuidString: raw) else {
            return accounts.first
        }
        return accounts.first { $0.id == id } ?? accounts.first
    }

    func save(_ account: ServerAccount, makeCurrent: Bool = true) {
        var all = accounts
        if let index = all.firstIndex(where: { $0.id == account.id }) {
            all[index] = account
        } else {
            all.append(account)
        }
        persist(all)
        if makeCurrent {
            defaults.set(account.id.uuidString, forKey: currentKey)
        }
    }

    func remove(_ account: ServerAccount) {
        persist(accounts.filter { $0.id != account.id })
        if defaults.string(forKey: currentKey) == account.id.uuidString {
            defaults.removeObject(forKey: currentKey)
        }
    }

    func setCurrent(_ account: ServerAccount) {
        defaults.set(account.id.uuidString, forKey: currentKey)
    }

    private func persist(_ all: [ServerAccount]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: accountsKey)
    }
}
