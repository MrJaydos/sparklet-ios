import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authSession: AuthSession
    @State private var controller = LoginController()
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            // Mirrors the web login page's "✨ Sparklet" wordmark and
            // subtitle (sparklet/src/app/login/page.tsx).
            Text("✨ Sparklet")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Learn something real, one swipe at a time.")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)

            Button {
                Task { await signIn() }
            } label: {
                Group {
                    if isSigningIn {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign in").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
            .disabled(isSigningIn)
            .padding(.top, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.dangerText)
            }
        }
        .padding(24)
    }

    private func signIn() async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let token = try await controller.signIn()
            authSession.signIn(token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
