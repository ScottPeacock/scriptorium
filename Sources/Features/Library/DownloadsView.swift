import SwiftUI

/// Books available without the server — the list that still works on a plane.
struct DownloadsView: View {
    let connection: ServerConnection

    var body: some View {
        List {
            ForEach(connection.downloads.downloads) { record in
                NavigationLink(value: record.bookId) {
                    HStack(spacing: 12) {
                        BookCoverView(
                            bookId: record.bookId,
                            updatedAt: nil,
                            title: record.title
                        )
                        .frame(width: 40)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.title ?? record.fileName).lineLimit(2)
                            Text(sizeLabel(record))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                let records = connection.downloads.downloads
                for index in indexSet where records.indices.contains(index) {
                    connection.downloads.remove(bookId: records[index].bookId)
                }
            }
        }
        .navigationTitle("Downloaded")
        .navigationDestination(for: Int64.self) { bookId in
            BookDetailView(bookId: bookId)
        }
        .overlay {
            if connection.downloads.downloads.isEmpty {
                ContentUnavailableView(
                    "Nothing downloaded",
                    systemImage: "arrow.down.circle",
                    description: Text("Download a book to read it without a connection.")
                )
            }
        }
        .task { connection.downloads.refreshFromDisk() }
    }

    private func sizeLabel(_ record: DownloadRecord) -> String {
        let size = ByteCountFormatter.string(fromByteCount: record.byteSize, countStyle: .file)
        guard let type = record.bookType, !type.isEmpty else { return size }
        return "\(type.uppercased()) · \(size)"
    }
}
