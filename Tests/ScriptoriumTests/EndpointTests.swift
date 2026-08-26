import Foundation
@testable import Scriptorium
import Testing

@Suite("Endpoint URL construction")
struct EndpointTests {
    private let base = URL(string: "http://192.168.1.21:6060")!

    @Test("Anonymous endpoints are exactly the two the server allows")
    func anonymousSet() {
        #expect(GrimmoryEndpoint.healthcheck.isAnonymous)
        #expect(GrimmoryEndpoint.publicSettings.isAnonymous)
        #expect(GrimmoryEndpoint.login.isAnonymous)
        #expect(GrimmoryEndpoint.refresh.isAnonymous)
        // Verified 401 against a live server — the version gate runs post-login.
        #expect(!GrimmoryEndpoint.version.isAnonymous)
    }

    /// AppBookSummary.thumbnailUrl claims "/api/books/{id}/cover", but no
    /// controller maps /api/books — the web frontend rewrites it. The real
    /// route is BookMediaController at /api/v1/media. Trusting the server's
    /// own field here would have broken every cover in the app.
    @Test("Covers resolve to the media controller, not the advertised thumbnailUrl")
    func coverPath() throws {
        let url = try #require(GrimmoryEndpoint.cover(bookId: 42).url(base: base))
        #expect(url.absoluteString == "http://192.168.1.21:6060/api/v1/media/book/42/cover")
    }

    @Test("Grids use the smaller thumbnail endpoint")
    func thumbnailPath() throws {
        let url = try #require(GrimmoryEndpoint.thumbnail(bookId: 42).url(base: base))
        #expect(url.absoluteString == "http://192.168.1.21:6060/api/v1/media/book/42/thumbnail")
    }

    @Test("Search binds the query to `q`, which is what the controller declares")
    func searchParameter() throws {
        let url = try #require(
            GrimmoryEndpoint.searchBooks(query: "dune", page: 0, size: 20).url(base: base)
        )
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "q", value: "dune")))
        #expect(!query.contains { $0.name == "query" })
    }

    @Test("Series names with spaces are percent-encoded into the path")
    func seriesPathEncoding() throws {
        let url = try #require(
            GrimmoryEndpoint.seriesBooks(name: "The Expanse", page: 0, size: 20).url(base: base)
        )
        #expect(url.absoluteString.contains("/api/v1/app/series/The%20Expanse/books"))
    }

    @Test("App endpoints use the /api/v1/app base")
    func appPath() throws {
        let url = try #require(GrimmoryEndpoint.bookDetail(id: 7).url(base: base))
        #expect(url.absoluteString == "http://192.168.1.21:6060/api/v1/app/books/7")
    }

    @Test("Paging is carried as query items")
    func paging() throws {
        var query = BookQuery()
        query.page = 2
        query.size = 50
        let url = try #require(GrimmoryEndpoint.books(query).url(base: base))
        #expect(url.absoluteString.contains("page=2"))
        #expect(url.absoluteString.contains("size=50"))
    }

    @Test("A base URL with a subpath is preserved, not overwritten")
    func subpathBase() throws {
        let proxied = try #require(URL(string: "https://example.com/grimmory"))
        let url = try #require(GrimmoryEndpoint.healthcheck.url(base: proxied))
        #expect(url.absoluteString == "https://example.com/grimmory/api/v1/healthcheck")
    }

    @Test("A series name with a slash stays inside one path segment")
    func seriesPathSlash() throws {
        let url = try #require(
            GrimmoryEndpoint.seriesBooks(name: "Sci-Fi/Fantasy", page: 0, size: 20).url(base: base)
        )
        #expect(url.absoluteString.contains("/api/v1/app/series/Sci-Fi%2FFantasy/books"))
    }

    @Test("A base URL ending in a slash does not produce a doubled separator")
    func trailingSlashBase() throws {
        let slashed = try #require(URL(string: "http://box:6060/"))
        let url = try #require(GrimmoryEndpoint.healthcheck.url(base: slashed))
        #expect(url.absoluteString == "http://box:6060/api/v1/healthcheck")
    }

    @Test("Progress writes use PUT")
    func progressMethod() {
        #expect(GrimmoryEndpoint.bookProgress(id: 1).method == "PUT")
        #expect(GrimmoryEndpoint.login.method == "POST")
        #expect(GrimmoryEndpoint.books(BookQuery()).method == "GET")
    }
}
