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
                Text("\(card.category.icon) \(card.category.name)")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.panelAlt, in: Capsule())
                Spacer()
            }

            if let imageUrl = card.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.panelAlt
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Text(card.title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            Text(card.body)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)

            if let firstSource = card.sources.first, let sourceURL = URL(string: firstSource.url) {
                Link(firstSource.publisher, destination: sourceURL)
                    .font(.caption)
                    .foregroundStyle(Theme.accentText)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }
}
