import SwiftUI
import UIKit

@main
struct SparkletApp: App {
    @StateObject private var authSession: AuthSession
    // A genuine app-wide singleton (unlike every other feature's
    // per-screen view model) — StoreKit's Transaction.updates listener
    // needs to run for the app's whole lifetime, not just while a
    // particular sheet is on screen, and ProfileView/UpgradeView both need
    // to observe the same live purchase state.
    @StateObject private var purchaseManager: PurchaseManager

    init() {
        let session = AuthSession()
        _authSession = StateObject(wrappedValue: session)
        _purchaseManager = StateObject(wrappedValue: PurchaseManager(authSession: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authSession)
                .environmentObject(purchaseManager)
                // The web app has no light mode (globals.css hardcodes a
                // near-black background) — forcing dark here instead of
                // adapting to the system setting keeps this app the same
                // fixed theme, not a lighter variant.
                .preferredColorScheme(.dark)
                .task {
                    purchaseManager.startListeningForTransactionUpdates()
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var authSession: AuthSession
    @State private var pendingInviteRefId: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if authSession.isSignedIn {
                FeedView(authSession: authSession)
            } else {
                LoginView()
            }
        }
        // Handles a tapped https://sparkletapp.com/invite/<id> link once
        // Universal Links are fully activated (see project.yml's
        // entitlements comment for what's still missing there) — until
        // then this simply never fires, and the link opens in Safari like
        // today. Also handles the same path via a direct onOpenURL, which
        // is how `xcrun simctl openurl` delivers it for local testing
        // without needing a real apple-app-site-association.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                pendingInviteRefId = InviteLink.refId(from: url)
            }
        }
        .onOpenURL { url in
            if let refId = InviteLink.refId(from: url) {
                pendingInviteRefId = refId
            }
        }
        .fullScreenCover(item: Binding(
            get: { pendingInviteRefId.map { InviteRoute(refId: $0) } },
            set: { pendingInviteRefId = $0?.refId }
        )) { route in
            InviteView(
                viewModel: InviteViewModel(authSession: authSession),
                refId: route.refId,
                onContinue: { pendingInviteRefId = nil }
            )
        }
    }
}

private struct InviteRoute: Identifiable {
    let refId: String
    var id: String { refId }
}
