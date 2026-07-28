import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authSession: AuthSession
    @State private var controller = LoginController()
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Sparklet")
                .font(.largeTitle.bold())

            Button {
                Task { await signIn() }
            } label: {
                if isSigningIn {
                    ProgressView()
                } else {
                    Text("Sign in")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
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
