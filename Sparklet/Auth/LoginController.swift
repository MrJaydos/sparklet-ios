import AuthenticationServices
import UIKit

// Mirrors the backend's mobile auth contract exactly (sparklet repo:
// src/lib/mobile-auth.ts, src/app/api/auth/mobile-{complete,exchange,session}
// — verified end-to-end there as of 2026-07-28, see AGENTS.md). This is an
// RFC 8252-style code exchange, not a token handed back directly through the
// deep link: a token embedded in a redirect URL sits in browser history and
// OS logs, and an unvalidated scheme could hand it to whatever app the OS
// resolves that scheme to. The one-time code is the only thing that crosses
// the browser/app boundary; the real Bearer token is fetched over a direct
// HTTPS POST from the app itself.
//
// ASWebAuthenticationSession (not WKWebView) is required for step 1: it runs
// in a shared system browser context, so Google's OAuth "disallowed_useragent"
// block on embedded web views doesn't apply.
@MainActor
final class LoginController: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    // Step 1-2: drive /login?mobileScheme=..., capturing the one-time code
    // from the backend's sparklet-ios://auth?code=<code> redirect once the
    // existing Google/Apple/magic-link flow completes.
    private func requestCode() async throws -> String {
        var components = URLComponents(
            url: AppConfig.apiBaseURL.appendingPathComponent("login"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "mobileScheme", value: AppConfig.authCallbackScheme),
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
                    let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(throwing: AuthError.missingCode)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    // Step 3: exchange the one-time code for a Bearer token over a direct
    // HTTPS request — never through the browser/deep-link, so the real
    // credential never travels through a URL. A 60-second-lived, single-use
    // code; an expired or replayed one 401s.
    private func exchangeCode(_ code: String) async throws -> String {
        struct ExchangeRequest: Encodable { let code: String }
        struct ExchangeResponse: Decodable { let token: String; let expires: String }

        let response: ExchangeResponse = try await APIClient.shared.post(
            "api/auth/mobile-exchange",
            body: ExchangeRequest(code: code),
            token: nil
        )
        return response.token
    }

    func signIn() async throws -> String {
        let code = try await requestCode()
        return try await exchangeCode(code)
    }

    // Step 4: DELETE /api/auth/mobile-session revokes this token specifically
    // — the browser's own cookie session (if any) is untouched.
    func signOut(token: String) async {
        try? await APIClient.shared.deleteDiscardingResponse("api/auth/mobile-session", token: token)
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
    case missingCode
}
