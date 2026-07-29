import Foundation

@MainActor
final class InviteViewModel: ObservableObject {
    @Published private(set) var response: InviteResponse?
    @Published private(set) var isLoading = false

    private let api = InviteAPI()
    private let authSession: AuthSession

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func accept(refId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await api.accept(refId: refId, token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // No response set — the view shows a generic "couldn't load" state.
        }
    }
}
