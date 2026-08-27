import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case invalidServerURL
    /// Host unreachable, DNS failure, or the local-network permission was denied.
    case unreachable(underlying: String)
    case tls(underlying: String)
    /// Reached something, but it does not look like a Grimmory server.
    case notGrimmory(status: Int)
    case unauthorized
    case forbidden
    case notFound
    case server(status: Int, message: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "That doesn't look like a valid server address."
        case let .unreachable(underlying):
            "Couldn't reach the server. \(underlying)"
        case let .tls(underlying):
            "The secure connection failed. \(underlying)"
        case .notGrimmory:
            "Reached that address, but it isn't a Grimmory server."
        case .unauthorized:
            "Your username or password wasn't accepted."
        case .forbidden:
            "Your account doesn't have permission for that."
        case .notFound:
            "The server doesn't have that item."
        case let .server(status, message):
            message ?? "The server returned an error (\(status))."
        case let .decoding(detail):
            "The server's response wasn't in the expected format. \(detail)"
        }
    }

    /// Maps a URLError into the categories onboarding needs to distinguish.
    static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            .tls(underlying: urlError.localizedDescription)
        default:
            .unreachable(underlying: urlError.localizedDescription)
        }
    }
}

/// Grimmory returns two shapes: its own `ErrorResponse`
/// (`{"status":400,"message":"...","details":[...]}`) from GlobalExceptionHandler,
/// and Spring's default (`{"status":401,"error":"Unauthorized","path":"..."}`)
/// for anything that never reaches a controller.
struct ServerErrorBody: Decodable, Sendable {
    let status: Int?
    let error: String?
    let message: String?
    let path: String?
    let details: [String]?

    /// The most specific thing the server said, or nil if it said nothing useful.
    var displayMessage: String? {
        if let message, !message.isEmpty {
            if let details, !details.isEmpty {
                return "\(message) (\(details.joined(separator: "; ")))"
            }
            return message
        }
        return error.flatMap { $0.isEmpty ? nil : $0 }
    }
}
