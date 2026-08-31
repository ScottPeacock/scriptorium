import Foundation
@testable import Scriptorium
import Testing

@Suite("Reader asset handler")
struct ReaderAssetHandlerTests {
    private let bookURL = URL(fileURLWithPath: "/tmp/some-book.epub")

    private func handler() -> ReaderAssetHandler {
        ReaderAssetHandler(bookURL: bookURL)
    }

    @Test("The book path maps to the downloaded file")
    func bookPath() {
        #expect(handler().resolve(path: ReaderAssetHandler.bookPath) == bookURL)
    }

    @Test("Path traversal is refused outright")
    func rejectsTraversal() throws {
        let url = try #require(URL(string: "scriptorium://app/foliate/../../../etc/passwd"))
        #expect(handler().normalizedPath(for: url) == nil)
    }

    @Test("Other schemes and hosts are refused")
    func rejectsForeignOrigins() throws {
        let wrongScheme = try #require(URL(string: "https://app/reader.html"))
        let wrongHost = try #require(URL(string: "scriptorium://elsewhere/reader.html"))
        #expect(handler().normalizedPath(for: wrongScheme) == nil)
        #expect(handler().normalizedPath(for: wrongHost) == nil)
    }

    @Test("A legitimate module path is accepted")
    func acceptsModulePath() throws {
        let url = try #require(URL(string: "scriptorium://app/foliate/vendor/zip.js"))
        #expect(handler().normalizedPath(for: url) == "/foliate/vendor/zip.js")
    }

    /// WKWebView refuses to execute a module served as anything but a JavaScript
    /// type, so these are load-bearing rather than cosmetic.
    @Test("JavaScript is served as a script type")
    func javascriptMIME() {
        let mime = ReaderAssetHandler.mimeType(for: URL(fileURLWithPath: "/x/view.js"))
        #expect(mime.hasPrefix("text/javascript"))
    }

    @Test("HTML and EPUB get their expected types")
    func otherMIMEs() {
        let html = ReaderAssetHandler.mimeType(for: URL(fileURLWithPath: "/x/reader.html"))
        #expect(html.hasPrefix("text/html"))
        #expect(ReaderAssetHandler.mimeType(for: URL(fileURLWithPath: "/x/b.epub")) == "application/epub+zip")
    }

    @Test("The reader page and the book share an origin, so fetch isn't blocked")
    func sameOrigin() throws {
        let reader = ReaderAssetHandler.readerURL
        let book = try #require(URL(
            string: "\(ReaderAssetHandler.scheme)://\(ReaderAssetHandler.host)\(ReaderAssetHandler.bookPath)"
        ))
        #expect(reader.scheme == book.scheme)
        #expect(reader.host == book.host)
    }

    @Test("Reader bridge uses 25/50/25 tap zones and supports swipe-down chrome restore")
    func bridgeGestureZones() throws {
        let url = try #require(
            Bundle(for: ReaderAssetBundleAnchor.self).url(
                forResource: "bridge",
                withExtension: "js",
                subdirectory: "reader"
            ),
            "Missing reader/bridge.js in test bundle"
        )
        let source = try String(contentsOf: url, encoding: .utf8)

        #expect(source.contains("width * 0.25"))
        #expect(source.contains("width * 0.75"))
        #expect(source.contains("post('showChrome')"))
        #expect(source.contains("TAP_MAX_MOVE_PX"))
        #expect(source.contains("passive: false, capture: true"))
        #expect(source.contains("suppressNextClick = true"))
        #expect(source.contains("addEventListener('touchmove', event => {"))
    }
}

private final class ReaderAssetBundleAnchor {}
