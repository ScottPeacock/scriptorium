import Foundation

/// Every Grimmory route the app talks to, in one place.
///
/// Note the inconsistent bases: covers live under `/api/books/...` while
/// everything else is `/api/v1/...`. That is the server's shape, not a typo —
/// see `AppBookMapper.mapThumbnailUrl`.
enum GrimmoryEndpoint {
    // Anonymous — usable before login.
    case healthcheck
    case publicSettings

    // Auth
    case login
    case refresh

    // Authenticated
    case version
    case currentUser
    case libraries
    case shelves
    case magicShelves
    case books(page: Int, size: Int)
    case bookDetail(id: Int64)
    case bookProgress(id: Int64)
    case searchBooks(query: String, page: Int, size: Int)
    case continueReading
    case recentlyAdded
    case filterOptions
    case cover(bookId: Int64)
    case downloadBook(bookId: Int64)
    case downloadFile(bookId: Int64, fileId: Int64)

    var method: String {
        switch self {
        case .login, .refresh: "POST"
        case .bookProgress: "PUT"
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
        case .shelves: "/api/v1/app/shelves"
        case .magicShelves: "/api/v1/app/shelves/magic"
        case .books: "/api/v1/app/books"
        case let .bookDetail(id): "/api/v1/app/books/\(id)"
        case let .bookProgress(id): "/api/v1/app/books/\(id)/progress"
        case .searchBooks: "/api/v1/app/books/search"
        case .continueReading: "/api/v1/app/books/continue-reading"
        case .recentlyAdded: "/api/v1/app/books/recently-added"
        case .filterOptions: "/api/v1/app/filter-options"
        case let .cover(bookId): "/api/books/\(bookId)/cover"
        case let .downloadBook(bookId): "/api/v1/books/\(bookId)/download"
        case let .downloadFile(bookId, fileId): "/api/v1/books/\(bookId)/files/\(fileId)/download"
        }
    }

    var queryItems: [URLQueryItem] {
        switch self {
        case let .books(page, size):
            [.init(name: "page", value: "\(page)"), .init(name: "size", value: "\(size)")]
        case let .searchBooks(query, page, size):
            [
                .init(name: "query", value: query),
                .init(name: "page", value: "\(page)"),
                .init(name: "size", value: "\(size)"),
            ]
        default:
            []
        }
    }

    /// Endpoints reachable without a token. Everything else 401s — including
    /// `/api/v1/version`, which is why the version gate runs after login.
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
        components.path = (components.path as NSString).appendingPathComponent(path)
        let items = queryItems
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}
