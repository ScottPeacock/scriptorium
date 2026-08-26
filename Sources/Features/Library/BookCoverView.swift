import SwiftUI

/// Covers need an Authorization header, so this replaces AsyncImage.
/// Falls back to a title placeholder — plenty of self-hosted libraries have
/// books with no cover art at all, and an empty grey box tells you nothing.
struct BookCoverView: View {
    let bookId: Int64
    let updatedAt: Date?
    let title: String?
    var size: CoverSize = .thumbnail

    @Environment(\.coverLoader) private var loader
    @State private var image: UIImage?
    @State private var didAttempt = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        )
        .task(id: bookId) {
            guard !didAttempt, let loader else { return }
            image = await loader.image(bookId: bookId, updatedAt: updatedAt, size: size)
            didAttempt = true
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if didAttempt {
                    Text(title ?? "Untitled")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(6)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
    }
}

extension EnvironmentValues {
    @Entry var coverLoader: CoverLoader?
}
