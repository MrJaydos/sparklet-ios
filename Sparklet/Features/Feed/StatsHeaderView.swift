import SwiftUI

// Kept visually and logically separate, per AGENTS.md: the streak/XP ring
// answers "did I hit my XP today", the (unused here yet) card-count goal
// answers a different question and should never be merged into this row.
struct StatsHeaderView: View {
    let profile: ProfileResponse?
    // Mirrors Feed.tsx's topicLabel button — the topic filter trigger sits
    // first/leftmost in the web's header too, ahead of streak/XP.
    let topicLabel: String
    // Whether any topic is actually selected — drives the pill's own
    // accent styling below, flagged live by the user as not obvious enough
    // when a filter was active (the pill looked the same either way,
    // differing only in its text).
    let hasCategoryFilter: Bool
    let unreadNotifications: Int
    let onOpenNotifications: () -> Void
    let onOpenFriends: () -> Void
    let onOpenLeaderboard: () -> Void
    let onOpenProfile: () -> Void
    let onOpenStreakInfo: () -> Void
    let onOpenXpInfo: () -> Void
    let onOpenFeedSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let profile {
                topicButton
                Button(action: onOpenStreakInfo) {
                    Label("\(profile.currentStreak)", systemImage: "flame.fill")
                }
                .foregroundStyle(.orange)
                Button(action: onOpenXpInfo) {
                    Label("\(profile.xpToday)/\(profile.xpGoal)", systemImage: "star.fill")
                }
                .foregroundStyle(.yellow)
                .lineLimit(1)
                .fixedSize()
                Spacer(minLength: 4)
                profileButton
                leaderboardButton
                friendsButton
                notificationsButton
            } else {
                Spacer()
                ProgressView().tint(Theme.textTertiary)
                Spacer()
            }
        }
        .font(.caption.bold())
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal)
    }

    // Emoji-only for "no filter" / a bare count when filtered — the web's
    // own label (space-joined category icons) needs a categories list this
    // view doesn't otherwise hold; a short label also just fits this row
    // better now that it's sharing space with streak/XP and 4 icons (a
    // spelled-out "Everything" wrapped the XP label onto two lines here,
    // confirmed live). Accent-colored fill + border when a filter is
    // actually active, rather than the same neutral gray pill either way —
    // the web's own version doesn't need this (its label is a real
    // space-joined list of category icons, self-evidently "something is
    // selected"), but this client's count-only label reads too easily as
    // "just a button" without it, flagged live by the user.
    private var topicButton: some View {
        Button(action: onOpenFeedSettings) {
            Text("\(topicLabel) ▾")
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    hasCategoryFilter ? Theme.accent.opacity(0.25) : Theme.panelAlt,
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(hasCategoryFilter ? Theme.accentBright : .clear, lineWidth: 1.5)
                )
        }
        .foregroundStyle(hasCategoryFilter ? Theme.accentText : Theme.textPrimary)
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
