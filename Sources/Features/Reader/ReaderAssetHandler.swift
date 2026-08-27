import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the reader page, foliate-js, and the book itself over a custom
/// scheme.
///
/// `file://` would be simpler, but WKWebView blocks ES module imports across
/// file URLs, and foliate-js is a set of ES modules. A custom scheme sidesteps
/// that. Everything is served from one host so the page can `fetch` the book
/// without tripping over cross-origin rules.
final class ReaderAssetHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "scriptorium"
    static let host = "app"
    static let bookPath = "/book.epub"

    static var readerURL: URL {
        URL(string: "\(scheme)://\(host)/reader.html")!
    }

    private let bookURL: URL
    private let foliateDirectory: URL?
    private let readerDirectory: URL?

    init(bookURL: URL, bundle: Bundle = .main) {
        self.bookURL = bookURL
        foliateDirectory = bundle.url(forResource: "foliate", withExtension: nil)
        readerDirectory = bundle.url(forResource: "reader", withExtension: nil)
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let path = normalizedPath(for: url) else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        guard let fileURL = resolve(path: path) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": Self.mimeType(for: fileURL),
                    "Content-Length": "\(data.count)",
                    // Same-origin already, but Safari is strict about module
                    // requests over custom schemes.
                    "Access-Control-Allow-Origin": "*"
                ]
            )!
            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    // MARK: - Resolution

    // Internal rather than private so the path rules can be tested directly:
    // a traversal bug here would expose the app container.

    func normalizedPath(for url: URL) -> String? {
        guard url.scheme == Self.scheme, url.host == Self.host else { return nil }
        let path = url.path
        // Refuse traversal outright rather than trying to sanitise it.
        guard !path.contains("..") else { return nil }
        return path
    }

    func resolve(path: String) -> URL? {
        if path == Self.bookPath {
            return bookURL
        }
        if path.hasPrefix("/foliate/") {
            let relative = String(path.dropFirst("/foliate/".count))
            return foliateDirectory?.appendingPathComponent(relative)
        }
        let name = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return readerDirectory?.appendingPathComponent(name.isEmpty ? "reader.html" : name)
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json": "application/json"
        case "epub": "application/epub+zip"
        case "svg": "image/svg+xml"
        default:
            UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
        }
    }
}
