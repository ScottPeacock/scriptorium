import Foundation

/// `org.booklore.model.dto.AccessTokenDto`
struct AccessToken: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    /// Epoch milliseconds at which `accessToken` expires, when the server sends it.
    let expires: Int64?
    let isDefaultPassword: Bool?

    var expiryDate: Date? {
        expires.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }
}

/// `org.booklore.model.dto.request.UserLoginRequest`
struct LoginRequest: Encodable, Sendable {
    let username: String
    let password: String
}

struct RefreshTokenRequest: Encodable, Sendable {
    let refreshToken: String
}

/// `GET /api/v1/public-settings` — anonymous. The only pre-login endpoint that
/// tells us anything useful about the server, so onboarding branches on it.
struct PublicSettings: Decodable, Sendable {
    let oidcEnabled: Bool
    let remoteAuthEnabled: Bool
    let oidcForceOnlyMode: Bool

    private enum CodingKeys: String, CodingKey {
        case oidcEnabled, remoteAuthEnabled, oidcForceOnlyMode
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        oidcEnabled = try c.decodeIfPresent(Bool.self, forKey: .oidcEnabled) ?? false
        remoteAuthEnabled = try c.decodeIfPresent(Bool.self, forKey: .remoteAuthEnabled) ?? false
        oidcForceOnlyMode = try c.decodeIfPresent(Bool.self, forKey: .oidcForceOnlyMode) ?? false
    }

    /// True when the app can offer a username/password form.
    var supportsLocalLogin: Bool {
        !oidcForceOnlyMode
    }
}

/// `org.booklore.model.dto.request.BookFileProgress`
///
/// For EPUB, `positionData` is the CFI and `positionHref` the spine href —
/// see ReadingProgressService.java:154-159.
struct BookFileProgress: Encodable, Sendable {
    let bookFileId: Int64
    let positionData: String?
    let positionHref: String?
    let progressPercent: Float
    let ttsPositionCfi: String?
    let contentSourceProgressPercent: Float?

    init(
        bookFileId: Int64,
        cfi: String?,
        href: String?,
        progressPercent: Float,
        ttsPositionCfi: String? = nil,
        contentSourceProgressPercent: Float? = nil
    ) {
        self.bookFileId = bookFileId
        positionData = cfi
        positionHref = href
        self.progressPercent = progressPercent
        self.ttsPositionCfi = ttsPositionCfi
        self.contentSourceProgressPercent = contentSourceProgressPercent
    }
}

/// `org.booklore.app.dto.UpdateProgressRequest` — the per-format `epubProgress`
/// etc. fields are deprecated server-side, so we only ever send `fileProgress`.
struct UpdateProgressRequest: Encodable, Sendable {
    let fileProgress: BookFileProgress?
    let dateFinished: Date?
}
