import SwiftUI

struct BookGridView: View {
    @Bindable var model: BookGridModel
    var title: String

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            if model.isLoadingFirstPage {
                ProgressView().padding(.top, 60)
            } else if let errorMessage = model.errorMessage, model.books.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load books", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await model.refresh() } }
                }
                .padding(.top, 40)
            } else if model.isEmpty {
                ContentUnavailableView(
                    "No books here",
                    systemImage: "books.vertical",
                    description: Text("Nothing in this collection yet.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(model.books) { book in
                        NavigationLink(value: book) {
                            BookGridCell(book: book)
                        }
                        .buttonStyle(.plain)
                        .task { await model.loadMoreIfNeeded(currentItem: book) }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if model.isLoadingMore {
                    ProgressView().padding(.vertical, 20)
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(for: AppBookSummary.self) { book in
            BookDetailView(bookId: book.id, fallbackTitle: book.title)
        }
        .refreshable { await model.refresh() }
        .task { await model.loadFirstPageIfNeeded() }
    }
}

struct BookGridCell: View {
    let book: AppBookSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BookCoverView(bookId: book.id, updatedAt: book.coverUpdatedOn, title: book.title)
                .overlay(alignment: .bottom) {
                    if let progress = book.readProgress, progress > 0, progress < 1 {
                        ProgressView(value: Double(progress))
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                    }
                }

            Text(book.title ?? "Untitled")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            if let author = book.authors?.first {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
