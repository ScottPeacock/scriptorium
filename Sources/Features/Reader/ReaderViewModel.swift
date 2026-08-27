import Foundation
import Observation

@Observable
@MainActor
final class ReaderViewModel {
    enum Phase: Equatable {
        case loading
        case reading
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var toc: [TOCEntry] = []
    private(set) var location: ReaderLocation?
    private(set) var syncError: String?

    var settings: ReaderSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
        }
    }

    var showChrome = true
    let commands = ReaderCommands()

    let book: AppBookDetail
    let bookURL: URL
    /// The CFI the server had when the book was opened. foliate-js resolves it
    /// on init — this is the whole reason the app runs the same engine as
    /// Grimmory's web reader.
    let startCFI: String?

    private let client: GrimmoryClient
    private let bookFileId: Int64?
    private var writeTask: Task<Void, Never>?
    private var lastWrittenCFI: String?

    init(book: AppBookDetail, bookURL: URL, client: GrimmoryClient) {
        self.book = book
        self.bookURL = bookURL
        self.client = client
        startCFI = book.epubProgress?.cfi
        bookFileId = DownloadManager.preferredFile(of: book)?.id
        settings = ReaderSettings.load()
    }

    var progressFraction: Double {
        location?.fraction ?? Double(book.readProgress ?? 0)
    }

    var progressLabel: String {
        let percent = Int((progressFraction * 100).rounded())
        if let label = location?.tocLabel, !label.isEmpty {
            return "\(label) · \(percent)%"
        }
        return "\(percent)%"
    }

    func handle(_ message: ReaderMessage) {
        switch message {
        case let .ready(toc, _):
            self.toc = toc
            phase = .reading
        case let .relocate(location):
            self.location = location
            scheduleProgressWrite(location)
        case .tap:
            showChrome.toggle()
        case let .failed(message):
            phase = .failed(message)
        }
    }

    func goTo(_ entry: TOCEntry) {
        commands.goTo(entry.href)
        showChrome = false
    }

    func scrub(to fraction: Double) {
        commands.goToFraction(fraction)
    }

    /// Debounces position writes. `relocate` fires on every page turn, and a
    /// fast reader would otherwise generate a request per tap.
    private func scheduleProgressWrite(_ location: ReaderLocation) {
        guard let cfi = location.cfi, cfi != lastWrittenCFI else { return }
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.writeProgress(location)
        }
    }

    /// Flushes immediately — called when the reader closes, where waiting out
    /// the debounce would lose the last page turn.
    func flushProgress() async {
        writeTask?.cancel()
        writeTask = nil
        guard let location, location.cfi != lastWrittenCFI else { return }
        await writeProgress(location)
    }

    private func writeProgress(_ location: ReaderLocation) async {
        guard let cfi = location.cfi, let bookFileId else { return }
        let request = UpdateProgressRequest(
            fileProgress: BookFileProgress(
                bookFileId: bookFileId,
                cfi: cfi,
                href: location.href,
                progressPercent: Float(location.fraction ?? 0)
            ),
            dateFinished: nil
        )
        do {
            _ = try await client.sendForData(.bookProgress(id: book.id), body: request)
            lastWrittenCFI = cfi
            syncError = nil
        } catch {
            // Offline queueing lands with M5. Until then, say so rather than
            // pretending the position is safe on the server.
            syncError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
