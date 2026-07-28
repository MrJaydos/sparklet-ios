import Foundation
import Combine

// App-wide auth state. `token` is the bearer credential sent as
// `Authorization: Bearer <token>` on every API request (see
// Networking/APIClient.swift) — the native equivalent of the session
// cookie the web client relies on.
@MainActor
final class AuthSession: ObservableObject {
    @Published private(set) var token: String?

    var isSignedIn: Bool { token != nil }

    init() {
        token = KeychainTokenStore.load()
    }

    func signIn(token: String) {
        KeychainTokenStore.save(token)
        self.token = token
    }

    // Local-only: clears the token here without revoking it server-side.
    // Used today only as the automatic response to a 401 (see FeedViewModel/
    // StatsHeaderViewModel), where the token is already invalid — nothing to
    // revoke. An explicit user-initiated "Sign out" (no UI for one yet)
    // should call LoginController.signOut(token:) first, which actually
    // revokes the Session row, then this.
    func signOut() {
        KeychainTokenStore.clear()
        token = nil
    }
}
