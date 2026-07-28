import AuthenticationServices
import UIKit

// Drives the existing web /login flow (Google, Apple, magic-link — all
// unchanged) in a system browser context and captures the token the
// backend hands back on completion.
//
// NOT YET SUPPORTED SERVER-SIDE: this expects the backend to accept
// `?client=ios&callback=<scheme>` on /login and, once Auth.js completes,
// redirect to `sparklet://auth?token=<sessionToken>` instead of /feed. That
// endpoint change lives in the sparklet repo and hasn't been built yet —
// see AGENTS.md's auth section. Until then this call will complete the web
// login but the final redirect won't carry a token.
//
// ASWebAuthenticationSession (not WKWebView) is required here: it runs in a
// shared system browser context, so Google's OAuth "disallowed_useragent"
// block on embedded web views doesn't apply, and it intercepts the
// registered callback scheme without ever loading it — the session cookie
// itself is never exposed to the app, only the token in the redirect query.
@MainActor
final class LoginController: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> String {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent("login"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "client", value: "ios"),
            URLQueryItem(name: "callback", value: AppConfig.authCallbackScheme),
        ]

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: AppConfig.authCallbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard
                    let callbackURL,
                    let token = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "token" })?.value
                else {
                    continuation.resume(throwing: AuthError.missingToken)
                    return
                }
                continuation.resume(returning: token)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

enum AuthError: Error {
    case missingToken
}
