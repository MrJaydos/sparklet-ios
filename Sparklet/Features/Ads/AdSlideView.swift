import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

// Mirrors AdSlide.tsx — a full-height, honestly-labeled "Sponsored" slide,
// shown only for free-tier users (gated in FeedViewModel.buildItems, not
// here). Styled as the same boxed panel every other feed slide uses
// (CardView/QuizCardView/etc.), rather than the web's plain unboxed slide —
// visual consistency with the rest of this app's feed matters more here
// than matching a web-only decoration choice.
struct AdSlideView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Text("SPONSORED")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textMuted)
                .tracking(1.5)

            // Renders nothing if UMP consent hasn't resolved to "can
            // request ads" yet — same "fail silently, never block the
            // feed" philosophy as the web's own AdSlide (which no-ops if
            // the AdSense env vars are absent).
            if ConsentInformation.shared.canRequestAds {
                BannerAdView()
                    .frame(width: 300, height: 250) // AdSizeMediumRectangle
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }
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
