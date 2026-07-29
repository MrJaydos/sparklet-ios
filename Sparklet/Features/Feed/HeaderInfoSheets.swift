import SwiftUI

// Mirrors StreakBadge.tsx — explains streaks/freezes when the flame is tapped.
struct StreakInfoView: View {
    let streak: Int
    let longestStreak: Int
    let freezesAvailable: Int
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🔥 Streaks — stay consistent")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("✕") { onClose() }
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(streak > 0
                 ? "You're on a \(streak)-day streak. Complete 10 cards/quizzes a day to keep it going."
                 : "Complete 10 cards/quizzes today to start a streak.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            VStack(spacing: 8) {
                statRow("🔥 Current streak", "\(streak) day\(streak == 1 ? "" : "s")")
                statRow("🏆 Longest streak", "\(longestStreak) day\(longestStreak == 1 ? "" : "s")")
                statRow("🧊 Streak freezes", "\(freezesAvailable) left")
            }

            Text("🧊 Streak freezes: you get 2 each month. They automatically cover a missed day so your streak doesn't break. Miss more days than you have freezes and the streak resets.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(12)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))

        }
        .padding(20)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundStyle(.orange)
        }
    }
}

// Mirrors XpRing.tsx — explains today's XP goal and how to earn it.
struct XpInfoView: View {
    let today: Int
    let goal: Int
    let onClose: () -> Void

    private var done: Bool { today >= goal }
    private var progress: Double { min(1, goal > 0 ? Double(today) / Double(goal) : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("⚡ XP — your daily learning goal")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("✕") { onClose() }
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(done
                 ? "Goal smashed — \(today) XP today. Everything from here is a bonus."
                 : "\(today) of \(goal) XP today — the ring fills as you learn.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            ProgressView(value: progress)
                .tint(done ? .orange : Theme.accent)

            VStack(spacing: 8) {
                xpRow("📖 Read a new card", "+1")
                xpRow("🔁 Recall a review card", "+5")
                xpRow("🧠 Answer a quiz", "+10 right · +2 for trying")
                xpRow("🔮 Lock in a guess", "+2–10 by closeness")
            }

            Text("🔥 Combos: correct quiz and guess answers in a row multiply your XP — ×1.5 from a 3-streak, ×2 from 5, ×3 from 10. One wrong answer resets the run.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(12)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
    }

    private func xpRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.bold()).foregroundStyle(.yellow)
        }
    }
}
