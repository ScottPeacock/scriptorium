import Foundation
@testable import Scriptorium
import Testing
import UIKit
import WebKit

/// Runs the production reader page offscreen and lets tests await its messages.
///
/// Uses the real `ReaderAssetHandler` and the real `ReaderWebView.Coordinator`,
/// so what's under test is the shipping bridge rather than a stand-in. The web
/// view is attached to a window because foliate's paginator lays out against
/// real dimensions — a zero-sized view never paginates and never relocates.
@MainActor
final class ReaderHarness {
    struct Ready {
        let toc: [TOCEntry]
        let title: String?
    }

    let commands = ReaderCommands()

    private let window: UIWindow
    private let webView: WKWebView
    private let coordinator: ReaderWebView.Coordinator

    private var ready: Ready?
    private var locations: [ReaderLocation] = []
    private var failure: String?

    private let box: MessageBox

    init(bookURL: URL, startCFI: String? = nil, settings: ReaderSettings = ReaderSettings()) throws {
        let box = MessageBox()
        self.box = box
        coordinator = ReaderWebView.Coordinator { message in
            box.append(message)
        }

        let configuration = WKWebViewConfiguration()
        // Bundle.main is the host app here, which is where foliate and the
        // reader page are bundled.
        configuration.setURLSchemeHandler(
            ReaderAssetHandler(bookURL: bookURL),
            forURLScheme: ReaderAssetHandler.scheme
        )
        configuration.userContentController.add(coordinator, name: "reader")

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.addSubview(webView)
        window.isHidden = false
        window.makeKeyAndVisible()

        coordinator.webView = webView
        commands.attach(coordinator: coordinator)
        coordinator.pendingOpen = .init(bookURL: bookURL, startCFI: startCFI, settings: settings)

        webView.load(URLRequest(url: ReaderAssetHandler.readerURL))
    }

    deinit {
        let webView = self.webView
        Task { @MainActor in
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
            webView.removeFromSuperview()
        }
    }

    func waitForReady(timeout: Duration = .seconds(25)) async throws -> Ready {
        try await poll(timeout: timeout, describing: "the book to open") {
            self.drain()
            if let failure = self.failure {
                throw ReaderHarnessError.pageFailed(failure)
            }
            return self.ready
        }
    }

    func waitForLocation(
        timeout: Duration = .seconds(25),
        matching predicate: @escaping (ReaderLocation) -> Bool
    ) async throws -> ReaderLocation {
        try await poll(timeout: timeout, describing: "a matching position") {
            self.drain()
            if let failure = self.failure {
                throw ReaderHarnessError.pageFailed(failure)
            }
            return self.locations.last(where: predicate)
        }
    }

    /// Renders the live reader to a PNG. Used to eyeball typography and theming
    /// without a server round trip — the bridge tests prove behaviour, this
    /// shows what a reader actually sees.
    func snapshot(to url: URL) throws {
        let renderer = UIGraphicsImageRenderer(bounds: webView.bounds)
        let image = renderer.image { _ in
            webView.drawHierarchy(in: webView.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            throw ReaderHarnessError.pageFailed("Couldn't encode the snapshot")
        }
        try data.write(to: url)
    }

    private func drain() {
        for message in box.take() {
            switch message {
            case let .ready(toc, title):
                ready = Ready(toc: toc, title: title)
            case let .relocate(location):
                locations.append(location)
            case let .failed(message):
                failure = message
            case .tap:
                break
            case .showChrome:
                break
            }
        }
    }

    private func poll<T>(
        timeout: Duration,
        describing what: String,
        _ check: () throws -> T?
    ) async throws -> T {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if let value = try check() {
                return value
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ReaderHarnessError.timedOut(what)
    }
}

enum ReaderHarnessError: Error, CustomStringConvertible {
    case timedOut(String)
    case pageFailed(String)

    var description: String {
        switch self {
        case let .timedOut(what): "Timed out waiting for \(what)"
        case let .pageFailed(message): "The reader page reported: \(message)"
        }
    }
}

/// Buffers messages so the harness can drain them from an async context.
@MainActor
private final class MessageBox {
    private var pending: [ReaderMessage] = []

    func append(_ message: ReaderMessage) {
        pending.append(message)
    }

    func take() -> [ReaderMessage] {
        defer { pending.removeAll() }
        return pending
    }
}
