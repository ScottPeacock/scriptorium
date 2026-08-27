import SwiftUI

struct HomeView: View {
    let connection: ServerConnection

    @State private var continueReading: [AppBookSummary] = []
    @State private var recentlyAdded: [AppBookSummary] = []
    @State private var fromLibrary: [AppBookSummary] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView().padding(.top, 60)
                } else if let errorMessage, continueReading.isEmpty, recentlyAdded.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't reach your library", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        if !continueReading.isEmpty {
                            BookSection(title: "Continue reading", books: continueReading)
                        }
                        if !recentlyAdded.isEmpty {
                            BookSection(title: "Recently added", books: recentlyAdded)
                        }
                        if !fromLibrary.isEmpty {
                            BookSection(title: "From your library", books: fromLibrary)
                        }
                        if continueReading.isEmpty, recentlyAdded.isEmpty, fromLibrary.isEmpty {
                            ContentUnavailableView(
                                "Nothing to read yet",
                                systemImage: "books.vertical",
                                description: Text("Books you add on the server will show up here.")
                            )
                            .padding(.top, 40)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle(connection.account.displayName)
            .navigationDestination(for: AppBookSummary.self) { book in
                BookDetailView(bookId: book.id, fallbackTitle: book.title)
            }
            .refreshable { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        let service = connection.library
        do {
            // Independent requests — no reason to wait for one before the other.
            async let reading = service.continueReading()
            async let recent = service.recentlyAdded()
            continueReading = try await reading
            recentlyAdded = try await recent

            // The server's "recently added" only looks back 30 days, so an
            // established library leaves this screen empty and looking broken.
            // Fall back to the newest books overall, which has no such window.
            if continueReading.isEmpty, recentlyAdded.isEmpty {
                var query = BookQuery()
                query.size = 30
                query.sort = .addedOn
                fromLibrary = try await service.books(query).content
            } else {
                fromLibrary = []
            }
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}

/// A titled block of covers laid out in a grid, so Home scrolls down as one
/// page rather than sideways per section.
struct BookSection: View {
    let title: String
    let books: [AppBookSummary]

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(books) { book in
                    NavigationLink(value: book) {
                        BookGridCell(book: book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}
