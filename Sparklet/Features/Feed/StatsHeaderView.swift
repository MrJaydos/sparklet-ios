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
    let onOpenLeaderboard: () -> Void
    let onOpenProfile: () -> Void

    @State private var showingStreakInfo = false
    @State private var showingXpInfo = false

    var body: some View {
        HStack(spacing: 14) {
            if let profile {
                Button {
                    showingStreakInfo = true
                } label: {
                    Label("\(profile.currentStreak)", systemImage: "flame.fill")
                }
                .foregroundStyle(.orange)
                Button {
                    showingXpInfo = true
                } label: {
                    Label("\(profile.xpToday)/\(profile.xpGoal) XP", systemImage: "star.fill")
                }
                .foregroundStyle(.yellow)
                Spacer()
                profileButton
                leaderboardButton
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
        .sheet(isPresented: $showingStreakInfo) {
            if let profile {
                StreakInfoView(
                    streak: profile.currentStreak,
                    longestStreak: profile.longestStreak,
                    freezesAvailable: profile.freezesAvailable
                )
            }
        }
        .sheet(isPresented: $showingXpInfo) {
            if let profile {
                XpInfoView(today: profile.xpToday, goal: profile.xpGoal)
            }
        }
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

    private var leaderboardButton: some View {
        Button(action: onOpenLeaderboard) {
            Image(systemName: "trophy.fill")
        }
        .foregroundStyle(Theme.textTertiary)
    }

    private var profileButton: some View {
        Button(action: onOpenProfile) {
            Image(systemName: "person.crop.circle")
        }
        .foregroundStyle(Theme.textTertiary)
    }
}
