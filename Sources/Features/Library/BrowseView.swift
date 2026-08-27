import SwiftUI

/// Navigation into the server's own organisation: libraries, shelves, the
/// rule-based "magic" shelves, and series.
struct BrowseView: View {
    let connection: ServerConnection

    @State private var libraries: [AppLibrarySummary] = []
    @State private var shelves: [AppShelfSummary] = []
    @State private var magicShelves: [AppMagicShelfSummary] = []
    // Per-section, so one endpoint failing doesn't hide the others. A 500 on
    // smart shelves should not blank out your libraries.
    @State private var failures: [String: String] = [:]
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
                    NavigationLink(value: BrowseRoute.downloaded) {
                        Label("Downloaded", systemImage: "arrow.down.circle")
                    }
                }

                if !libraries.isEmpty {
                    Section("Libraries") {
                        ForEach(libraries) { library in
                            NavigationLink(value: BrowseRoute.library(library.id, library.name ?? "Library")) {
                                LabeledContent {
                                    if let count = library.bookCount {
                                        Text("\(count)").foregroundStyle(.secondary)
                                    }
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

                if !failures.isEmpty {
                    Section {
                        ForEach(failures.sorted(by: { $0.key < $1.key }), id: \.key) { section, message in
                            VStack(alignment: .leading, spacing: 2) {
                                Label("Couldn't load \(section)", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
        case .downloaded:
            DownloadsView(connection: connection)
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
        let service = connection.library
        var problems: [String: String] = [:]

        // Each section loads on its own so a failure is contained and named.
        async let loadedLibraries = Result { try await service.libraries() }
        async let loadedShelves = Result { try await service.shelves() }
        async let loadedMagic = Result { try await service.magicShelves() }

        switch await loadedLibraries {
        case let .success(value): libraries = value
        case let .failure(error): problems["libraries"] = Self.describe(error)
        }
        switch await loadedShelves {
        case let .success(value): shelves = value
        case let .failure(error): problems["shelves"] = Self.describe(error)
        }
        switch await loadedMagic {
        case let .success(value): magicShelves = value
        case let .failure(error): problems["smart shelves"] = Self.describe(error)
        }

        failures = problems
        isLoading = false
    }

    private static func describe(_ error: any Error) -> String {
        (error as? APIError)?.localizedDescription ?? error.localizedDescription
    }
}

extension Result where Failure == any Error {
    /// `async let` needs a non-throwing expression to run these concurrently.
    init(catching body: () async throws -> Success) async {
        do {
            self = try await .success(body())
        } catch {
            self = .failure(error)
        }
    }
}

enum BrowseRoute: Hashable {
    case allBooks
    case downloaded
    case library(Int64, String)
    case shelf(Int64, String)
    case magicShelf(Int64, String)
    case series
    case seriesBooks(String)
}
