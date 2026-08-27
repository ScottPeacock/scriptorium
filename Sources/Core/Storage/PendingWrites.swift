import Foundation
import GRDB

/// A reading position that hasn't reached the server yet.
///
/// Positions are the one thing the app must not lose: someone reading on a
/// plane and closing the app should not come back to a book that forgot where
/// they were. Everything else can be re-fetched.
struct PendingProgress: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pendingProgress"

    var bookId: Int64
    var bookFileId: Int64
    /// The EPUB CFI foliate-js reported, stored verbatim.
    var cfi: String?
    var href: String?
    var fraction: Double
    var updatedAt: Date
    var attempts: Int = 0
}

struct PendingStatus: Codable, Sendable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pendingStatus"

    var bookId: Int64
    var status: String
    var updatedAt: Date
    var attempts: Int = 0
}

/// Grimmory's `ReadStatus`. Only the values the app sets are modelled;
/// the rest round-trip as `other` so a status set on the server isn't clobbered.
enum ReadStatus: String, Sendable, CaseIterable, Identifiable {
    case unread = "UNREAD"
    case reading = "READING"
    case read = "READ"
    case paused = "PAUSED"
    case abandoned = "ABANDONED"
    case wontRead = "WONT_READ"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .unread: "Unread"
        case .reading: "Reading"
        case .read: "Read"
        case .paused: "Paused"
        case .abandoned: "Abandoned"
        case .wontRead: "Won't read"
        }
    }

    init?(serverValue: String?) {
        guard let serverValue else { return nil }
        self.init(rawValue: serverValue.uppercased())
    }
}
