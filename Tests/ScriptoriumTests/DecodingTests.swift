import Foundation
@testable import Scriptorium
import Testing

@Suite("Payload decoding")
struct DecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "json"),
            "Missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    @Test("Real /api/v1/public-settings payload decodes")
    func publicSettings() throws {
        let settings = try JSONCoding.decoder.decode(PublicSettings.self, from: fixture("public-settings"))
        #expect(settings.oidcEnabled == false)
        #expect(settings.remoteAuthEnabled == false)
        #expect(settings.supportsLocalLogin)
    }

    @Test("Real Spring error body decodes, including its millisecond timestamp")
    func errorBody() throws {
        let body = try JSONCoding.decoder.decode(ServerErrorBody.self, from: fixture("error-401"))
        #expect(body.status == 401)
        #expect(body.error == "Unauthorized")
        #expect(body.path == "/api/v1/version")
    }

    @Test("Instant with milliseconds parses, fractional part included")
    func instantWithMillis() throws {
        let date = try #require(JSONCoding.parseDate("2026-08-26T18:32:00.543Z"))

        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 26
        components.hour = 18
        components.minute = 32
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let whole = try #require(calendar.date(from: components))

        #expect(abs(date.timeIntervalSince(whole) - 0.543) < 0.001)
    }

    @Test("Instant without milliseconds parses")
    func instantWithoutMillis() {
        #expect(JSONCoding.parseDate("2026-08-26T18:32:00Z") != nil)
    }

    @Test("LocalDate parses — publishedDate arrives as a plain day")
    func localDate() {
        #expect(JSONCoding.parseDate("2026-08-26") != nil)
    }

    @Test("Unparseable dates are rejected rather than silently defaulted")
    func badDate() {
        #expect(JSONCoding.parseDate("not a date") == nil)
    }

    // Lombok renames primitive booleans (isAdmin -> "admin") but leaves boxed
    // ones alone (isPhysical -> "isPhysical"). We accept both spellings until
    // authenticated fixtures settle which the server actually sends.

    @Test("AppUserInfo decodes the Lombok-stripped 'admin' key")
    func userInfoStrippedKey() throws {
        let json = Data(
            #"{"admin":true,"canUpload":false,"canDownload":true,"canAccessBookdrop":false,"maxFileUploadSizeMb":100}"#
                .utf8
        )
        let user = try JSONCoding.decoder.decode(AppUserInfo.self, from: json)
        #expect(user.isAdmin)
        #expect(user.canDownload)
        #expect(!user.canUpload)
    }

    @Test("AppUserInfo also decodes the unstripped 'isAdmin' key")
    func userInfoUnstrippedKey() throws {
        let json = Data(
            #"{"isAdmin":true,"canUpload":false,"canDownload":false,"canAccessBookdrop":false,"maxFileUploadSizeMb":0}"#
                .utf8
        )
        let user = try JSONCoding.decoder.decode(AppUserInfo.self, from: json)
        #expect(user.isAdmin)
    }

    @Test("AppBookFile maps the reserved 'extension' key and both boolean spellings")
    func bookFile() throws {
        let json = Data(#"""
        {"id":9,"bookId":3,"fileName":"book.epub","extension":"epub",
         "book":true,"primary":true,"folderBased":false}
        """#.utf8)
        let file = try JSONCoding.decoder.decode(AppBookFile.self, from: json)
        #expect(file.fileExtension == "epub")
        #expect(file.isPrimary == true)
        #expect(file.isBook == true)
    }

    @Test("Absent optional fields decode to nil rather than throwing")
    func sparsePayload() throws {
        // Grimmory annotates these DTOs @JsonInclude(NON_NULL), so a book with
        // no metadata sends very little.
        let json = Data(#"{"id":1}"#.utf8)
        let summary = try JSONCoding.decoder.decode(AppBookSummary.self, from: json)
        #expect(summary.id == 1)
        #expect(summary.title == nil)
        #expect(summary.authors == nil)
    }

    @Test("EPUB progress carries the CFI and spine href")
    func epubProgress() throws {
        let json = Data(#"""
        {"cfi":"epubcfi(/6/14!/4/2/2[c01]/2/1:0)","href":"chapter1.xhtml",
         "percentage":0.42,"updatedAt":"2026-08-26T18:32:00.543Z"}
        """#.utf8)
        let progress = try JSONCoding.decoder.decode(EpubProgress.self, from: json)
        #expect(progress.cfi?.hasPrefix("epubcfi(") == true)
        #expect(progress.href == "chapter1.xhtml")
        #expect(progress.percentage == 0.42)
    }
}

/// Anchors `Bundle(for:)` to the test bundle so fixtures resolve.
private final class FixtureAnchor {}
