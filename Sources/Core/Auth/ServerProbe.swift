import Foundation

/// Pre-login server discovery.
///
/// Only two endpoints answer anonymously — `/api/v1/healthcheck` and
/// `/api/v1/public-settings`. `/api/v1/version` is authenticated (verified
/// against a live 26.x server), so the version compatibility gate has to wait
/// until after sign-in.
struct ServerProbe: Sendable {
    struct Result: Sendable {
        let settings: PublicSettings
    }

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func probe(baseURL: URL) async throws -> Result {
        // Healthcheck first: it distinguishes "nothing is listening" from
        // "something is listening but isn't Grimmory".
        _ = try await get(.healthcheck, baseURL: baseURL)
        let data = try await get(.publicSettings, baseURL: baseURL)
        do {
            return try Result(settings: JSONCoding.decoder.decode(PublicSettings.self, from: data))
        } catch {
            throw APIError.notGrimmory(status: 200)
        }
    }

    private func get(_ endpoint: GrimmoryEndpoint, baseURL: URL) async throws -> Data {
        guard let url = endpoint.url(base: baseURL) else { throw APIError.invalidServerURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.notGrimmory(status: -1)
            }
            guard http.statusCode == 200 else {
                throw APIError.notGrimmory(status: http.statusCode)
            }
            return data
        } catch let error as URLError {
            throw APIError.from(urlError: error)
        }
    }
}

/// Signs in against a server that has already been probed.
struct AuthService: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func login(baseURL: URL, username: String, password: String) async throws -> AccessToken {
        guard let url = GrimmoryEndpoint.login.url(base: baseURL) else {
            throw APIError.invalidServerURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONCoding.encoder.encode(
            LoginRequest(username: username, password: password)
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.notGrimmory(status: -1)
            }
            switch http.statusCode {
            case 200 ..< 300:
                return try JSONCoding.decoder.decode(AccessToken.self, from: data)
            case 401, 403:
                throw APIError.unauthorized
            default:
                let body = try? JSONCoding.decoder.decode(ServerErrorBody.self, from: data)
                throw APIError.server(status: http.statusCode, message: body?.message ?? body?.error)
            }
        } catch let error as URLError {
            throw APIError.from(urlError: error)
        }
    }
}
