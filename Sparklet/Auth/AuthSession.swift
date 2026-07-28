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

    func signOut() {
        KeychainTokenStore.clear()
        token = nil
    }
}
