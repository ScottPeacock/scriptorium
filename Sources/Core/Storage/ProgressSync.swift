import Foundation
import GRDB
import Network
import Observation

/// Owns reading positions: records them locally first, then gets them to the
/// server when it can.
///
/// Writing locally before attempting the network is the whole point. A position
/// that only exists in a failed request is a lost position, and losing someone's
/// place in a book is the one bug this app cannot ship with.
@Observable
@MainActor
final class ProgressSync {
    private(set) var pendingCount = 0
    private(set) var isOnline = true
    private(set) var lastError: String?

    private let client: GrimmoryClient
    private let database: Database
    private let monitor = NWPathMonitor()
    private var flushTask: Task<Void, Never>?

    init(client: GrimmoryClient, database: Database) {
        self.client = client
        self.database = database
        refreshPendingCount()
        startMonitoring()
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Recording

    /// Records a position locally, then tries to send it.
    func record(
        bookId: Int64,
        bookFileId: Int64,
        cfi: String?,
        href: String?,
        fraction: Double,
        at date: Date = Date()
    ) {
        let pending = PendingProgress(
            bookId: bookId,
            bookFileId: bookFileId,
            cfi: cfi,
            href: href,
            fraction: fraction,
            updatedAt: date
        )
        try? database.writer.write { db in try pending.save(db) }
        refreshPendingCount()
        scheduleFlush()
    }

    func record(status: ReadStatus, bookId: Int64, at date: Date = Date()) {
        let pending = PendingStatus(bookId: bookId, status: status.rawValue, updatedAt: date)
        try? database.writer.write { db in try pending.save(db) }
        refreshPendingCount()
        scheduleFlush()
    }

    /// The locally-recorded position for a book, if one hasn't synced yet.
    func pendingProgress(for bookId: Int64) -> PendingProgress? {
        try? database.writer.read { db in try PendingProgress.fetchOne(db, key: bookId) }
    }

    // MARK: - Flushing

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            await self?.flush()
            await MainActor.run { self?.flushTask = nil }
        }
    }

    /// Drains everything waiting. Safe to call repeatedly.
    func flush() async {
        let positions = await (try? database.writer.read { db in
            try PendingProgress.order(Column("updatedAt")).fetchAll(db)
        }) ?? []

        for pending in positions {
            let request = UpdateProgressRequest(
                fileProgress: BookFileProgress(
                    bookFileId: pending.bookFileId,
                    cfi: pending.cfi,
                    href: pending.href,
                    progressPercent: Float(pending.fraction)
                ),
                dateFinished: nil
            )
            do {
                _ = try await client.sendForData(.bookProgress(id: pending.bookId), body: request)
                try? await database.writer.write { db in
                    // Only clear the row if it hasn't been superseded while the
                    // request was in flight — otherwise a page turn during a slow
                    // network would be silently dropped.
                    let current = try PendingProgress.fetchOne(db, key: pending.bookId)
                    if let current, current.updatedAt <= pending.updatedAt {
                        _ = try PendingProgress.deleteOne(db, key: pending.bookId)
                    }
                }
                lastError = nil
            } catch {
                handle(error, bookId: pending.bookId)
                break
            }
        }

        let statuses = await (try? database.writer.read { db in
            try PendingStatus.order(Column("updatedAt")).fetchAll(db)
        }) ?? []

        for pending in statuses {
            do {
                _ = try await client.sendForData(
                    .updateStatus(bookId: pending.bookId),
                    body: UpdateStatusBody(status: pending.status)
                )
                try? await database.writer.write { db in
                    _ = try PendingStatus.deleteOne(db, key: pending.bookId)
                }
                lastError = nil
            } catch {
                handle(error, bookId: pending.bookId)
                break
            }
        }

        refreshPendingCount()
    }

    private func handle(_ error: any Error, bookId: Int64) {
        lastError = (error as? APIError)?.localizedDescription ?? error.localizedDescription

        // Network failures are why the queue exists — keep the row and retry.
        // A write the server actively rejects will be rejected again, so count
        // those and eventually drop them rather than blocking the queue behind
        // one bad row forever.
        guard case let .server(status, _)? = error as? APIError,
              (400 ..< 500).contains(status),
              ![401, 408, 429].contains(status)
        else { return }

        try? database.writer.write { db in
            if var row = try PendingProgress.fetchOne(db, key: bookId) {
                row.attempts += 1
                if row.attempts >= 5 {
                    _ = try PendingProgress.deleteOne(db, key: bookId)
                } else {
                    try row.save(db)
                }
            }
            if var row = try PendingStatus.fetchOne(db, key: bookId) {
                row.attempts += 1
                if row.attempts >= 5 {
                    _ = try PendingStatus.deleteOne(db, key: bookId)
                } else {
                    try row.save(db)
                }
            }
        }
    }

    private func refreshPendingCount() {
        pendingCount = (try? database.writer.read { db in
            try PendingProgress.fetchCount(db) + PendingStatus.fetchCount(db)
        }) ?? 0
    }

    // MARK: - Connectivity

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                let cameBack = online && !self.isOnline
                self.isOnline = online
                // Coming back online is the moment the queue exists for.
                if cameBack {
                    self.scheduleFlush()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.scottpeacock.scriptorium.network"))
    }
}

/// `UpdateStatusRequest` on the server side.
struct UpdateStatusBody: Encodable, Sendable {
    let status: String
}

/// `UpdateRatingRequest` — the server validates 1...5.
struct UpdateRatingBody: Encodable, Sendable {
    let rating: Int
}
