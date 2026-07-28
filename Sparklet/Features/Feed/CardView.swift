import SwiftUI

struct CardView: View {
    let card: FeedCard

    var body: some View {
        // Each card fills exactly one page (FeedView's .containerRelativeFrame),
        // but body length varies (~40-80 words, occasionally more) and the
        // page height doesn't. A nested ScrollView here was tried and
        // reverted — a vertical scroll inside a .scrollTargetBehavior(.paging)
        // parent captures the drag gesture and breaks paging, which isn't
        // verifiable without a device/simulator. Known layout gap for now
        // (see AGENTS.md): an unusually long card is clipped rather than
        // scrollable within its page.
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(card.category.icon)
                Text(card.category.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if let imageUrl = card.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(card.title)
                .font(.headline)

            Text(card.body)
                .font(.body)
                .foregroundStyle(.secondary)

            if let firstSource = card.sources.first, let sourceURL = URL(string: firstSource.url) {
                Link(firstSource.publisher, destination: sourceURL)
                    .font(.caption)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
