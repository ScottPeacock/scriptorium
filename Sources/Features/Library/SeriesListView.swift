import SwiftUI

struct SeriesListView: View {
    let connection: ServerConnection

    @State private var series: [AppSeriesSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(series) { entry in
                NavigationLink(value: BrowseRoute.seriesBooks(entry.seriesName)) {
                    HStack(spacing: 12) {
                        if let cover = entry.coverBooks?.first, let bookId = cover.bookId {
                            BookCoverView(
                                bookId: bookId,
                                updatedAt: cover.coverUpdatedOn,
                                title: entry.seriesName
                            )
                            .frame(width: 44)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.seriesName).lineLimit(1)
                            Text(subtitle(for: entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Series")
        .overlay {
            if isLoading {
                ProgressView()
            } else if series.isEmpty, errorMessage == nil {
                ContentUnavailableView(
                    "No series",
                    systemImage: "square.stack",
                    description: Text("Books grouped into a series will appear here.")
                )
            }
        }
        .task { await load() }
    }

    private func subtitle(for entry: AppSeriesSummary) -> String {
        let total = entry.seriesTotal ?? entry.bookCount
        let books = "\(entry.bookCount) of \(total) book\(total == 1 ? "" : "s")"
        return entry.booksRead > 0 ? "\(books) · \(entry.booksRead) read" : books
    }

    private func load() async {
        do {
            // Series listings are usually short enough that one generous page
            // covers a personal library; paging can come with the filter UI.
            series = try await connection.library.series(page: 0, size: 200).content
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
