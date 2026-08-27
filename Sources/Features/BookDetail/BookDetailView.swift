import SwiftUI

struct BookDetailView: View {
    let bookId: Int64
    var fallbackTitle: String?

    @Environment(SessionModel.self) private var session
    @State private var detail: AppBookDetail?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var status: ReadStatus?
    @State private var rating: Int?
    @State private var ratingError: String?

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

            actions(book)

            if let description = book.description.map(HTMLText.plain(from:)), !description.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").font(.headline)
                    Text(description).font(.callout)
                }
            }

            statusAndRating(book)

            detailsGrid(book)
        }
        .padding()
    }

    @ViewBuilder
    private func actions(_ book: AppBookDetail) -> some View {
        if let connection = session.connection {
            actionStack(book: book, connection: connection)
        }
    }

    @ViewBuilder
    private func actionStack(book: AppBookDetail, connection: ServerConnection) -> some View {
        let downloads = connection.downloads
        let status = downloads.status(for: book.id)

        VStack(spacing: 10) {
            switch status {
            case .downloaded:
                NavigationLink {
                    readerDestination(book: book, connection: connection)
                } label: {
                    Label("Read", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isReadable(book) || downloads.localURL(for: book.id) == nil)

                Button("Remove download", role: .destructive) {
                    downloads.remove(bookId: book.id)
                }
                .font(.footnote)

            case let .downloading(fraction):
                if let fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
                Button("Cancel") { downloads.cancel(bookId: book.id) }
                    .font(.footnote)

            case .notDownloaded, .failed:
                Button {
                    downloads.download(book)
                } label: {
                    Label("Download to read", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!connection.user.canDownload)

                if case let .failed(message) = status {
                    Text(message).font(.footnote).foregroundStyle(.red)
                } else if !connection.user.canDownload {
                    Text("Your account doesn't have permission to download books.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !isReadable(book), let type = book.primaryFileType {
                Text("Scriptorium reads EPUB so far — this is \(type.uppercased()).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func readerDestination(book: AppBookDetail, connection: ServerConnection) -> some View {
        if let url = connection.downloads.localURL(for: book.id) {
            ReaderView(book: book, bookURL: url, progress: connection.progress)
        } else {
            ContentUnavailableView(
                "Download missing",
                systemImage: "arrow.down.circle",
                description: Text("The file is no longer on this device. Download it again.")
            )
        }
    }

    /// v1 reads EPUB only; other formats download but can't be opened yet.
    private func isReadable(_ book: AppBookDetail) -> Bool {
        if (book.primaryFileType ?? "").lowercased().contains("epub") {
            return true
        }
        return book.fileTypes?.contains { $0.lowercased().contains("epub") } ?? false
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

    @ViewBuilder
    private func statusAndRating(_ book: AppBookDetail) -> some View {
        if let connection = session.connection {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Status", selection: Binding(
                    get: { status ?? ReadStatus(serverValue: book.readStatus) ?? .unread },
                    set: { newValue in
                        status = newValue
                        connection.progress.record(status: newValue, bookId: book.id)
                    }
                )) {
                    ForEach(ReadStatus.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)

                HStack(spacing: 6) {
                    Text("Rating").foregroundStyle(.secondary)
                    Spacer()
                    ForEach(1 ... 5, id: \.self) { star in
                        let current = rating ?? book.personalRating ?? 0
                        Button {
                            rating = star
                            Task { await rate(star, bookId: book.id, connection: connection) }
                        } label: {
                            Image(systemName: star <= current ? "star.fill" : "star")
                                .foregroundStyle(star <= current ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.callout)

                if let ratingError {
                    Text(ratingError).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    /// Ratings aren't queued: they're a one-tap preference, not something you'd
    /// lose work over, and a stale one overwriting a newer one would be worse
    /// than the tap simply not taking.
    private func rate(_ value: Int, bookId: Int64, connection: ServerConnection) async {
        do {
            _ = try await connection.client.sendForData(
                .updateRating(bookId: bookId),
                body: UpdateRatingBody(rating: value)
            )
            ratingError = nil
        } catch {
            rating = nil
            ratingError = "Couldn't save that rating."
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
