import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

// Styled to match a real card's own shape (chip → image → title → body),
// not a boxed panel set apart from the rest of the feed — flagged live by
// the user as looking out of place once every other slide went edge-to-edge
// with a category-tinted gradient (see this session's card redesign). The
// web's own AdSlide.tsx is a plain centered "Sponsored" label + ad unit
// with no such card framing, so this is a deliberate iOS-only departure,
// not a port: still an honest, prominent "Sponsored" label (never
// disguised as a real fact — that's an AdMob policy line, not just a
// style choice), just with a bit of the same self-aware, slightly cheeky
// tone Reddit's own promoted posts use, dressed in the same chip/title/
// body rhythm as CardView so it reads as part of the feed rather than an
// interruption to it.
struct AdSlideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🤑 Sponsored")
                    .font(.caption.bold())
                    .foregroundStyle(chipColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(chipColor.opacity(0.2), in: Capsule())
                Spacer()
            }

            // Renders nothing if UMP consent hasn't resolved to "can request
            // ads" yet — same "fail silently, never block the feed"
            // philosophy as the web's own AdSlide (which no-ops if the
            // AdSense env vars are absent). Sits where a card's image would,
            // same corner radius, so it reads as this slide's "photo"
            // rather than a bolted-on separate element.
            if ConsentInformation.shared.canRequestAds {
                BannerAdView()
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            Text("Okay, this one's an ad")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            Text("Someone paid for you to see this so the next few hundred facts stay free. Back to actual learning right after this.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var chipColor: Color { Color(hexString: "#fbbf24") }
}

// UIViewRepresentable wrapper around BannerView (GADBannerView) — Google's
// SDK is UIKit-only, no native SwiftUI view type. rootViewController is
// left unset: BannerView.h documents that when nil, "the view controller
// containing the banner view is used," which SwiftUI's UIHostingController
// bridging satisfies without needing to resolve one manually here.
private struct BannerAdView: UIViewRepresentable {
    // Google's public test banner ad unit id — always serves a test
    // creative, never real inventory or spend. Swap for the app's own ad
    // unit id once a real AdMob app/ad unit exists (see AGENTS.md).
    private static let testAdUnitID = "ca-app-pub-3940256099942544/2435281174"

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeMediumRectangle)
        banner.adUnitID = Self.testAdUnitID
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
