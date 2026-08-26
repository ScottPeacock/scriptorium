import SwiftUI

struct BookDetailView: View {
    let bookId: Int64
    var fallbackTitle: String?

    @Environment(SessionModel.self) private var session
    @State private var detail: AppBookDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if let detail {
                content(detail)
            } else if isLoading {
                ProgressView().padding(.top, 60)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Couldn't load this book", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
                .padding(.top, 40)
            }
        }
        .navigationTitle(detail?.title ?? fallbackTitle ?? "Book")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func content(_ book: AppBookDetail) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(book)

            // The reader arrives at M4; downloads at M3.
            Button {} label: {
                Label("Read", systemImage: "book")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)

            if let description = book.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").font(.headline)
                    Text(description).font(.callout)
                }
            }

            detailsGrid(book)
        }
        .padding()
    }

    private func header(_ book: AppBookDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            BookCoverView(
                bookId: book.id,
                updatedAt: book.coverUpdatedOn,
                title: book.title,
                size: .full
            )
            .frame(width: 130)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title ?? "Untitled")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let subtitle = book.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                if let authors = book.authors, !authors.isEmpty {
                    Text(authors.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let series = book.seriesName {
                    let number = book.seriesNumber.map { " #\(formatted($0))" } ?? ""
                    Text("\(series)\(number)").font(.caption).foregroundStyle(.secondary)
                }
                if let progress = book.readProgress, progress > 0 {
                    ProgressView(value: Double(progress))
                        .progressViewStyle(.linear)
                        .padding(.top, 4)
                    Text("\(Int(progress * 100))% read")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func detailsGrid(_ book: AppBookDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Details").font(.headline)
            detailRow("Library", book.libraryName)
            detailRow("Publisher", book.publisher)
            detailRow("Language", book.language)
            detailRow("Pages", book.pageCount.map(String.init))
            detailRow("ISBN", book.isbn13)
            detailRow("Format", book.primaryFileType)
            if let categories = book.categories, !categories.isEmpty {
                detailRow("Categories", categories.joined(separator: ", "))
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).multilineTextAlignment(.trailing)
            }
            .font(.callout)
        }
    }

    private func formatted(_ number: Float) -> String {
        number == number.rounded() ? String(Int(number)) : String(number)
    }

    private func load() async {
        guard let connection = session.connection else { return }
        errorMessage = nil
        do {
            detail = try await connection.library.bookDetail(id: bookId)
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
