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

    @Test("Covers use the /api/books base, not /api/v1")
    func coverPath() throws {
        let url = try #require(GrimmoryEndpoint.cover(bookId: 42).url(base: base))
        #expect(url.absoluteString == "http://192.168.1.21:6060/api/books/42/cover")
    }

    @Test("App endpoints use the /api/v1/app base")
    func appPath() throws {
        let url = try #require(GrimmoryEndpoint.bookDetail(id: 7).url(base: base))
        #expect(url.absoluteString == "http://192.168.1.21:6060/api/v1/app/books/7")
    }

    @Test("Paging is carried as query items")
    func paging() throws {
        let url = try #require(GrimmoryEndpoint.books(page: 2, size: 50).url(base: base))
        #expect(url.absoluteString.contains("page=2"))
        #expect(url.absoluteString.contains("size=50"))
    }

    @Test("A base URL with a subpath is preserved, not overwritten")
    func subpathBase() throws {
        let proxied = try #require(URL(string: "https://example.com/grimmory"))
        let url = try #require(GrimmoryEndpoint.healthcheck.url(base: proxied))
        #expect(url.absoluteString == "https://example.com/grimmory/api/v1/healthcheck")
    }

    @Test("Progress writes use PUT")
    func progressMethod() {
        #expect(GrimmoryEndpoint.bookProgress(id: 1).method == "PUT")
        #expect(GrimmoryEndpoint.login.method == "POST")
        #expect(GrimmoryEndpoint.books(page: 0, size: 20).method == "GET")
    }
}
