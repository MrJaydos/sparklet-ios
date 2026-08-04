import Foundation

// Parses the one-time code out of the backend's sparklet-ios://auth?code=...
// redirect (see LoginController's own top-of-file comment for the full
// code-exchange contract). Normally intercepted directly by
// ASWebAuthenticationSession's own callback (LoginController.requestCode)
// — but magic-link sign-in can never complete that way: confirming the
// emailed link means leaving that session's sandboxed browser for Mail/
// Safari, a separate process ASWebAuthenticationSession's callback simply
// can't observe. The OS delivers the eventual sparklet-ios://auth redirect
// as a plain app-open instead, caught by SparkletApp's .onOpenURL — this is
// the parser for that path. Google/Apple OAuth never hit this: they
// complete within the ASWebAuthenticationSession tab itself.
enum AuthCallback {
    static func code(from url: URL) -> String? {
        guard url.host == "auth" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
    }
}
