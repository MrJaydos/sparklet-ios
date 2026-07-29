import SwiftUI

// Mirrors the web's src/app/invite/[refId]/page.tsx result screen — a
// native client is always already signed in by the time it can reach this
// (see InviteAPI's doc comment), so there's no login-gate step to show
// here, only the outcome.
struct InviteView: View {
    @ObservedObject var viewModel: InviteViewModel
    let refId: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isLoading {
                ProgressView().tint(Theme.textTertiary)
            } else if let response = viewModel.response {
                Text(emoji(for: response.status))
                    .font(.system(size: 48))
                Text(title(for: response))
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                if response.rewardGranted, let name = response.referrerName {
                    Text("🧊 \(name) just earned a bonus streak freeze for inviting you.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            } else {
                Text("Couldn't load that invite.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }

            Button("Continue to feed") {
                onContinue()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .task {
            await viewModel.accept(refId: refId)
        }
    }

    private func emoji(for status: InviteResponse.Status) -> String {
        switch status {
        case .invalid: return "🔗"
        case .self_: return "🙂"
        case .friended, .already: return "🎉"
        }
    }

    private func title(for response: InviteResponse) -> String {
        switch response.status {
        case .invalid: return "That invite link isn't valid"
        case .self_: return "That's your own invite link"
        case .friended: return "You and \(response.referrerName ?? "them") are now friends!"
        case .already: return "You and \(response.referrerName ?? "them") are already friends"
        }
    }
}
