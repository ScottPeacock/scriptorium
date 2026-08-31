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

    /// Two positions that disagree — typically this device read offline while
    /// another device read online, or vice versa.
    struct PositionConflict: Equatable {
        let otherCFI: String
        let otherFraction: Double
        let otherIsNewer: Bool
    }

    private(set) var phase: Phase = .loading
    private(set) var toc: [TOCEntry] = []
    private(set) var location: ReaderLocation?
    private(set) var conflict: PositionConflict?

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
    /// Where the book opens. The newer of what the server holds and what this
    /// device recorded but hasn't synced.
    let startCFI: String?

    private let progress: ProgressSync
    private let bookFileId: Int64?
    private var writeTask: Task<Void, Never>?
    private var markedAsReading = false

    init(book: AppBookDetail, bookURL: URL, progress: ProgressSync) {
        self.book = book
        self.bookURL = bookURL
        self.progress = progress
        bookFileId = DownloadManager.preferredFile(of: book)?.id
        settings = ReaderSettings.load()

        // Resolve where to open before the page loads.
        let server = book.epubProgress
        let local = progress.pendingProgress(for: book.id)
        let resolution = Self.resolve(server: server, local: local)
        startCFI = resolution.startCFI
        conflict = resolution.conflict
    }

    /// Picks the newer of the two positions, and reports the other one when the
    /// two genuinely disagree so the reader can offer to jump.
    static func resolve(
        server: EpubProgress?,
        local: PendingProgress?
    ) -> (startCFI: String?, conflict: PositionConflict?) {
        let serverCFI = server?.cfi
        let localCFI = local?.cfi

        guard let serverCFI, let localCFI, serverCFI != localCFI else {
            return (localCFI ?? serverCFI, nil)
        }

        let serverDate = server?.updatedAt ?? .distantPast
        let localDate = local?.updatedAt ?? .distantPast
        let localIsNewer = localDate >= serverDate

        // Positions a hair apart are the same page in practice; only surface a
        // conflict worth interrupting someone for.
        let serverFraction = Double(server?.percentage ?? 0)
        let localFraction = local?.fraction ?? 0
        guard abs(serverFraction - localFraction) > 0.01 else {
            return (localIsNewer ? localCFI : serverCFI, nil)
        }

        return (
            localIsNewer ? localCFI : serverCFI,
            PositionConflict(
                otherCFI: localIsNewer ? serverCFI : localCFI,
                otherFraction: localIsNewer ? serverFraction : localFraction,
                otherIsNewer: !localIsNewer
            )
        )
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

    /// Positions waiting to reach the server, for the reader's footer.
    var pendingCount: Int {
        progress.pendingCount
    }

    var isOnline: Bool {
        progress.isOnline
    }

    func handle(_ message: ReaderMessage) {
        switch message {
        case let .ready(toc, _):
            self.toc = toc
            phase = .reading
            markAsReadingIfNeeded()
        case let .relocate(location):
            self.location = location
            scheduleProgressWrite(location)
        case .tap:
            showChrome.toggle()
        case .showChrome:
            showChrome = true
        case let .failed(message):
            phase = .failed(message)
        }
    }

    func goTo(_ entry: TOCEntry) {
        commands.goTo(entry.href)
        showChrome = false
    }

    func jumpToConflictPosition() {
        guard let conflict else { return }
        commands.goTo(conflict.otherCFI)
        self.conflict = nil
    }

    func dismissConflict() {
        conflict = nil
    }

    func scrub(to fraction: Double) {
        commands.goToFraction(fraction)
    }

    /// Opening a book means you're reading it. Only promotes from unread —
    /// a book someone deliberately marked "abandoned" shouldn't silently flip
    /// back because they opened it to check something.
    private func markAsReadingIfNeeded() {
        guard !markedAsReading else { return }
        markedAsReading = true
        let current = ReadStatus(serverValue: book.readStatus)
        guard current == nil || current == .unread else { return }
        progress.record(status: .reading, bookId: book.id)
    }

    /// Debounces position writes. `relocate` fires on every page turn, and a
    /// fast reader would otherwise generate a request per tap.
    private func scheduleProgressWrite(_ location: ReaderLocation) {
        guard location.cfi != nil else { return }
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.recordProgress(location)
        }
    }

    /// Flushes immediately — called when the reader closes, where waiting out
    /// the debounce would lose the last page turn.
    func flushProgress() async {
        writeTask?.cancel()
        writeTask = nil
        if let location {
            recordProgress(location)
        }
        markAsReadIfFinished()
        await progress.flush()
    }

    private func recordProgress(_ location: ReaderLocation) {
        guard let cfi = location.cfi, let bookFileId else { return }
        progress.record(
            bookId: book.id,
            bookFileId: bookFileId,
            cfi: cfi,
            href: location.href,
            fraction: location.fraction ?? 0
        )
    }

    private func markAsReadIfFinished() {
        guard let fraction = location?.fraction, fraction >= 0.99 else { return }
        let current = ReadStatus(serverValue: book.readStatus)
        guard current != .read else { return }
        progress.record(status: .read, bookId: book.id)
    }
}
