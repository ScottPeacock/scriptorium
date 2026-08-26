import Foundation

/// Mirrors Grimmory's `BookListRequest`, which arrives as `@ModelAttribute` —
/// i.e. flat query parameters, not a JSON body.
///
/// The server record has ~40 fields, most of them metadata facets. Only the
/// ones the app actually drives are modelled here; the rest can be added as
/// filtering UI needs them.
struct BookQuery: Sendable, Equatable {
    enum Sort: String, Sendable, CaseIterable {
        case title
        case addedOn = "recentlyAdded"
        case lastRead = "lastReadTime"
        case rating = "personalRating"
    }

    enum Direction: String, Sendable {
        case ascending = "asc"
        case descending = "desc"
    }

    var page = 0
    var size = 40
    var sort: Sort = .addedOn
    var direction: Direction = .descending
    var libraryId: Int64?
    var shelfId: Int64?
    var magicShelfId: Int64?
    var search: String?
    /// Read-status facet values, e.g. "READING", "UNREAD".
    var status: [String] = []

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = [
            .init(name: "page", value: "\(page)"),
            .init(name: "size", value: "\(size)"),
            .init(name: "sort", value: sort.rawValue),
            .init(name: "dir", value: direction.rawValue)
        ]
        if let libraryId {
            items.append(.init(name: "libraryId", value: "\(libraryId)"))
        }
        if let shelfId {
            items.append(.init(name: "shelfId", value: "\(shelfId)"))
        }
        if let magicShelfId {
            items.append(.init(name: "magicShelfId", value: "\(magicShelfId)"))
        }
        if let search, !search.isEmpty {
            items.append(.init(name: "search", value: search))
        }
        // Spring binds a repeated parameter to List<String>.
        items.append(contentsOf: status.map { URLQueryItem(name: "status", value: $0) })
        return items
    }

    func nextPage() -> BookQuery {
        var copy = self
        copy.page += 1
        return copy
    }
}
