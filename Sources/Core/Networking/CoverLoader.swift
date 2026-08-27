import Foundation
import UIKit

/// Loads book covers, which are authenticated: `/api/v1/media/book/{id}/...`
/// requires a Bearer token, and Grimmory's query-parameter JWT filter is
/// registered disabled, so there is no `?token=` shortcut. That rules out
/// `AsyncImage`, which cannot set headers — hence this.
///
/// Cache keys include `coverUpdatedOn`, so re-fetching metadata on the server
/// invalidates the cached image for free rather than serving a stale cover.
actor CoverLoader {
    private let client: GrimmoryClient
    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    /// Caps how many covers are fetched at once. A fast scroll through a large
    /// grid would otherwise fire dozens of requests at someone's home server
    /// and starve the data requests behind them.
    private let concurrencyLimit = 4
    private var activeFetches = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(client: GrimmoryClient, accountID: UUID) {
        self.client = client
        memory.countLimit = 300

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("covers/\(accountID.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(bookId: Int64, updatedAt: Date?, size: CoverSize) async -> UIImage? {
        let key = Self.cacheKey(bookId: bookId, updatedAt: updatedAt, size: size)

        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }

        // Collapse duplicate requests — a grid scrolling fast will ask for the
        // same cover several times before the first fetch returns.
        if let existing = inFlight[key] {
            return await existing.value
        }

        await acquireSlot()

        let task = Task<UIImage?, Never> { [directory, client] in
            let fileURL = directory.appendingPathComponent(key)
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                return image
            }
            guard let data = try? await client.sendForData(size.endpoint(bookId: bookId)),
                  let image = UIImage(data: data)
            else { return nil }
            try? data.write(to: fileURL, options: .atomic)
            return image
        }

        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        releaseSlot()

        if let image {
            memory.setObject(image, forKey: key as NSString)
        }
        return image
    }

    private func acquireSlot() async {
        if activeFetches < concurrencyLimit {
            activeFetches += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
        activeFetches += 1
    }

    private func releaseSlot() {
        activeFetches -= 1
        if !waiting.isEmpty {
            waiting.removeFirst().resume()
        }
    }

    /// Drops every cached cover for this account.
    func clearCache() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func cacheSizeBytes() -> Int64 {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return contents.reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private static func cacheKey(bookId: Int64, updatedAt: Date?, size: CoverSize) -> String {
        let stamp = updatedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        return "\(bookId)-\(stamp)-\(size.rawValue)"
    }
}

enum CoverSize: String, Sendable {
    /// Smaller image, served by the server's thumbnail endpoint. Use in grids.
    case thumbnail
    /// Full-size cover. Use on detail screens.
    case full

    func endpoint(bookId: Int64) -> GrimmoryEndpoint {
        switch self {
        case .thumbnail: .thumbnail(bookId: bookId)
        case .full: .cover(bookId: bookId)
        }
    }
}
