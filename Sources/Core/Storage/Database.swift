import Foundation
import GRDB

/// One SQLite file per account, holding what the app knows offline: which books
/// are downloaded, and (from M5) reading positions waiting to be sent.
struct Database: Sendable {
    let writer: any DatabaseWriter

    init(accountID: UUID) throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Scriptorium/\(accountID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let queue = try DatabaseQueue(path: directory.appendingPathComponent("library.sqlite").path)
        writer = queue
        try Self.migrator.migrate(writer)
    }

    /// In-memory database for tests.
    init(inMemory: Bool) throws {
        precondition(inMemory)
        writer = try DatabaseQueue()
        try Self.migrator.migrate(writer)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createDownloads") { db in
            try db.create(table: "download") { table in
                table.primaryKey("bookId", .integer)
                table.column("fileId", .integer)
                table.column("fileName", .text).notNull()
                table.column("bookType", .text)
                table.column("title", .text)
                table.column("byteSize", .integer).notNull().defaults(to: 0)
                table.column("downloadedAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("createPendingWrites") { db in
            // One row per book: a newer position supersedes an older one
            // outright, so there is nothing to merge and no backlog to replay
            // in order.
            try db.create(table: "pendingProgress") { table in
                table.primaryKey("bookId", .integer)
                table.column("bookFileId", .integer).notNull()
                table.column("cfi", .text)
                table.column("href", .text)
                table.column("fraction", .double).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("attempts", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "pendingStatus") { table in
                table.primaryKey("bookId", .integer)
                table.column("status", .text).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("attempts", .integer).notNull().defaults(to: 0)
            }
        }

        return migrator
    }
}
