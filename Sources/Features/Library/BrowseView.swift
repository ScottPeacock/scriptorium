import SwiftUI

/// Navigation into the server's own organisation: libraries, shelves, the
/// rule-based "magic" shelves, and series.
struct BrowseView: View {
    let connection: ServerConnection

    @State private var libraries: [AppLibrarySummary] = []
    @State private var shelves: [AppShelfSummary] = []
    @State private var magicShelves: [AppMagicShelfSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: BrowseRoute.allBooks) {
                        Label("All books", systemImage: "books.vertical")
                    }
                    NavigationLink(value: BrowseRoute.series) {
                        Label("Series", systemImage: "square.stack")
                    }
                }

                if !libraries.isEmpty {
                    Section("Libraries") {
                        ForEach(libraries) { library in
                            NavigationLink(value: BrowseRoute.library(library.id, library.name ?? "Library")) {
                                LabeledContent {
                                    Text("\(library.bookCount)").foregroundStyle(.secondary)
                                } label: {
                                    Label(library.name ?? "Library", systemImage: "building.columns")
                                }
                            }
                        }
                    }
                }

                if !shelves.isEmpty {
                    Section("Shelves") {
                        ForEach(shelves) { shelf in
                            NavigationLink(value: BrowseRoute.shelf(shelf.id, shelf.name ?? "Shelf")) {
                                LabeledContent {
                                    Text("\(shelf.bookCount)").foregroundStyle(.secondary)
                                } label: {
                                    Label(shelf.name ?? "Shelf", systemImage: "bookmark")
                                }
                            }
                        }
                    }
                }

                if !magicShelves.isEmpty {
                    Section {
                        ForEach(magicShelves) { shelf in
                            NavigationLink(value: BrowseRoute.magicShelf(shelf.id, shelf.name ?? "Shelf")) {
                                Label(shelf.name ?? "Shelf", systemImage: "wand.and.stars")
                            }
                        }
                    } header: {
                        Text("Smart shelves")
                    } footer: {
                        Text("Shelves the server fills automatically from rules you set.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button("Try again") { Task { await load() } }
                    }
                }
            }
            .navigationTitle("Browse")
            .navigationDestination(for: BrowseRoute.self) { route in
                destination(for: route)
            }
            .navigationDestination(for: AppBookSummary.self) { book in
                BookDetailView(bookId: book.id, fallbackTitle: book.title)
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .refreshable { await load() }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func destination(for route: BrowseRoute) -> some View {
        switch route {
        case .allBooks:
            grid(title: "All books") { $0 }
        case let .library(id, name):
            grid(title: name) { query in
                var scoped = query
                scoped.libraryId = id
                return scoped
            }
        case let .shelf(id, name):
            grid(title: name) { query in
                var scoped = query
                scoped.shelfId = id
                return scoped
            }
        case let .magicShelf(id, name):
            grid(title: name) { query in
                var scoped = query
                scoped.magicShelfId = id
                return scoped
            }
        case .series:
            SeriesListView(connection: connection)
        case let .seriesBooks(name):
            let service = connection.library
            BookGridView(
                model: BookGridModel { page in
                    try await service.seriesBooks(name: name, page: page)
                },
                title: name
            )
        }
    }

    /// Every browse destination is the same paged grid over a differently
    /// scoped query, so they share one builder.
    private func grid(
        title: String,
        scope: @escaping @Sendable (BookQuery) -> BookQuery
    ) -> some View {
        let service = connection.library
        return BookGridView(
            model: BookGridModel { page in
                var query = BookQuery()
                query.page = page
                return try await service.books(scope(query))
            },
            title: title
        )
    }

    private func load() async {
        errorMessage = nil
        let service = connection.library
        do {
            async let libs = service.libraries()
            async let shelfList = service.shelves()
            async let magic = service.magicShelves()
            libraries = try await libs
            shelves = try await shelfList
            magicShelves = try await magic
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

enum BrowseRoute: Hashable {
    case allBooks
    case library(Int64, String)
    case shelf(Int64, String)
    case magicShelf(Int64, String)
    case series
    case seriesBooks(String)
}
