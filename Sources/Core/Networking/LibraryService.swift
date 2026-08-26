import Foundation

/// Read-side wrapper over `GrimmoryClient` for everything the browser needs.
/// Keeps endpoint shapes (page vs bare array) out of the views.
struct LibraryService: Sendable {
    typealias BookPage = AppPageResponse<AppBookSummary>
    typealias SeriesPage = AppPageResponse<AppSeriesSummary>
    typealias AuthorPage = AppPageResponse<AppAuthorSummary>

    let client: GrimmoryClient

    func books(_ query: BookQuery) async throws -> BookPage {
        try await client.send(.books(query))
    }

    func search(_ text: String, page: Int = 0, size: Int = 40) async throws -> BookPage {
        try await client.send(.searchBooks(query: text, page: page, size: size))
    }

    /// These two return a bare array, not a page — the server treats them as
    /// fixed-length home-screen rows.
    func continueReading(limit: Int = 10) async throws -> [AppBookSummary] {
        try await client.send(.continueReading(limit: limit))
    }

    func recentlyAdded(limit: Int = 10) async throws -> [AppBookSummary] {
        try await client.send(.recentlyAdded(limit: limit))
    }

    func libraries() async throws -> [AppLibrarySummary] {
        try await client.send(.libraries)
    }

    func shelves() async throws -> [AppShelfSummary] {
        try await client.send(.shelves)
    }

    func magicShelves() async throws -> [AppMagicShelfSummary] {
        try await client.send(.magicShelves)
    }

    func series(page: Int = 0, size: Int = 40, libraryId: Int64? = nil) async throws -> SeriesPage {
        try await client.send(.series(page: page, size: size, libraryId: libraryId))
    }

    func seriesBooks(name: String, page: Int = 0, size: Int = 40) async throws -> BookPage {
        try await client.send(.seriesBooks(name: name, page: page, size: size))
    }

    func authors(page: Int = 0, size: Int = 60, libraryId: Int64? = nil) async throws -> AuthorPage {
        try await client.send(.authors(page: page, size: size, libraryId: libraryId))
    }

    func bookDetail(id: Int64) async throws -> AppBookDetail {
        try await client.send(.bookDetail(id: id))
    }

    func currentUser() async throws -> AppUserInfo {
        try await client.send(.currentUser)
    }
}
