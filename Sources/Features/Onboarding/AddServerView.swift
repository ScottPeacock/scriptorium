import SwiftUI

struct AddServerView: View {
    @Environment(SessionModel.self) private var session
    @State private var model = AddServerViewModel()
    @FocusState private var focus: Field?

    private enum Field { case address, username, password }

    var body: some View {
        NavigationStack {
            Form {
                addressSection

                if case let .enteringCredentials(settings) = model.phase {
                    credentialsSection(settings)
                } else if model.phase == .signingIn {
                    credentialsSection(nil)
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Connect to Grimmory")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var addressSection: some View {
        Section {
            TextField("192.168.1.21:6060", text: $model.address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($focus, equals: .address)
                .disabled(model.phase != .enteringAddress)
                .onSubmit { Task { await model.connect() } }

            switch model.phase {
            case .enteringAddress:
                Button("Continue") {
                    Task { await model.connect() }
                }
                .disabled(!model.canProbe)
            case .probing:
                HStack {
                    ProgressView()
                    Text("Looking for a server…").foregroundStyle(.secondary)
                }
            default:
                Button("Change address", action: model.editAddress)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Server address")
        } footer: {
            Text("Your Grimmory server's address, with the port if it isn't 80. Plain http is fine on a local network.")
        }
    }

    private func credentialsSection(_ settings: AddServerViewModel.PublicSettingsSnapshot?) -> some View {
        Section("Sign in") {
            TextField("Username", text: $model.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .focused($focus, equals: .username)

            SecureField("Password", text: $model.password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .onSubmit { Task { await model.signIn(into: session) } }

            if model.phase == .signingIn {
                HStack {
                    ProgressView()
                    Text("Signing in…").foregroundStyle(.secondary)
                }
            } else {
                Button("Sign in") {
                    Task { await model.signIn(into: session) }
                }
                .disabled(!model.canSignIn)
            }

            if let settings, settings.oidcEnabled {
                // OIDC is out of scope for v1; say so rather than showing a
                // dead button to someone whose server is configured for it.
                Text("This server also offers single sign-on, which Scriptorium doesn't support yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    AddServerView().environment(SessionModel())
}
