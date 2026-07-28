import SwiftUI

@main
struct SparkletApp: App {
    @StateObject private var authSession = AuthSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authSession)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var authSession: AuthSession

    var body: some View {
        if authSession.isSignedIn {
            FeedView(authSession: authSession)
        } else {
            LoginView()
        }
    }
}
