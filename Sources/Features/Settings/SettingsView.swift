import SwiftUI

struct SettingsView: View {
    let connection: ServerConnection

    @Environment(SessionModel.self) private var session
    @State private var cacheSize: Int64 = 0
    @State private var showSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Server") {
                    LabeledContent("Address", value: connection.account.baseURL.absoluteString)
                    LabeledContent("Signed in as", value: connection.account.username)
                    if let version = connection.account.serverVersion {
                        LabeledContent("Grimmory", value: version)
                    }
                }

                Section("Permissions") {
                    LabeledContent("Administrator", value: connection.user.isAdmin ? "Yes" : "No")
                    LabeledContent("Can download", value: connection.user.canDownload ? "Yes" : "No")
                }

                Section {
                    LabeledContent("Waiting to sync", value: syncLabel)
                    if connection.progress.pendingCount > 0 {
                        Button("Sync now") {
                            Task { await connection.progress.flush() }
                        }
                    }
                    if connection.progress.pendingCount > 0, let error = connection.progress.lastError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Reading positions")
                } footer: {
                    Text("Positions are saved here first, then sent to your server when it's reachable.")
                }

                Section {
                    LabeledContent("Downloaded books", value: downloadsSize)
                    LabeledContent("Cached covers", value: formattedSize)
                    Button("Clear cover cache") {
                        Task {
                            await connection.covers.clearCache()
                            await refreshCacheSize()
                        }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Covers are cached on this device only, and redownload as you browse.")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } footer: {
                    Text("Open source under the MPL-2.0. Talks to your server and nothing else.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Sign out of \(connection.account.displayName)?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
            } message: {
                Text("Downloaded books and cached covers for this server will be removed from this device.")
            }
            .task { await refreshCacheSize() }
        }
    }

    private var syncLabel: String {
        let pending = connection.progress.pendingCount
        if pending == 0 {
            return connection.progress.isOnline ? "Up to date" : "Up to date (offline)"
        }
        return "\(pending) change\(pending == 1 ? "" : "s")"
    }

    private var downloadsSize: String {
        let bytes = connection.downloads.totalBytes
        let count = connection.downloads.downloads.count
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return count == 0 ? "None" : "\(count) · \(size)"
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func refreshCacheSize() async {
        cacheSize = await connection.covers.cacheSizeBytes()
    }
}
