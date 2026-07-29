import SwiftUI

// Kept visually and logically separate, per AGENTS.md: the streak/XP ring
// answers "did I hit my XP today", the (unused here yet) card-count goal
// answers a different question and should never be merged into this row.
struct StatsHeaderView: View {
    let profile: ProfileResponse?
    // Explicit refresh affordance instead of `.refreshable` — see the
    // comment on FeedView's refresh button for why.
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let unreadNotifications: Int
    let onOpenNotifications: () -> Void
    let onOpenFriends: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if let profile {
                Label("\(profile.currentStreak)", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
                Label("\(profile.xpToday)/\(profile.xpGoal) XP", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
                Spacer()
                friendsButton
                notificationsButton
                refreshButton
            } else {
                Spacer()
                ProgressView().tint(Theme.textTertiary)
                Spacer()
            }
        }
        .font(.subheadline.bold())
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal)
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            if isRefreshing {
                ProgressView().tint(Theme.textTertiary)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .foregroundStyle(Theme.textTertiary)
        .disabled(isRefreshing)
    }

    private var notificationsButton: some View {
        Button(action: onOpenNotifications) {
            Image(systemName: unreadNotifications > 0 ? "bell.badge.fill" : "bell")
        }
        .foregroundStyle(unreadNotifications > 0 ? Theme.accentBright : Theme.textTertiary)
    }

    private var friendsButton: some View {
        Button(action: onOpenFriends) {
            Image(systemName: "person.2.fill")
        }
        .foregroundStyle(Theme.textTertiary)
    }
}
