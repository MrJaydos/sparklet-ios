import Foundation

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var details: ProfileDetailsResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var isSavingName = false
    @Published var name = ""

    private let api = ProfileAPI()
    private let authSession: AuthSession

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func loadIfNeeded() async {
        guard details == nil else { return }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.fetchDetails(token: authSession.token)
            details = response
            name = response.name
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the screen just shows whatever loaded, if anything.
        }
    }

    func saveName() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != details?.name else { return }
        isSavingName = true
        defer { isSavingName = false }
        do {
            try await api.updateName(trimmed, token: authSession.token)
            await load()
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the field just keeps its unsaved local value.
        }
    }
}
