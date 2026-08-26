import SwiftUI

struct SearchView: View {
    let connection: ServerConnection

    @State private var text = ""
    @State private var results: [AppBookSummary] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { book in
                    NavigationLink(value: book) {
                        HStack(spacing: 12) {
                            BookCoverView(
                                bookId: book.id,
                                updatedAt: book.coverUpdatedOn,
                                title: book.title
                            )
                            .frame(width: 40)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.title ?? "Untitled").lineLimit(2)
                                if let author = book.authors?.first {
                                    Text(author).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: AppBookSummary.self) { book in
                BookDetailView(bookId: book.id, fallbackTitle: book.title)
            }
            .searchable(text: $text, prompt: "Titles, authors, series")
            .onChange(of: text) { _, newValue in
                // Debounce: the server does a full-text query per keystroke otherwise.
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await search(newValue)
                }
            }
            .overlay { overlay }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if isSearching {
            ProgressView()
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Search failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            }
        } else if text.isEmpty {
            ContentUnavailableView(
                "Search your library",
                systemImage: "magnifyingglass",
                description: Text("Find books by title, author or series.")
            )
        } else if results.isEmpty {
            ContentUnavailableView.search(text: text)
        }
    }

    private func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil
        do {
            results = try await connection.library.search(trimmed).content
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        isSearching = false
    }
}
