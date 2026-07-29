import Foundation

@MainActor
final class FriendsViewModel: ObservableObject {
    @Published private(set) var friends: [FriendRow] = []
    @Published private(set) var incoming: [FriendRow] = []
    @Published private(set) var outgoing: [FriendRow] = []
    @Published private(set) var friendCode: String?
    @Published private(set) var isLoading = false
    // The row currently mid accept/remove — disables its own buttons only,
    // same as the web FriendsPanel's busyId.
    @Published private(set) var busyId: String?
    @Published var notice: String?

    private let api = FriendsAPI()
    private let authSession: AuthSession

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.fetch(token: authSession.token)
            friends = response.friends
            incoming = response.incoming
            outgoing = response.outgoing
            friendCode = response.friendCode
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the screen just shows whatever loaded, if anything.
        }
    }

    // Same "@ means email, else a friend code" split as the web client —
    // see FriendsAPI.sendRequest. Surfaces the server's own message either
    // way (a generic "request sent" for email, an honest error for a bad
    // code — see the route's comment on why those two cases differ).
    func sendRequest(_ value: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let response = try await api.sendRequest(trimmed, token: authSession.token)
            notice = response.message
            await load()
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch APIError.server(_, let body) {
            notice = Self.errorMessage(fromBody: body) ?? "Couldn't send that request."
        } catch {
            notice = "Couldn't send that request."
        }
    }

    func accept(_ friendshipId: String) async {
        busyId = friendshipId
        defer { busyId = nil }
        do {
            try await api.accept(friendshipId: friendshipId, token: authSession.token)
            await load()
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the row just stays put, user can retry.
        }
    }

    // Declining, cancelling, and unfriending are all the same call — see
    // FriendsAPI.remove.
    func remove(_ friendshipId: String) async {
        busyId = friendshipId
        defer { busyId = nil }
        do {
            try await api.remove(friendshipId: friendshipId, token: authSession.token)
            await load()
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the row just stays put, user can retry.
        }
    }

    private struct ErrorBody: Decodable { let error: String }
    private static func errorMessage(fromBody body: String) -> String? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).error
    }
}
