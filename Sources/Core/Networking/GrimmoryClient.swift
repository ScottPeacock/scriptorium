import Foundation

/// Talks to one Grimmory server.
///
/// Refreshing is single-flight: a library screen fires a page request plus a
/// dozen cover requests at once, and if the access token has just expired every
/// one of them gets a 401. Without the guard that's a dozen concurrent refresh
/// calls, and Grimmory rotates the refresh token — all but one would fail and
/// log the user out. `refreshTask` collapses them into one.
actor GrimmoryClient {
    private let baseURL: URL
    private let tokenStore: TokenStore
    private let session: URLSession
    private var refreshTask: Task<Tokens, Error>?

    init(baseURL: URL, tokenStore: TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    // MARK: - Public surface

    func send<T: Decodable & Sendable>(
        _ endpoint: GrimmoryEndpoint,
        body: (some Encodable)? = Optional<Never>.none,
        as _: T.Type = T.self
    ) async throws -> T {
        let data = try await sendForData(endpoint, body: body)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    func sendForData(
        _ endpoint: GrimmoryEndpoint,
        body: (some Encodable)? = Optional<Never>.none
    ) async throws -> Data {
        let (data, response) = try await perform(endpoint, body: body, allowRefresh: true)
        try Self.validate(response: response, data: data, endpoint: endpoint)
        return data
    }

    // MARK: - Request plumbing

    private func perform(
        _ endpoint: GrimmoryEndpoint,
        body: (some Encodable)?,
        allowRefresh: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        var request = try buildRequest(endpoint, body: body)

        if !endpoint.isAnonymous {
            guard let tokens = await currentTokens() else { throw APIError.unauthorized }
            request.setValue("Bearer \(tokens.access)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await execute(request)

        // One retry, and only for authenticated endpoints — a 401 from /login
        // means bad credentials, not a stale token.
        if response.statusCode == 401, !endpoint.isAnonymous, allowRefresh {
            let refreshed = try await refreshTokens()
            var retry = try buildRequest(endpoint, body: body)
            retry.setValue("Bearer \(refreshed.access)", forHTTPHeaderField: "Authorization")
            return try await execute(retry)
        }

        return (data, response)
    }

    private func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.notGrimmory(status: -1)
            }
            return (data, http)
        } catch let error as URLError {
            throw APIError.from(urlError: error)
        }
    }

    private func buildRequest(
        _ endpoint: GrimmoryEndpoint,
        body: (some Encodable)?
    ) throws -> URLRequest {
        guard let url = endpoint.url(base: baseURL) else { throw APIError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONCoding.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func currentTokens() async -> Tokens? {
        await tokenStore.load()
    }

    // MARK: - Token refresh

    private func refreshTokens() async throws -> Tokens {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task<Tokens, Error> { [tokenStore, baseURL, session] in
            guard let existing = await tokenStore.load(), let refreshToken = existing.refresh else {
                await tokenStore.clear()
                throw APIError.unauthorized
            }

            guard let url = GrimmoryEndpoint.refresh.url(base: baseURL) else {
                throw APIError.invalidServerURL
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONCoding.encoder.encode(RefreshTokenRequest(refreshToken: refreshToken))

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError {
                throw APIError.from(urlError: error)
            }

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                // The refresh token is spent or revoked; the user must sign in again.
                await tokenStore.clear()
                throw APIError.unauthorized
            }

            let token = try JSONCoding.decoder.decode(AccessToken.self, from: data)
            try await tokenStore.store(token)
            guard let tokens = await tokenStore.load() else { throw APIError.unauthorized }
            return tokens
        }

        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - Response validation

    private static func validate(
        response: HTTPURLResponse,
        data: Data,
        endpoint: GrimmoryEndpoint
    ) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            // A 404 on an endpoint we know Grimmory serves means we're pointed
            // at something else — a different app, or a reverse proxy misroute.
            throw endpoint.isAnonymous ? APIError.notGrimmory(status: 404) : APIError.notFound
        default:
            let body = try? JSONCoding.decoder.decode(ServerErrorBody.self, from: data)
            throw APIError.server(status: response.statusCode, message: body?.message ?? body?.error)
        }
    }
}
