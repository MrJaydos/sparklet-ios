import Foundation

@MainActor
final class LeaderboardViewModel: ObservableObject {
    enum Board: String, CaseIterable {
        case today, week, all, friends

        var label: String {
            switch self {
            case .today: return "Today"
            case .week: return "7 days"
            case .all: return "All time"
            case .friends: return "Friends"
            }
        }
    }

    @Published private(set) var response: LeaderboardResponse?
    @Published private(set) var isLoading = false
    @Published var board: Board = .today {
        didSet {
            guard oldValue != board else { return }
            Task { await load() }
        }
    }

    private let api = LeaderboardAPI()
    private let authSession: AuthSession

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    func loadIfNeeded() async {
        guard response == nil else { return }
        await load()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await api.fetch(board: board.rawValue, token: authSession.token)
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the board just shows whatever loaded, if anything.
        }
    }
}
