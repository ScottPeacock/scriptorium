import Foundation
@testable import Scriptorium
import Testing
import UIKit

/// Renders the reader in each theme and writes PNGs into the test process's
/// temporary directory. Skipped unless SCRIPTORIUM_SNAPSHOTS is set (pass it as
/// TEST_RUNNER_SCRIPTORIUM_SNAPSHOTS to xcodebuild), so CI stays fast.
@Suite("Reader snapshots", .serialized)
@MainActor
struct ReaderSnapshotTests {
    private var outputDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCRIPTORIUM_SNAPSHOTS"] != nil else { return nil }
        // The app is sandboxed to its container, so host paths are not writable.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("scriptorium-snapshots", isDirectory: true)
        print("SNAPSHOT_DIR=\(directory.path)")
        return directory
    }

    @Test("Render each theme")
    func renderThemes() async throws {
        guard let outputDirectory else { return }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let book = try #require(
            Bundle(for: SnapshotAnchor.self).url(forResource: "sample", withExtension: "epub")
        )

        for theme in ReaderSettings.Theme.allCases {
            var settings = ReaderSettings()
            settings.theme = theme
            settings.fontSize = 110

            let harness = try ReaderHarness(bookURL: book, settings: settings)
            _ = try await harness.waitForReady()
            _ = try await harness.waitForLocation { $0.cfi != nil }
            // Let the paginator settle before capturing.
            try await Task.sleep(for: .milliseconds(600))

            try harness.snapshot(to: outputDirectory.appendingPathComponent("reader-\(theme.rawValue).png"))
        }
    }

    @Test("Render scrolled flow")
    func renderScrolled() async throws {
        guard let outputDirectory else { return }
        let book = try #require(
            Bundle(for: SnapshotAnchor.self).url(forResource: "sample", withExtension: "epub")
        )

        var settings = ReaderSettings()
        settings.flow = .scrolled
        settings.fontSize = 110

        let harness = try ReaderHarness(bookURL: book, settings: settings)
        _ = try await harness.waitForReady()
        _ = try await harness.waitForLocation { $0.cfi != nil }
        try await Task.sleep(for: .milliseconds(600))

        try harness.snapshot(to: outputDirectory.appendingPathComponent("reader-scrolled.png"))
    }
}

private final class SnapshotAnchor {}
