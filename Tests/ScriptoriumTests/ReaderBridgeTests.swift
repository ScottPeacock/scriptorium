import Foundation
@testable import Scriptorium
import Testing
import WebKit

/// Drives the real reader page in a real WKWebView against a real EPUB.
///
/// This is the test that justifies the whole foliate-js decision: it proves a
/// CFI reported by the reader can be handed back to it and resolves to the same
/// place. That round-trip is what keeps the app in step with Grimmory's web
/// reader, Kobo and KOReader, all of which resolve against the same stored CFI.
@Suite("Reader bridge", .serialized)
@MainActor
struct ReaderBridgeTests {
    private static func sampleEPUB() throws -> URL {
        try #require(
            Bundle(for: ReaderFixtureAnchor.self).url(forResource: "sample", withExtension: "epub"),
            "Missing sample.epub fixture"
        )
    }

    @Test("Opens an EPUB and reports a table of contents")
    func opensBook() async throws {
        let harness = try ReaderHarness(bookURL: Self.sampleEPUB())
        let ready = try await harness.waitForReady()

        #expect(ready.title == "A Test Book")
        #expect(ready.toc.count == 3)
        #expect(ready.toc.first?.label == "The Wide Lawns")
    }

    @Test("A reported CFI resolves back to the same position")
    func cfiRoundTrip() async throws {
        let harness = try ReaderHarness(bookURL: Self.sampleEPUB())
        _ = try await harness.waitForReady()

        // Move a couple of pages in so we're not testing the trivial start.
        harness.commands.next()
        harness.commands.next()
        let original = try await harness.waitForLocation { $0.cfi != nil }
        let cfi = try #require(original.cfi)
        #expect(cfi.hasPrefix("epubcfi("))

        // Jump elsewhere, then return using only the CFI.
        harness.commands.goToFraction(0.9)
        _ = try await harness.waitForLocation { $0.cfi != nil && $0.cfi != cfi }

        harness.commands.goTo(cfi)
        let restored = try await harness.waitForLocation { $0.cfi == cfi }
        #expect(restored.cfi == cfi)
    }

    @Test("A stored CFI passed at open time restores the position")
    func restoresFromStoredCFI() async throws {
        let first = try ReaderHarness(bookURL: Self.sampleEPUB())
        _ = try await first.waitForReady()
        first.commands.goToFraction(0.6)
        let saved = try await first.waitForLocation { ($0.fraction ?? 0) > 0.3 }
        let savedCFI = try #require(saved.cfi)

        // A fresh reader, opened the way the app opens a book the server has a
        // position for.
        let second = try ReaderHarness(bookURL: Self.sampleEPUB(), startCFI: savedCFI)
        _ = try await second.waitForReady()
        let restored = try await second.waitForLocation { $0.cfi != nil }

        #expect(restored.cfi == savedCFI)
    }

    @Test("Progress fraction advances as pages turn")
    func progressAdvances() async throws {
        let harness = try ReaderHarness(bookURL: Self.sampleEPUB())
        _ = try await harness.waitForReady()
        let start = try await harness.waitForLocation { $0.fraction != nil }

        harness.commands.goToFraction(0.8)
        let later = try await harness.waitForLocation { ($0.fraction ?? 0) > (start.fraction ?? 0) }

        #expect((later.fraction ?? 0) > (start.fraction ?? 0))
    }
}

private final class ReaderFixtureAnchor {}
