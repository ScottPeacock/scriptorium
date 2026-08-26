import Foundation
@testable import Scriptorium
import Testing

@Suite("Server address normalisation")
struct ServerAccountTests {
    @Test("Bare host and port gets an http scheme")
    func bareHostPort() throws {
        let url = try #require(ServerAccount.normalizeBaseURL("192.168.1.21:6060"))
        #expect(url.absoluteString == "http://192.168.1.21:6060")
    }

    @Test("An explicit scheme is preserved")
    func explicitScheme() throws {
        let url = try #require(ServerAccount.normalizeBaseURL("https://books.example.com"))
        #expect(url.absoluteString == "https://books.example.com")
    }

    @Test("Trailing slashes are trimmed so path joining stays predictable")
    func trailingSlash() throws {
        let url = try #require(ServerAccount.normalizeBaseURL("http://box:6060///"))
        #expect(url.absoluteString == "http://box:6060")
    }

    @Test("A reverse-proxy subpath survives normalisation")
    func subpath() throws {
        let url = try #require(ServerAccount.normalizeBaseURL("https://example.com/grimmory/"))
        #expect(url.absoluteString == "https://example.com/grimmory")
    }

    @Test("Surrounding whitespace is tolerated")
    func whitespace() throws {
        let url = try #require(ServerAccount.normalizeBaseURL("  192.168.1.21:6060  "))
        #expect(url.absoluteString == "http://192.168.1.21:6060")
    }

    @Test("Empty and junk input is rejected", arguments: ["", "   ", "://"])
    func rejectsJunk(input: String) {
        #expect(ServerAccount.normalizeBaseURL(input) == nil)
    }
}
