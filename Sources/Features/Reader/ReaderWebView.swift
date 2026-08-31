import SwiftUI
import WebKit

/// Hosts foliate-js and relays messages both ways.
struct ReaderWebView: UIViewRepresentable {
    let bookURL: URL
    let startCFI: String?
    let settings: ReaderSettings
    let onMessage: (ReaderMessage) -> Void
    /// Set by the coordinator so the view model can drive the page.
    let commands: ReaderCommands

    func makeCoordinator() -> Coordinator {
        Coordinator(onMessage: onMessage)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            ReaderAssetHandler(bookURL: bookURL),
            forURLScheme: ReaderAssetHandler.scheme
        )
        configuration.userContentController.add(context.coordinator, name: "reader")
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.bounces = false
        // Content scrolling belongs to foliate's renderer, not the host view.
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false

        context.coordinator.webView = webView
        commands.attach(coordinator: context.coordinator)
        context.coordinator.pendingOpen = .init(bookURL: bookURL, startCFI: startCFI, settings: settings)
        webView.load(URLRequest(url: ReaderAssetHandler.readerURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.apply(settings: settings)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: "reader")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var pendingOpen: PendingOpen?
        private var lastAppliedSettings: ReaderSettings?
        private var isReady = false
        private let onMessage: (ReaderMessage) -> Void

        init(onMessage: @escaping (ReaderMessage) -> Void) {
            self.onMessage = onMessage
        }

        nonisolated func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else { return }

            Task { @MainActor in
                self.handle(type: type, body: body)
            }
        }

        private func handle(type: String, body: [String: Any]) {
            switch type {
            case "bridgeReady":
                isReady = true
                openPendingBook()
            case "ready":
                let toc = (body["toc"] as? [[String: Any]] ?? []).map {
                    TOCEntry(
                        label: $0["label"] as? String ?? "",
                        href: $0["href"] as? String ?? "",
                        depth: $0["depth"] as? Int ?? 0
                    )
                }
                onMessage(.ready(toc: toc, title: body["title"] as? String))
            case "relocate":
                onMessage(.relocate(ReaderLocation(
                    cfi: body["cfi"] as? String,
                    href: body["href"] as? String,
                    fraction: body["fraction"] as? Double,
                    tocLabel: body["tocLabel"] as? String,
                    sectionCurrent: body["sectionCurrent"] as? Int,
                    sectionTotal: body["sectionTotal"] as? Int
                )))
            case "tap":
                onMessage(.tap)
            case "showChrome":
                onMessage(.showChrome)
            case "error":
                onMessage(.failed(body["message"] as? String ?? "The book couldn't be opened."))
            default:
                break
            }
        }

        private func openPendingBook() {
            guard let pending = pendingOpen else { return }
            pendingOpen = nil
            let (cfi, settings) = (pending.startCFI, pending.settings)
            lastAppliedSettings = settings

            let payload: [String: Any] = [
                "url": "\(ReaderAssetHandler.scheme)://\(ReaderAssetHandler.host)\(ReaderAssetHandler.bookPath)",
                "lastLocation": cfi as Any,
                "style": settings.payload
            ]
            evaluate(function: "open", argument: payload)
        }

        func apply(settings: ReaderSettings) {
            guard isReady, settings != lastAppliedSettings else { return }
            lastAppliedSettings = settings
            evaluate(function: "setStyle", argument: settings.payload)
        }

        func goTo(_ target: String) {
            evaluate(function: "goTo", argument: target)
        }

        func goToFraction(_ fraction: Double) {
            evaluate(function: "goToFraction", argument: fraction)
        }

        func next() {
            evaluate(function: "next", argument: nil)
        }

        func previous() {
            evaluate(function: "prev", argument: nil)
        }

        private func evaluate(function: String, argument: Any?) {
            guard let webView else { return }
            let encoded: String
            if let argument {
                guard let data = try? JSONSerialization.data(
                    withJSONObject: argument,
                    options: [.fragmentsAllowed]
                ), let json = String(data: data, encoding: .utf8) else { return }
                encoded = json
            } else {
                encoded = ""
            }
            webView.evaluateJavaScript("window.reader.\(function)(\(encoded))")
        }
    }
}

/// What to open once the page reports its bridge is live.
struct PendingOpen {
    let bookURL: URL
    let startCFI: String?
    let settings: ReaderSettings
}

enum ReaderMessage {
    case ready(toc: [TOCEntry], title: String?)
    case relocate(ReaderLocation)
    case tap
    case showChrome
    case failed(String)
}

/// Lets the view model reach into the web view without owning it.
@MainActor
final class ReaderCommands {
    private weak var coordinator: ReaderWebView.Coordinator?

    func attach(coordinator: ReaderWebView.Coordinator) {
        self.coordinator = coordinator
    }

    func goTo(_ target: String) {
        coordinator?.goTo(target)
    }

    func goToFraction(_ fraction: Double) {
        coordinator?.goToFraction(fraction)
    }

    func next() {
        coordinator?.next()
    }

    func previous() {
        coordinator?.previous()
    }
}
