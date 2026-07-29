import SwiftUI

@main
struct SparkletApp: App {
    @StateObject private var authSession = AuthSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authSession)
                // The web app has no light mode (globals.css hardcodes a
                // near-black background) — forcing dark here instead of
                // adapting to the system setting keeps this app the same
                // fixed theme, not a lighter variant.
                .preferredColorScheme(.dark)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var authSession: AuthSession

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if authSession.isSignedIn {
                FeedView(authSession: authSession)
            } else {
                LoginView()
            }
        }
    }
}
