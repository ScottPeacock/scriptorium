import Foundation
import GRDB
@testable import Scriptorium
import Testing

@Suite("Pending write queue")
struct PendingWriteTests {
    private func progress(bookId: Int64, cfi: String, at date: Date) -> PendingProgress {
        PendingProgress(
            bookId: bookId,
            bookFileId: 1,
            cfi: cfi,
            href: "c1.xhtml",
            fraction: 0.5,
            updatedAt: date
        )
    }

    @Test("A queued position survives a round trip")
    func roundTrip() throws {
        let database = try Database(inMemory: true)
        let row = progress(bookId: 1, cfi: "epubcfi(/6/4!/2)", at: Date(timeIntervalSince1970: 1000))
        try database.writer.write { db in try row.save(db) }

        let loaded = try database.writer.read { db in try PendingProgress.fetchOne(db, key: 1) }
        #expect(loaded?.cfi == "epubcfi(/6/4!/2)")
        #expect(loaded?.attempts == 0)
    }

    /// One row per book: a newer position supersedes an older one outright, so
    /// the queue can never grow unbounded while someone reads offline.
    @Test("A newer position for the same book replaces the older one")
    func newerReplacesOlder() throws {
        let database = try Database(inMemory: true)
        try database.writer.write { db in
            try progress(bookId: 1, cfi: "old", at: Date(timeIntervalSince1970: 1000)).save(db)
            try progress(bookId: 1, cfi: "new", at: Date(timeIntervalSince1970: 2000)).save(db)
        }

        let count = try database.writer.read { db in try PendingProgress.fetchCount(db) }
        let loaded = try database.writer.read { db in try PendingProgress.fetchOne(db, key: 1) }
        #expect(count == 1)
        #expect(loaded?.cfi == "new")
    }

    @Test("Different books queue independently")
    func separateBooks() throws {
        let database = try Database(inMemory: true)
        try database.writer.write { db in
            try progress(bookId: 1, cfi: "a", at: Date()).save(db)
            try progress(bookId: 2, cfi: "b", at: Date()).save(db)
        }
        let count = try database.writer.read { db in try PendingProgress.fetchCount(db) }
        #expect(count == 2)
    }

    @Test("Status changes queue separately from positions")
    func statusQueue() throws {
        let database = try Database(inMemory: true)
        let status = PendingStatus(bookId: 3, status: ReadStatus.reading.rawValue, updatedAt: Date())
        try database.writer.write { db in try status.save(db) }

        let loaded = try database.writer.read { db in try PendingStatus.fetchOne(db, key: 3) }
        #expect(loaded?.status == "READING")
    }

    @Test("Read statuses match the server's enum spelling")
    func statusSpelling() {
        #expect(ReadStatus.wontRead.rawValue == "WONT_READ")
        #expect(ReadStatus(serverValue: "reading") == .reading)
        #expect(ReadStatus(serverValue: "READ") == .read)
        #expect(ReadStatus(serverValue: nil) == nil)
        // A status the app doesn't model shouldn't be mistaken for one it does.
        #expect(ReadStatus(serverValue: "RE_READING") == nil)
    }
}

@Suite("Position conflict resolution")
@MainActor
struct PositionResolutionTests {
    private func server(_ cfi: String, fraction: Float, at date: Date) -> EpubProgress {
        // Decoded from JSON so the test goes through the real Codable path.
        let json = Data("""
        {"cfi":"\(cfi)","href":"c1.xhtml","percentage":\(fraction),\
        "updatedAt":"\(ISO8601DateFormatter().string(from: date))"}
        """.utf8)
        // swiftlint:disable:next force_try
        return try! JSONCoding.decoder.decode(EpubProgress.self, from: json)
    }

    private func local(_ cfi: String, fraction: Double, at date: Date) -> PendingProgress {
        PendingProgress(
            bookId: 1,
            bookFileId: 1,
            cfi: cfi,
            href: "c1.xhtml",
            fraction: fraction,
            updatedAt: date
        )
    }

    private let early = Date(timeIntervalSince1970: 1_000_000)
    private let late = Date(timeIntervalSince1970: 2_000_000)

    @Test("With only a server position, the book opens there")
    func serverOnly() {
        let result = ReaderViewModel.resolve(
            server: server("srv", fraction: 0.4, at: early),
            local: nil
        )
        #expect(result.startCFI == "srv")
        #expect(result.conflict == nil)
    }

    @Test("With only a local position, the book opens there")
    func localOnly() {
        let result = ReaderViewModel.resolve(
            server: nil,
            local: local("loc", fraction: 0.4, at: early)
        )
        #expect(result.startCFI == "loc")
        #expect(result.conflict == nil)
    }

    @Test("Neither position means no start and no conflict")
    func neither() {
        let result = ReaderViewModel.resolve(server: nil, local: nil)
        #expect(result.startCFI == nil)
        #expect(result.conflict == nil)
    }

    @Test("Identical positions are not a conflict")
    func identical() {
        let result = ReaderViewModel.resolve(
            server: server("same", fraction: 0.4, at: late),
            local: local("same", fraction: 0.4, at: early)
        )
        #expect(result.startCFI == "same")
        #expect(result.conflict == nil)
    }

    /// The offline case: this device read further while disconnected, so its
    /// unsynced position is the one that should win.
    @Test("A newer unsynced local position wins over the server's")
    func localNewerWins() throws {
        let result = ReaderViewModel.resolve(
            server: server("srv", fraction: 0.20, at: early),
            local: local("loc", fraction: 0.60, at: late)
        )
        #expect(result.startCFI == "loc")
        let conflict = try #require(result.conflict)
        #expect(conflict.otherCFI == "srv")
        #expect(conflict.otherIsNewer == false)
    }

    /// The other-device case: someone read on the web reader or a Kobo since
    /// this device last synced.
    @Test("A newer server position wins over a stale local one")
    func serverNewerWins() throws {
        let result = ReaderViewModel.resolve(
            server: server("srv", fraction: 0.80, at: late),
            local: local("loc", fraction: 0.30, at: early)
        )
        #expect(result.startCFI == "srv")
        let conflict = try #require(result.conflict)
        #expect(conflict.otherCFI == "loc")
        #expect(conflict.otherIsNewer == true)
    }

    /// Different CFIs on the same page are not worth interrupting a reader for.
    @Test("Positions a hair apart don't raise a conflict")
    func negligibleDifference() {
        let result = ReaderViewModel.resolve(
            server: server("srv", fraction: 0.500, at: late),
            local: local("loc", fraction: 0.505, at: early)
        )
        #expect(result.startCFI == "srv")
        #expect(result.conflict == nil)
    }

    @Test("The conflict reports the other position's fraction, for the prompt")
    func conflictFraction() throws {
        let result = ReaderViewModel.resolve(
            server: server("srv", fraction: 0.25, at: late),
            local: local("loc", fraction: 0.75, at: early)
        )
        let conflict = try #require(result.conflict)
        #expect(abs(conflict.otherFraction - 0.75) < 0.001)
    }
}
