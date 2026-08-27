import Foundation
import GRDB
@testable import Scriptorium
import Testing

@Suite("Downloads")
struct DownloadTests {
    /// Builds a book detail from JSON so the test exercises real decoding —
    /// including the Lombok boolean spellings — rather than a hand-made struct.
    private struct FileSpec {
        let id: Int64
        let name: String
        let ext: String
        let primary: Bool
    }

    private func book(files: [FileSpec]) throws -> AppBookDetail {
        let entries = files.map { file in
            """
            {"id":\(file.id),"fileName":"\(file.name)","extension":"\(file.ext)",\
            "primary":\(file.primary),"book":true}
            """
        }.joined(separator: ",")
        let json = Data("""
        {"id":1,"title":"T","primaryFileType":"EPUB","files":[\(entries)]}
        """.utf8)
        return try JSONCoding.decoder.decode(AppBookDetail.self, from: json)
    }

    @Test("An EPUB wins over other formats attached to the same book")
    func prefersEPUB() throws {
        let detail = try book(files: [
            FileSpec(id: 10, name: "book.pdf", ext: "pdf", primary: true),
            FileSpec(id: 11, name: "book.epub", ext: "epub", primary: false)
        ])
        let chosen = try #require(DownloadManager.preferredFile(of: detail))
        #expect(chosen.id == 11)
    }

    @Test("Without an EPUB, the primary file wins")
    func fallsBackToPrimary() throws {
        let detail = try book(files: [
            FileSpec(id: 20, name: "a.cbz", ext: "cbz", primary: false),
            FileSpec(id: 21, name: "b.pdf", ext: "pdf", primary: true)
        ])
        let chosen = try #require(DownloadManager.preferredFile(of: detail))
        #expect(chosen.id == 21)
    }

    @Test("A book with no files yields nothing to download")
    func noFiles() throws {
        let detail = try JSONCoding.decoder.decode(
            AppBookDetail.self,
            from: Data(#"{"id":1,"title":"T"}"#.utf8)
        )
        #expect(DownloadManager.preferredFile(of: detail) == nil)
    }

    @Test("Download records round-trip through the database")
    func recordRoundTrip() throws {
        let database = try Database(inMemory: true)
        let record = DownloadRecord(
            bookId: 42,
            fileId: 7,
            fileName: "book.epub",
            bookType: "EPUB",
            title: "A Book",
            byteSize: 1234,
            downloadedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try database.writer.write { db in try record.save(db) }

        let loaded = try database.writer.read { db in try DownloadRecord.fetchOne(db, key: 42) }
        #expect(loaded?.fileName == "book.epub")
        #expect(loaded?.byteSize == 1234)
    }

    @Test("Deleting a record removes it")
    func deleteRecord() throws {
        let database = try Database(inMemory: true)
        let record = DownloadRecord(
            bookId: 9,
            fileId: nil,
            fileName: "x.epub",
            bookType: nil,
            title: nil,
            byteSize: 1,
            downloadedAt: Date()
        )
        try database.writer.write { db in try record.save(db) }
        try database.writer.write { db in _ = try DownloadRecord.deleteOne(db, key: 9) }

        let count = try database.writer.read { db in try DownloadRecord.fetchCount(db) }
        #expect(count == 0)
    }

    /// The container path changes between installs and OS upgrades, so an
    /// absolute path recorded at download time goes stale.
    @Test("File paths are derived from the account and book, not stored")
    func derivedPath() {
        let id = UUID()
        let url = DownloadRecord.fileURL(accountID: id, bookId: 5, fileName: "war.epub")
        #expect(url.lastPathComponent == "5-war.epub")
        #expect(url.path.contains(id.uuidString))
    }
}

@Suite("Reader settings")
struct ReaderSettingsTests {
    @Test("The JS payload carries every field the bridge reads")
    func payload() {
        var settings = ReaderSettings()
        settings.theme = .sepia
        settings.flow = .scrolled
        settings.fontSize = 130

        let payload = settings.payload
        #expect(payload["theme"] as? String == "sepia")
        #expect(payload["flow"] as? String == "scrolled")
        #expect(payload["fontSize"] as? Int == 130)
        #expect(payload["lineHeight"] as? Double == 1.5)
    }

    @Test("An unset font family is omitted rather than sent as null")
    func omitsFontFamily() {
        #expect(ReaderSettings().payload["fontFamily"] == nil)
    }

    @Test("Settings survive a save and load")
    func persistence() throws {
        let suite = "ReaderSettingsTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        var settings = ReaderSettings()
        settings.theme = .dark
        settings.fontSize = 150
        settings.save(to: defaults)

        let loaded = ReaderSettings.load(from: defaults)
        #expect(loaded.theme == .dark)
        #expect(loaded.fontSize == 150)
    }

    @Test("Missing stored settings fall back to the defaults")
    func defaultsWhenAbsent() throws {
        let suite = "ReaderSettingsTestsEmpty"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let loaded = ReaderSettings.load(from: defaults)
        #expect(loaded.theme == .light)
        #expect(loaded.flow == .paginated)
    }
}

@Suite("Download endpoint choice")
struct DownloadEndpointTests {
    private let base = URL(string: "http://192.168.1.21:6060")!

    /// AdditionalFileController refuses the primary book file:
    /// validateAdditionalFile throws IllegalArgumentException, which Spring
    /// returns as a 400. Using it for the main EPUB failed every download.
    @Test("The primary file uses the whole-book download route")
    func primaryUsesBookRoute() throws {
        let url = try #require(GrimmoryEndpoint.downloadBook(bookId: 12).url(base: base))
        #expect(url.absoluteString == "http://192.168.1.21:6060/api/v1/books/12/download")
    }

    @Test("A supplementary file uses the per-file route")
    func additionalUsesFileRoute() throws {
        let url = try #require(GrimmoryEndpoint.downloadFile(bookId: 12, fileId: 34).url(base: base))
        #expect(url.absoluteString == "http://192.168.1.21:6060/api/v1/books/12/files/34/download")
    }
}

@Suite("Server error bodies")
struct ServerErrorBodyTests {
    @Test("Grimmory's own ErrorResponse surfaces its message")
    func errorResponseShape() throws {
        let json = Data(#"""
        {"status":400,"message":"Primary book file cannot be processed as an additional file: 7",
         "timestamp":"2026-08-27T12:00:00"}
        """#.utf8)
        let body = try JSONCoding.decoder.decode(ServerErrorBody.self, from: json)
        #expect(body.displayMessage?.hasPrefix("Primary book file") == true)
    }

    @Test("Spring's default shape falls back to its error field")
    func springShape() throws {
        let json = Data(#"{"status":401,"error":"Unauthorized","path":"/api/v1/version"}"#.utf8)
        let body = try JSONCoding.decoder.decode(ServerErrorBody.self, from: json)
        #expect(body.displayMessage == "Unauthorized")
    }

    @Test("Validation details are appended to the message")
    func withDetails() throws {
        let json = Data(#"{"status":400,"message":"Invalid","details":["rating must be at most 5"]}"#.utf8)
        let body = try JSONCoding.decoder.decode(ServerErrorBody.self, from: json)
        #expect(body.displayMessage == "Invalid (rating must be at most 5)")
    }

    @Test("An empty body yields no message rather than an empty string")
    func emptyBody() throws {
        let body = try JSONCoding.decoder.decode(ServerErrorBody.self, from: Data("{}".utf8))
        #expect(body.displayMessage == nil)
    }
}
