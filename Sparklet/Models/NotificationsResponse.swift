import Foundation

// Mirrors the object shape returned by GET /api/notifications
// (sparklet/src/app/api/notifications/route.ts). adminAlerts/friendAlerts
// aren't persisted rows — they're live-computed action items (open reports,
// cards awaiting review, pending friend requests — see
// sparklet/src/lib/notifications.ts) that clear themselves once resolved,
// not something a client ever marks read.
struct NotificationsResponse: Decodable {
    let unreadCount: Int
    let adminAlerts: [NotificationAlert]
    let friendAlerts: [NotificationAlert]
    let notifications: [NotificationItem]
}

struct NotificationAlert: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let count: Int
}

struct NotificationItem: Decodable, Identifiable, Hashable {
    let id: String
    let actorName: String
    let cardId: String
    let cardTitle: String
    let preview: String?
    let createdAt: String
    let read: Bool
}
