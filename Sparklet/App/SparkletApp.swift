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
                    await AdsManager.start()
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var authSession: AuthSession
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var pendingInviteRefId: String?
    // Owned here rather than inside LoginView so the magic-link fallback
    // below (.onOpenURL's AuthCallback case) can reach the exact same
    // ASWebAuthenticationSession instance to cancel it — see
    // LoginController.completeSignInFromExternalRedirect's comment.
    @State private var loginController = LoginController()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if authSession.isSignedIn {
                FeedView(authSession: authSession, purchaseManager: purchaseManager)
            } else {
                LoginView(controller: loginController)
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
            // Magic-link sign-in's only possible completion path — see
            // AuthCallback.swift's comment for why. Checked before the
            // invite case since both use the same custom scheme.
            if let code = AuthCallback.code(from: url) {
                Task {
                    if let token = try? await loginController.completeSignInFromExternalRedirect(code: code) {
                        authSession.signIn(token: token)
                    }
                }
                return
            }
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
