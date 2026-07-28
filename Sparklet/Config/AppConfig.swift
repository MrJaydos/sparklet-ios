import Foundation

enum AppConfig {
    // Swap to the local Next.js dev server (see sparklet/AGENTS.md — runs on
    // PORT=3001 to avoid clashing with other :3000 servers) while iterating
    // against a local backend.
    static let apiBaseURL = URL(string: "https://sparkletapp.com")!

    // Must exactly match an entry in the backend's ALLOWED_MOBILE_SCHEMES
    // (src/lib/mobile-auth.ts) and project.yml's CFBundleURLTypes — it's an
    // allowlist, not a passthrough, so any other value 400s at /login.
    static let authCallbackScheme = "sparklet-ios"
}
