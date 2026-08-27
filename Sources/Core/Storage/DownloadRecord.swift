import Foundation
import GRDB

/// A book whose file is on this device.
struct DownloadRecord: Codable, Sendable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "download"

    var bookId: Int64
    var fileId: Int64?
    var fileName: String
    var bookType: String?
    var title: String?
    var byteSize: Int64
    var downloadedAt: Date

    var id: Int64 {
        bookId
    }
}

extension DownloadRecord {
    /// Where the file lives. Derived rather than stored: the container path
    /// changes between installs and across OS upgrades, so an absolute path
    /// recorded at download time goes stale.
    static func fileURL(accountID: UUID, bookId: Int64, fileName: String) -> URL {
        directory(accountID: accountID).appendingPathComponent("\(bookId)-\(fileName)")
    }

    static func directory(accountID: UUID) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Scriptorium/\(accountID.uuidString)/Books", isDirectory: true)
    }
}
