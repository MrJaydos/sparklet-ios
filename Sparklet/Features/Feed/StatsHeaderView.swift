import SwiftUI

// Kept visually and logically separate, per AGENTS.md: the streak/XP ring
// answers "did I hit my XP today", the (unused here yet) card-count goal
// answers a different question and should never be merged into this row.
struct StatsHeaderView: View {
    let profile: ProfileResponse?

    var body: some View {
        HStack(spacing: 16) {
            if let profile {
                Label("\(profile.currentStreak)", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
                Label("\(profile.xpToday)/\(profile.xpGoal) XP", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
                Spacer()
            } else {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
        .font(.subheadline.bold())
        .padding(.horizontal)
    }
}
