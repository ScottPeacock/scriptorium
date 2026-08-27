import Foundation
import GRDB
import Observation

/// Downloads books for offline reading and keeps track of what's on disk.
@Observable
@MainActor
final class DownloadManager {
    enum Status: Equatable {
        case notDownloaded
        case downloading(fraction: Double?)
        case downloaded
        case failed(String)
    }

    private(set) var statuses: [Int64: Status] = [:]
    private(set) var downloads: [DownloadRecord] = []

    private let client: GrimmoryClient
    private let database: Database
    private let accountID: UUID
    private var tasks: [Int64: Task<Void, Never>] = [:]

    init(client: GrimmoryClient, database: Database, accountID: UUID) {
        self.client = client
        self.database = database
        self.accountID = accountID
        refreshFromDisk()
    }

    func status(for bookId: Int64) -> Status {
        statuses[bookId] ?? .notDownloaded
    }

    func localURL(for bookId: Int64) -> URL? {
        guard let record = downloads.first(where: { $0.bookId == bookId }) else { return nil }
        let url = DownloadRecord.fileURL(
            accountID: accountID,
            bookId: record.bookId,
            fileName: record.fileName
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Downloads a book's primary file. Picks the EPUB when a book has several
    /// formats attached — that's the one the reader can open.
    func download(_ book: AppBookDetail) {
        let bookId = book.id
        guard tasks[bookId] == nil, localURL(for: bookId) == nil else { return }

        let file = Self.preferredFile(of: book)
        let fileName = file?.fileName ?? "\(bookId).epub"
        let destination = DownloadRecord.fileURL(
            accountID: accountID,
            bookId: bookId,
            fileName: fileName
        )
        // /books/{id}/files/{fileId}/download is AdditionalFileController, and it
        // refuses the primary book file outright — validateAdditionalFile throws
        // IllegalArgumentException, which Spring returns as a 400. So the
        // per-file route is only for genuinely supplementary files; the primary
        // file comes from /books/{id}/download. When we can't tell (isPrimary
        // absent), take the whole-book route, which is right for the
        // single-file books that are the common case.
        let endpoint: GrimmoryEndpoint = if let file, file.isPrimary == false {
            .downloadFile(bookId: bookId, fileId: file.id)
        } else {
            .downloadBook(bookId: bookId)
        }

        statuses[bookId] = .downloading(fraction: nil)

        tasks[bookId] = Task { [client, database, weak self] in
            do {
                try await client.downloadFile(endpoint, to: destination) { written, expected in
                    guard expected > 0 else { return }
                    let fraction = Double(written) / Double(expected)
                    Task { @MainActor in
                        self?.statuses[bookId] = .downloading(fraction: fraction)
                    }
                }

                let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                let record = DownloadRecord(
                    bookId: bookId,
                    fileId: file?.id,
                    fileName: fileName,
                    bookType: file?.bookType ?? book.primaryFileType,
                    title: book.title,
                    byteSize: size,
                    downloadedAt: Date()
                )
                try await database.writer.write { db in try record.save(db) }

                await MainActor.run {
                    self?.statuses[bookId] = .downloaded
                    self?.tasks[bookId] = nil
                    self?.refreshFromDisk()
                }
            } catch {
                let message = (error as? APIError)?.localizedDescription ?? error.localizedDescription
                await MainActor.run {
                    self?.statuses[bookId] = .failed(message)
                    self?.tasks[bookId] = nil
                }
            }
        }
    }

    func cancel(bookId: Int64) {
        tasks[bookId]?.cancel()
        tasks[bookId] = nil
        statuses[bookId] = .notDownloaded
    }

    func remove(bookId: Int64) {
        cancel(bookId: bookId)
        if let record = downloads.first(where: { $0.bookId == bookId }) {
            let url = DownloadRecord.fileURL(
                accountID: accountID,
                bookId: bookId,
                fileName: record.fileName
            )
            try? FileManager.default.removeItem(at: url)
        }
        try? database.writer.write { db in
            _ = try DownloadRecord.deleteOne(db, key: bookId)
        }
        statuses[bookId] = .notDownloaded
        refreshFromDisk()
    }

    func removeAll() {
        for record in downloads {
            remove(bookId: record.bookId)
        }
    }

    var totalBytes: Int64 {
        downloads.reduce(into: Int64(0)) { $0 += $1.byteSize }
    }

    /// Reconciles the registry against what's actually on disk. Files can go
    /// missing when iOS reclaims space or a restore drops the container, and a
    /// row pointing at nothing looks like a downloaded book that won't open.
    func refreshFromDisk() {
        let records = (try? database.writer.read { db in
            try DownloadRecord.order(Column("downloadedAt").desc).fetchAll(db)
        }) ?? []

        var live: [DownloadRecord] = []
        for record in records {
            let url = DownloadRecord.fileURL(
                accountID: accountID,
                bookId: record.bookId,
                fileName: record.fileName
            )
            if FileManager.default.fileExists(atPath: url.path) {
                live.append(record)
                if statuses[record.bookId] == nil {
                    statuses[record.bookId] = .downloaded
                }
            } else {
                try? database.writer.write { db in
                    _ = try DownloadRecord.deleteOne(db, key: record.bookId)
                }
                statuses[record.bookId] = .notDownloaded
            }
        }
        downloads = live
    }

    /// Prefers an EPUB: a book can carry several formats, and the reader only
    /// handles EPUB in v1.
    nonisolated static func preferredFile(of book: AppBookDetail) -> AppBookFile? {
        guard let files = book.files, !files.isEmpty else { return nil }
        let readable = files.filter { $0.isBook ?? true }
        let epub = readable.first { ($0.fileExtension ?? $0.bookType)?.lowercased().contains("epub") == true }
        return epub ?? readable.first { $0.isPrimary == true } ?? readable.first
    }
}
