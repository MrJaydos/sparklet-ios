import Foundation

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published var selectedSlugs: Set<String> = []
    @Published var name = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false

    private let api = OnboardingAPI()
    private let profileAPI = ProfileAPI()
    private let authSession: AuthSession

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func loadCategories() async {
        isLoading = true
        defer { isLoading = false }
        do {
            categories = try await api.fetchCategories(token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the grid just stays empty; Skip still completes
            // onboarding either way.
        }
    }

    func toggle(_ slug: String) {
        if selectedSlugs.contains(slug) {
            selectedSlugs.remove(slug)
        } else {
            selectedSlugs.insert(slug)
        }
    }

    // Same order as the web client's OnboardingGrid.submit: save the name
    // first (if any), then the picks (or an empty array for "skip — show me
    // everything," which still completes onboarding server-side). Errors are
    // swallowed rather than surfaced — same as the web's `finally { router.
    // push("/feed") }`, this is a one-time, low-stakes preference the user
    // can always redo, not worth blocking the app on.
    func complete(skip: Bool) async {
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !trimmedName.isEmpty {
                try await profileAPI.updateName(trimmedName, token: authSession.token)
            }
            try await api.submitInterests(
                categorySlugs: skip ? [] : Array(selectedSlugs),
                token: authSession.token
            )
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — see doc comment above.
        }
    }
}
