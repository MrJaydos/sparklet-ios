import SwiftUI

// Ports Feed.tsx's three session-recap/growth slides — checkin, invite, and
// goalReached — the last of the web's feed slide kinds not yet on iOS (see
// AGENTS.md). All three share the same boxed-panel-fills-one-page shape as
// every other feed slide in this app (CardView/QuizCardView/AdSlideView),
// not the web's plain edge-to-edge `h-dvh` section — same reasoning as
// AdSlideView's own comment: visual consistency with the rest of this app's
// feed matters more here than matching a web-only decoration choice. The
// web's ConfettiBurst celebration polish (Celebration.tsx) is deliberately
// not ported — scoped out previously (see AGENTS.md) and unchanged here.

private func recapButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(filled ? .white : Theme.textSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.panelAlt),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(filled ? Color.clear : Theme.border)
            )
    }
}

private struct RecapSlideChrome<Content: View>: View {
    let emoji: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Text(emoji).font(.system(size: 48))
            content
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }
}

// Every-other-session in-feed invite prompt (gated in FeedViewModel.init,
// see `showInviteCard`) — mirrors Feed.tsx's `kind: "invite"` section.
struct InviteSlideView: View {
    let inviteUrl: URL
    let onContinue: () -> Void

    var body: some View {
        RecapSlideChrome(emoji: "🎁") {
            Text("Know someone who'd love this?")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Invite a friend to Sparklet — you'll earn a bonus 🧊 streak freeze when they join.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 12) {
                ShareLink(
                    item: inviteUrl,
                    subject: Text("Join me on Sparklet"),
                    message: Text("Learn something real, one swipe at a time.")
                ) {
                    Text("Invite a friend")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                recapButton("Maybe later", action: onContinue)
            }
            .padding(.top, 4)
        }
    }
}

// Soft session check-in, every 15 cards — mirrors Feed.tsx's `kind:
// "checkin"` section. `sessionViews`/`topicCount` are live FeedViewModel
// state read at render time, not frozen at the moment this slide was
// inserted, matching the web's own live React state.
struct CheckinSlideView: View {
    let sessionViews: Int
    let topicCount: Int
    let inviteUrl: URL
    let onContinue: () -> Void

    var body: some View {
        RecapSlideChrome(emoji: "🌱") {
            Text("You've learned \(sessionViews) thing\(sessionViews == 1 ? "" : "s") across \(topicCount) topic\(topicCount == 1 ? "" : "s")")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Keep going, or come back later — your streak is safe for today.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 12) {
                recapButton("Keep going", filled: true, action: onContinue)
                ShareLink(
                    item: inviteUrl,
                    subject: Text("Sparklet"),
                    message: Text("I just learned \(sessionViews) thing\(sessionViews == 1 ? "" : "s") across \(topicCount) topic\(topicCount == 1 ? "" : "s") on Sparklet ✨")
                ) {
                    Text("Share recap")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.panelAlt, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
                }
            }
            .padding(.top, 4)
        }
    }
}

// Fires once per local calendar day, the first time the daily card-count
// goal is crossed this session — mirrors Feed.tsx's `kind: "goalReached"`
// section (see FeedViewModel.markGoalReached / DailyCardGoal). "Done for
// today" opens ProfileView as this app's nearest equivalent of the web's
// navigation to /profile.
struct GoalReachedSlideView: View {
    let cardsToday: Int
    let dailyGoal: Int
    let sessionViews: Int
    let topicCount: Int
    let onContinue: () -> Void
    let onDone: () -> Void

    var body: some View {
        RecapSlideChrome(emoji: "🏁") {
            Text("Daily goal complete!")
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("\(cardsToday) cards today — you hit your goal of \(dailyGoal). That's \(sessionViews) this session across \(topicCount) topic\(topicCount == 1 ? "" : "s"). Ending on purpose beats endless scrolling.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 12) {
                recapButton("Keep going anyway", filled: true, action: onContinue)
                recapButton("Done for today", action: onDone)
            }
            .padding(.top, 4)
        }
    }
}
