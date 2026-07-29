import Foundation

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var notifications: [NotificationItem] = []
    @Published private(set) var adminAlerts: [NotificationAlert] = []
    @Published private(set) var friendAlerts: [NotificationAlert] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var isLoading = false

    private let api = NotificationsAPI()
    private let authSession: AuthSession

    init(authSession: AuthSession) {
        self.authSession = authSession
    }

    // Read-only refresh for the header bell's badge count — must NOT mark
    // anything read, only opening the full list does that (see
    // loadAndMarkRead), same as the web bell vs. the web notifications page.
    func refreshUnreadCount() async {
        do {
            let response = try await api.fetch(token: authSession.token)
            unreadCount = response.unreadCount
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the badge just stays at its last known count.
        }
    }

    // Mirrors the web notifications page: viewing the list marks every
    // real notification read (admin/friend alerts aren't persisted rows,
    // so nothing to mark — they clear themselves once resolved).
    func loadAndMarkRead() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await api.fetch(token: authSession.token)
            notifications = response.notifications
            adminAlerts = response.adminAlerts
            friendAlerts = response.friendAlerts
            unreadCount = response.unreadCount

            if response.notifications.contains(where: { !$0.read }) {
                try await api.markAllRead(token: authSession.token)
                notifications = notifications.map {
                    NotificationItem(id: $0.id, actorName: $0.actorName, cardId: $0.cardId, cardTitle: $0.cardTitle, preview: $0.preview, createdAt: $0.createdAt, read: true)
                }
                // Alerts aren't affected by mark-all-read — only the real
                // notification count drops out of the badge.
                let alertTotal = (adminAlerts + friendAlerts).reduce(0) { $0 + $1.count }
                unreadCount = alertTotal
            }
        } catch APIError.unauthorized {
            authSession.signOut()
        } catch {
            // Best-effort — the sheet just shows whatever loaded, if anything.
        }
    }
}
