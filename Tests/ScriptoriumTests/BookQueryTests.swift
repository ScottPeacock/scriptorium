import Foundation
@testable import Scriptorium
import Testing

@Suite("Book list query parameters")
struct BookQueryTests {
    @Test("Defaults carry paging and sorting")
    func defaults() {
        let items = BookQuery().queryItems
        #expect(items.contains(URLQueryItem(name: "page", value: "0")))
        #expect(items.contains(URLQueryItem(name: "sort", value: "recentlyAdded")))
        #expect(items.contains(URLQueryItem(name: "dir", value: "desc")))
    }

    @Test("Unset filters are omitted rather than sent empty")
    func omitsUnsetFilters() {
        let names = Set(BookQuery().queryItems.map(\.name))
        #expect(!names.contains("libraryId"))
        #expect(!names.contains("shelfId"))
        #expect(!names.contains("search"))
        #expect(!names.contains("status"))
    }

    @Test("Scoping to a library sends libraryId")
    func libraryScope() {
        var query = BookQuery()
        query.libraryId = 3
        #expect(query.queryItems.contains(URLQueryItem(name: "libraryId", value: "3")))
    }

    @Test("Status is repeated per value, which is how Spring binds List<String>")
    func repeatedStatus() {
        var query = BookQuery()
        query.status = ["READING", "UNREAD"]
        let statuses = query.queryItems.filter { $0.name == "status" }.map(\.value)
        #expect(statuses == ["READING", "UNREAD"])
    }

    @Test("nextPage advances only the page")
    func nextPage() {
        var query = BookQuery()
        query.libraryId = 9
        let next = query.nextPage()
        #expect(next.page == 1)
        #expect(next.libraryId == 9)
        #expect(query.page == 0)
    }
}
