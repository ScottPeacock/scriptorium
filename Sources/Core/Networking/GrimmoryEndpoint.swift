import Foundation

/// Every Grimmory route the app talks to, in one place.
///
/// Two things here are counterintuitive and were both verified against the
/// server source rather than inferred:
///
/// - Covers live under `/api/v1/media/book/{id}/...` (`BookMediaController`).
///   The `thumbnailUrl` that `AppBookSummary` carries says `/api/books/{id}/cover`,
///   which no controller maps — the web frontend rewrites it. Build cover URLs
///   from this enum, never from that field.
/// - `/api/v1/version` requires authentication, so the server-version gate has
///   to run after sign-in rather than during server discovery.
enum GrimmoryEndpoint {
    // Anonymous — usable before login.
    case healthcheck
    case publicSettings
    case login
    case refresh

    // Identity
    case version
    case currentUser

    /// Browsing
    case libraries
    /// The web UI's library endpoint, used when the app one 500s.
    case librariesFallback
    case shelves
    case magicShelves
    case magicShelfBooks(id: Int64, page: Int, size: Int)
    case books(BookQuery)
    case bookDetail(id: Int64)
    case bookProgress(id: Int64)
    case searchBooks(query: String, page: Int, size: Int)
    case continueReading(limit: Int)
    case recentlyAdded(limit: Int)
    case series(page: Int, size: Int, libraryId: Int64?)
    case seriesBooks(name: String, page: Int, size: Int)
    case authors(page: Int, size: Int, libraryId: Int64?)
    case filterOptions(libraryId: Int64?)

    // Media and files
    case thumbnail(bookId: Int64)
    case cover(bookId: Int64)
    case downloadBook(bookId: Int64)
    case downloadFile(bookId: Int64, fileId: Int64)

    // Mutations
    case updateStatus(bookId: Int64)
    case updateRating(bookId: Int64)

    var method: String {
        switch self {
        case .login, .refresh: "POST"
        case .bookProgress, .updateStatus, .updateRating: "PUT"
        default: "GET"
        }
    }

    var path: String {
        switch self {
        case .healthcheck: "/api/v1/healthcheck"
        case .publicSettings: "/api/v1/public-settings"
        case .login: "/api/v1/auth/login"
        case .refresh: "/api/v1/auth/refresh"
        case .version: "/api/v1/version"
        case .currentUser: "/api/v1/app/users/me"
        case .libraries: "/api/v1/app/libraries"
        case .librariesFallback: "/api/v1/libraries"
        case .shelves: "/api/v1/app/shelves"
        case .magicShelves: "/api/v1/app/shelves/magic"
        case let .magicShelfBooks(id, _, _): "/api/v1/app/shelves/magic/\(id)/books"
        case .books: "/api/v1/app/books"
        case let .bookDetail(id): "/api/v1/app/books/\(id)"
        case let .bookProgress(id): "/api/v1/app/books/\(id)/progress"
        case .searchBooks: "/api/v1/app/books/search"
        case .continueReading: "/api/v1/app/books/continue-reading"
        case .recentlyAdded: "/api/v1/app/books/recently-added"
        case .series: "/api/v1/app/series"
        case let .seriesBooks(name, _, _):
            // Series are keyed by name, so the name is a path segment. Encode
            // it here (excluding "/", which would otherwise split the segment)
            // and assign via percentEncodedPath below — letting URLComponents
            // encode an already-encoded string turns a space into %2520.
            "/api/v1/app/series/\(Self.encodePathSegment(name))/books"
        case .authors: "/api/v1/app/authors"
        case .filterOptions: "/api/v1/app/filter-options"
        case let .thumbnail(bookId): "/api/v1/media/book/\(bookId)/thumbnail"
        case let .cover(bookId): "/api/v1/media/book/\(bookId)/cover"
        case let .downloadBook(bookId): "/api/v1/books/\(bookId)/download"
        case let .downloadFile(bookId, fileId): "/api/v1/books/\(bookId)/files/\(fileId)/download"
        case let .updateStatus(bookId): "/api/v1/app/books/\(bookId)/status"
        case let .updateRating(bookId): "/api/v1/app/books/\(bookId)/rating"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case let .books(query):
            return query.queryItems

        case let .searchBooks(query, page, size):
            // The server binds this to `q`, not `query` or `search`.
            return [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "size", value: "\(size)")
            ]

        case let .continueReading(limit), let .recentlyAdded(limit):
            return [URLQueryItem(name: "limit", value: "\(limit)")]

        case let .magicShelfBooks(_, page, size), let .seriesBooks(_, page, size):
            return [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "size", value: "\(size)")
            ]

        case let .series(page, size, libraryId), let .authors(page, size, libraryId):
            var items = [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "size", value: "\(size)")
            ]
            if let libraryId {
                items.append(URLQueryItem(name: "libraryId", value: "\(libraryId)"))
            }
            return items

        case let .filterOptions(libraryId):
            guard let libraryId else { return [] }
            return [URLQueryItem(name: "libraryId", value: "\(libraryId)")]

        default:
            return []
        }
    }

    /// Endpoints reachable without a token. Everything else 401s.
    var isAnonymous: Bool {
        switch self {
        case .healthcheck, .publicSettings, .login, .refresh: true
        default: false
        }
    }

    func url(base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // `path` is already percent-encoded, so join onto the encoded form.
        let prefix = components.percentEncodedPath
        components.percentEncodedPath = prefix.hasSuffix("/")
            ? String(prefix.dropLast()) + path
            : prefix + path
        let items = queryItems
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    /// Percent-encodes a single path segment. `.urlPathAllowed` permits "/",
    /// which would silently split the segment, so drop it.
    private static func encodePathSegment(_ value: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
