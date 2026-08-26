import Foundation
import Observation

/// Paged, infinitely-scrolling list of books.
///
/// The source is a closure rather than a fixed endpoint so the same grid backs
/// "all books", a library, a shelf, a series and search results.
@Observable
@MainActor
final class BookGridModel {
    typealias Page = AppPageResponse<AppBookSummary>
    typealias Loader = @Sendable (Int) async throws -> Page

    private(set) var books: [AppBookSummary] = []
    private(set) var isLoadingFirstPage = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var totalCount: Int?

    private var nextPage = 0
    private var hasMore = true
    private let load: Loader

    init(load: @escaping Loader) {
        self.load = load
    }

    var isEmpty: Bool {
        books.isEmpty && !isLoadingFirstPage && errorMessage == nil
    }

    func loadFirstPageIfNeeded() async {
        guard books.isEmpty, !isLoadingFirstPage else { return }
        isLoadingFirstPage = true
        await fetch(reset: true)
        isLoadingFirstPage = false
    }

    func refresh() async {
        await fetch(reset: true)
    }

    /// Called as cells appear. Triggers a fetch when the given book is near the
    /// end of what's loaded.
    func loadMoreIfNeeded(currentItem book: AppBookSummary) async {
        guard hasMore, !isLoadingMore, !isLoadingFirstPage else { return }
        let threshold = 8
        guard let index = books.firstIndex(of: book),
              index >= books.count - threshold
        else { return }

        isLoadingMore = true
        await fetch(reset: false)
        isLoadingMore = false
    }

    private func fetch(reset: Bool) async {
        if reset {
            nextPage = 0
            hasMore = true
        }
        guard hasMore else { return }

        do {
            let page = try await load(nextPage)
            errorMessage = nil
            totalCount = page.totalElements
            if reset {
                books = page.content
            } else {
                // Guard against duplicates: if books are added server-side while
                // paging, the same row can arrive on two pages.
                let known = Set(books.map(\.id))
                books.append(contentsOf: page.content.filter { !known.contains($0.id) })
            }
            hasMore = page.hasNext
            nextPage = page.page + 1
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            hasMore = false
        }
    }
}
